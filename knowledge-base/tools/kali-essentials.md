# Kali Linux Essential Tools Reference

> Quick reference for the most important tools. Use this to pick the right tool for the job.

## Reconnaissance & OSINT

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| nmap | Port scanning, service detection | `nmap -sC -sV -oA out TARGET` |
| masscan | Ultra-fast port scanning | `masscan -p1-65535 TARGET --rate=1000` |
| rustscan | Fast Rust-based scanner | `rustscan -a TARGET -- -sC -sV` |
| subfinder | Passive subdomain enum | `subfinder -d DOMAIN -o subs.txt` |
| amass | Subdomain enumeration | `amass enum -passive -d DOMAIN` |
| theHarvester | Email/name/subdomain gathering | `theHarvester -d DOMAIN -b all` |
| dnsrecon | DNS enumeration | `dnsrecon -d DOMAIN -t std` |
| dnsenum | DNS enumeration | `dnsenum DOMAIN` |
| fierce | DNS recon | `fierce --domain DOMAIN` |
| whois | Domain registration info | `whois DOMAIN` |
| recon-ng | OSINT framework | `recon-ng` |
| maltego | Visual link analysis | GUI tool |
| sherlock | Username OSINT | `sherlock USERNAME` |
| whatweb | Web tech fingerprint | `whatweb -a 3 URL` |
| wafw00f | WAF detection | `wafw00f URL` |

## Web Application Testing

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| burpsuite | Web proxy/scanner | GUI — intercept, scan, repeat |
| gobuster | Dir/DNS/vhost brute force | `gobuster dir -u URL -w WORDLIST` |
| feroxbuster | Recursive dir brute force | `feroxbuster -u URL -w WORDLIST` |
| ffuf | Fuzzer (dir, params, vhosts) | `ffuf -u URL/FUZZ -w WORDLIST` |
| dirsearch | Directory scanning | `dirsearch -u URL` |
| nikto | Web vuln scanner | `nikto -h URL` |
| nuclei | Template-based vuln scanner | `nuclei -u URL -t cves/` |
| sqlmap | SQL injection automation | `sqlmap -u "URL?id=1" --batch --dbs` |
| wpscan | WordPress scanner | `wpscan --url URL --enumerate vp,vt,u` |
| dalfox | XSS scanner | `dalfox url "URL?q=test"` |
| commix | Command injection | `commix -u "URL?param=test"` |
| wfuzz | Web fuzzer | `wfuzz -c -w WORDLIST URL/FUZZ` |
| sslscan | SSL/TLS analysis | `sslscan TARGET` |
| testssl | SSL/TLS testing | `testssl.sh TARGET` |

## Exploitation

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| metasploit | Exploitation framework | `msfconsole` |
| searchsploit | Exploit database search | `searchsploit PRODUCT VERSION` |
| msfvenom | Payload generation | `msfvenom -p PAYLOAD LHOST=IP LPORT=PORT -f FORMAT` |

## Password Attacks

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| hydra | Online brute force | `hydra -l USER -P WORDLIST PROTOCOL://TARGET` |
| john | Offline hash cracking | `john --wordlist=WORDLIST hashes.txt` |
| hashcat | GPU hash cracking | `hashcat -m MODE hashes.txt WORDLIST` |
| medusa | Online brute force | `medusa -h TARGET -u USER -P WORDLIST -M MODULE` |
| crackmapexec | Network auth testing | `crackmapexec smb TARGET -u USER -p PASS` |
| cewl | Custom wordlist from site | `cewl URL -d 2 -m 5 -w wordlist.txt` |
| crunch | Wordlist generation | `crunch MIN MAX CHARSET -o wordlist.txt` |

## Active Directory

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| bloodhound | AD attack path mapping | `bloodhound-python -u USER -p PASS -d DOMAIN -c All` |
| impacket | AD exploitation suite | Multiple tools (see below) |
| evil-winrm | WinRM shell | `evil-winrm -i TARGET -u USER -p PASS` |
| kerbrute | Kerberos brute force | `kerbrute userenum --dc DC -d DOMAIN users.txt` |
| crackmapexec | Multi-protocol AD tool | `crackmapexec smb TARGET -u USER -p PASS` |
| enum4linux | SMB/NetBIOS enum | `enum4linux -a TARGET` |
| rpcclient | RPC enumeration | `rpcclient -U "user%pass" TARGET` |
| ldapsearch | LDAP queries | `ldapsearch -x -H ldap://DC -b "dc=domain,dc=com"` |

### Impacket Suite
```bash
impacket-psexec      # Remote shell via SMB
impacket-wmiexec     # Remote shell via WMI
impacket-smbexec     # Remote shell via SMB
impacket-dcomexec    # Remote shell via DCOM
impacket-atexec      # Remote execution via Task Scheduler
impacket-secretsdump # Dump credentials (SAM/NTDS/LSA)
impacket-GetUserSPNs # Kerberoasting
impacket-GetNPUsers  # AS-REP Roasting
impacket-getTGT      # Request TGT
impacket-ticketer    # Create tickets (Golden/Silver)
impacket-mssqlclient # MSSQL client
impacket-smbclient   # SMB client
```

## Post-Exploitation

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| linpeas | Linux privesc enum | `./linpeas.sh` |
| winpeas | Windows privesc enum | `.\winpeas.exe` |
| pspy | Process monitoring (no root) | `./pspy64` |
| chisel | TCP tunneling | Server: `chisel server -p 8080 --reverse` |
| ligolo-ng | Network pivoting | Modern tunneling framework |
| proxychains | Proxy routing | `proxychains4 COMMAND` |
| socat | Relay/tunnel | `socat TCP-LISTEN:PORT,fork TCP:TARGET:PORT` |

## Wireless

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| aircrack-ng | WiFi cracking suite | `airmon-ng`, `airodump-ng`, `aircrack-ng` |
| wifite | Automated WiFi attacks | `wifite` |
| bettercap | Network attack framework | `bettercap -iface IFACE` |
| kismet | Wireless detection | `kismet` |

## Networking

| Tool | Purpose | Quick Usage |
|------|---------|-------------|
| wireshark | Packet capture/analysis | GUI or `tshark -i IFACE` |
| tcpdump | CLI packet capture | `tcpdump -i IFACE -w capture.pcap` |
| netcat | TCP/UDP connections | `nc -lvnp PORT` (listen) |
| responder | LLMNR/NBT-NS poisoning | `responder -I IFACE` |
| bettercap | MITM framework | `bettercap -iface IFACE` |
| arpspoof | ARP spoofing | `arpspoof -i IFACE -t TARGET GATEWAY` |

## Wordlists

```bash
# Built-in
/usr/share/wordlists/rockyou.txt          # Passwords (classic)
/usr/share/seclists/                       # SecLists collection

# Key SecLists paths
/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt
/usr/share/seclists/Discovery/Web-Content/common.txt
/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt
/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt
/usr/share/seclists/Passwords/Common-Credentials/10k-most-common.txt
/usr/share/seclists/Usernames/top-usernames-shortlist.txt
/usr/share/seclists/Fuzzing/LFI/LFI-gracefulsecurity-linux.txt
```
