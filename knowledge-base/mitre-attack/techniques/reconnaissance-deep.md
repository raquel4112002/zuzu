# Reconnaissance — Deep Dive (TA0043)

> Complete methodology for passive and active reconnaissance before engagement.
> Maps to MITRE ATT&CK TA0043 — Reconnaissance.

---

## Passive Reconnaissance (No Target Interaction)

### Domain & DNS Intelligence
```bash
# Subdomain enumeration (passive)
subfinder -d TARGET -silent -o subs.txt
amass enum -passive -d TARGET -o amass-subs.txt
assetfinder TARGET | sort -u
# Combine results
cat subs.txt amass-subs.txt | sort -u > all-subs.txt

# Certificate transparency logs
curl -s "https://crt.sh/?q=%25.TARGET&output=json" | jq -r '.[].name_value' | sort -u
# Or use web: https://crt.sh/?q=%25.target.com

# DNS records (passive)
dig any TARGET
dig TARGET mx
dig TARGET ns
dig TARGET txt
host -t any TARGET
dnsdumpster.com (web)

# Reverse DNS
dig -x IP_ADDRESS
nmap -sL SUBNET/24  # List scan — reverse DNS only

# Zone transfer attempt
dig axfr @NS_SERVER TARGET
host -l TARGET NS_SERVER
```

### OSINT — People & Organization
```bash
# Email harvesting
theHarvester -d TARGET -b all -f harvest-results
# Sources: google, bing, linkedin, twitter, dnsdumpster, etc.

# LinkedIn reconnaissance
# Search: site:linkedin.com "TARGET company"
# Gather: names, titles, tech stack from job postings

# Google dorking
# site:TARGET filetype:pdf
# site:TARGET filetype:xlsx
# site:TARGET filetype:docx
# site:TARGET filetype:sql
# site:TARGET filetype:log
# site:TARGET filetype:bak
# site:TARGET filetype:conf
# site:TARGET inurl:admin
# site:TARGET inurl:login
# site:TARGET intitle:"index of"
# site:TARGET ext:env
# "TARGET" password | credential | secret | key
# "TARGET" filetype:xml inurl:sitemap

# GitHub/GitLab recon
# Search for TARGET in code, commits, issues
# Look for: API keys, passwords, internal URLs, config files
# Tools: gitrob, trufflehog, gitleaks
trufflehog github --org=TARGET_ORG --only-verified
gitleaks detect --source=REPO_URL

# Pastebin / paste sites
# Search: site:pastebin.com "TARGET"
# Tools: pspy, pastehunter
```

### Infrastructure Intelligence
```bash
# Shodan
shodan search "hostname:TARGET"
shodan host TARGET_IP
shodan search "ssl:TARGET org:TARGET_ORG"
# Useful filters: port, city, country, os, product

# Censys
censys search "TARGET"
censys view TARGET_IP

# WHOIS
whois TARGET
whois TARGET_IP

# Historical data
# Wayback Machine: web.archive.org
# Check old versions of the website for hidden pages, endpoints, leaked info
waybackurls TARGET | sort -u > wayback-urls.txt

# IP range discovery
# ARIN/RIPE/APNIC whois
whois -h whois.arin.net "n TARGET_ORG"
# BGP info
# https://bgp.he.net/

# Technology profiling
whatweb -a 1 http://TARGET    # Passive mode
builtwith.com (web)
wappalyzer (browser extension)
```

### Social Media OSINT
```bash
# Username search across platforms
sherlock USERNAME
# Check: Twitter/X, Instagram, Facebook, Reddit, GitHub, etc.

# Metadata extraction from public documents
exiftool downloaded_file.pdf
# Look for: author names, software versions, internal paths, GPS coords

# Image OSINT
# Reverse image search: Google Images, TinEye, Yandex
exiftool image.jpg  # EXIF data — location, camera, timestamps
```

---

## Active Reconnaissance (Touches the Target)

### Port Scanning
```bash
# Quick scan — top ports
nmap -sV -sC -oA nmap-quick TARGET

# Full TCP scan
nmap -sS -p- --min-rate 5000 -oA nmap-full TARGET
# Then service scan on discovered ports:
nmap -sV -sC -p PORT1,PORT2,PORT3 -oA nmap-services TARGET

# UDP scan (slow but important)
nmap -sU --top-ports 50 --min-rate 1000 -oA nmap-udp TARGET
# Common interesting UDP: 53 (DNS), 69 (TFTP), 123 (NTP), 161 (SNMP), 500 (IKE)

# Fast scanning alternatives
masscan -p1-65535 TARGET --rate=1000 -oJ masscan.json
rustscan -a TARGET -- -sC -sV

# Script scanning for specific services
nmap --script=smb-enum-shares,smb-os-discovery -p 445 TARGET
nmap --script=http-enum,http-title -p 80,443,8080 TARGET
nmap --script=snmp-info -p 161 -sU TARGET
nmap --script=vuln TARGET  # Vulnerability scripts
```

### Web Reconnaissance
```bash
# Screenshot all web services
gowitness file -f urls.txt
eyewitness --web -f urls.txt

# Crawl and spider
gospider -s http://TARGET -d 3 -o spider-results
hakrawler -url http://TARGET -depth 3

# JS file analysis (find endpoints, secrets)
# Download all JS files, then:
linkfinder -i http://TARGET/script.js -o cli
# Or bulk:
cat js-urls.txt | while read url; do linkfinder -i "$url" -o cli; done

# robots.txt & sitemap
curl http://TARGET/robots.txt
curl http://TARGET/sitemap.xml
curl http://TARGET/crossdomain.xml
curl http://TARGET/.well-known/security.txt

# API discovery
ffuf -u http://TARGET/api/FUZZ -w /usr/share/seclists/Discovery/Web-Content/api/api-endpoints.txt
ffuf -u http://TARGET/FUZZ -w /usr/share/seclists/Discovery/Web-Content/swagger.txt
curl http://TARGET/swagger.json
curl http://TARGET/api-docs
curl http://TARGET/openapi.json
```

### Service Enumeration (After Port Discovery)
```bash
# See knowledge-base/checklists/enumeration-checklist.md for per-port enumeration
# Quick reference for most common:

# SSH (22)
ssh -v TARGET  # Banner grab, auth methods
nmap --script=ssh-auth-methods -p 22 TARGET

# HTTP/HTTPS (80/443)
whatweb http://TARGET
curl -sI http://TARGET
gobuster dir -u http://TARGET -w /usr/share/seclists/Discovery/Web-Content/common.txt

# SMB (445)
enum4linux -a TARGET
smbclient -L //TARGET -N
crackmapexec smb TARGET

# SNMP (161)
snmpwalk -v2c -c public TARGET
onesixtyone -c /usr/share/seclists/Discovery/SNMP/snmp.txt TARGET

# LDAP (389/636)
ldapsearch -x -H ldap://TARGET -b "" -s base namingContexts
nmap --script=ldap-rootdse -p 389 TARGET
```

---

## Organizing Recon Output

```bash
# Create target directory structure
mkdir -p recon/{nmap,web,osint,dns,screenshots}

# File naming convention
# recon/nmap/TARGET-full.nmap
# recon/dns/subdomains.txt
# recon/web/directories.txt
# recon/osint/emails.txt
# recon/screenshots/

# Combine and deduplicate
sort -u recon/dns/subs-*.txt > recon/dns/all-subdomains.txt

# Resolve subdomains to IPs
cat recon/dns/all-subdomains.txt | dnsx -silent -a -resp > recon/dns/resolved.txt

# Find live HTTP services
cat recon/dns/all-subdomains.txt | httpx -silent -title -status-code -tech-detect > recon/web/live-services.txt
```

---

## Decision Tree: What Recon to Do

```
New target (domain)  → Subdomain enum → DNS records → Certificate transparency
                      → OSINT (emails, people, tech stack)
                      → Google dorks → GitHub search → Wayback Machine
                      → Resolve all subdomains → Port scan live hosts
                      → Screenshot web services → Fingerprint tech

New target (IP only)  → Port scan (full TCP + top UDP) → Service enum
                      → Reverse DNS → WHOIS → Shodan lookup
                      → Web fingerprinting if HTTP found

Internal network      → Ping sweep → Port scan subnet → SMB enum
                      → SNMP walk → LDAP/AD enum → Share hunting
```
