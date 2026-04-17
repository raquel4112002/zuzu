# OWASP Top 10 (2021) — Testing Checklist

## A01:2021 — Broken Access Control

- [ ] Test IDOR: change IDs in URLs/API calls (e.g., /api/user/1 → /api/user/2)
- [ ] Test forced browsing: access admin pages without auth
- [ ] Test horizontal privilege escalation: access other users' data
- [ ] Test vertical privilege escalation: perform admin actions as regular user
- [ ] Check JWT manipulation: change role/user claims
- [ ] Test HTTP method tampering: GET vs POST vs PUT vs DELETE
- [ ] Check CORS misconfiguration
- [ ] Test directory traversal: `../../../etc/passwd`
- [ ] Check missing function-level access controls on API endpoints

## A02:2021 — Cryptographic Failures

- [ ] Check for HTTP (no TLS) on sensitive pages
- [ ] Test for weak TLS versions/ciphers: `sslscan TARGET`, `testssl.sh TARGET`
- [ ] Look for sensitive data in URLs (tokens, passwords in query strings)
- [ ] Check for exposed backup/config files with credentials
- [ ] Verify password storage (look for MD5/SHA1 without salt in dumps)
- [ ] Check for hardcoded secrets in JS/source

## A03:2021 — Injection

- [ ] SQL Injection: `' OR 1=1--`, `" OR 1=1--`, `sqlmap`
- [ ] NoSQL Injection: `{"$gt":""}`, `{"$ne":"invalid"}`
- [ ] OS Command Injection: `; id`, `| whoami`, `$(id)`, `` `id` ``
- [ ] LDAP Injection: `*)(objectClass=*`
- [ ] XPath Injection: `' or '1'='1`
- [ ] Template Injection (SSTI): `{{7*7}}`, `${7*7}`, `<%= 7*7 %>`
- [ ] Header Injection: CRLF `%0d%0a`

## A04:2021 — Insecure Design

- [ ] Check for rate limiting on login/reset/OTP endpoints
- [ ] Test business logic flaws (negative quantities, price manipulation)
- [ ] Check password reset flow for weaknesses
- [ ] Test for predictable tokens/session IDs
- [ ] Check for missing anti-automation on sensitive operations

## A05:2021 — Security Misconfiguration

- [ ] Check default credentials on admin panels, databases, services
- [ ] Look for exposed error messages with stack traces
- [ ] Check unnecessary HTTP methods (PUT, DELETE, TRACE)
- [ ] Test for directory listing enabled
- [ ] Check security headers: `X-Frame-Options`, `CSP`, `X-Content-Type-Options`, `HSTS`
- [ ] Look for exposed admin interfaces (/admin, /manager, /console)
- [ ] Check for unnecessary features/ports/services
- [ ] Check cloud storage permissions (S3 buckets, Azure blobs)

## A06:2021 — Vulnerable and Outdated Components

- [ ] Identify all technologies and versions (`whatweb`, `wappalyzer`)
- [ ] Check CVE databases: `searchsploit`, `nuclei -t cves/`
- [ ] Check JavaScript libraries for known vulns (retire.js)
- [ ] Test for outdated CMS/plugins: `wpscan`, `joomscan`
- [ ] Check server software versions in headers

## A07:2021 — Identification and Authentication Failures

- [ ] Test for username enumeration (different responses for valid/invalid users)
- [ ] Check password policy (weak passwords allowed?)
- [ ] Test for brute force protection (account lockout, rate limiting)
- [ ] Check session management:
  - [ ] Session fixation
  - [ ] Session doesn't expire
  - [ ] Session ID in URL
  - [ ] Session not invalidated on logout
- [ ] Test for credential stuffing protection
- [ ] Check multi-factor authentication bypass
- [ ] Test password reset token security (predictable? long-lived?)

## A08:2021 — Software and Data Integrity Failures

- [ ] Check for insecure deserialization (ysoserial, Java/PHP/Python/Node)
- [ ] Test CI/CD pipeline security
- [ ] Check for unsigned/unverified updates
- [ ] Test for mass assignment / parameter pollution

## A09:2021 — Security Logging and Monitoring Failures

- [ ] Check if login failures are logged
- [ ] Check if sensitive operations are logged
- [ ] Test if logs are accessible/tamper-proof
- [ ] (Usually assessed through interviews, not direct testing)

## A10:2021 — Server-Side Request Forgery (SSRF)

- [ ] Test URL parameters that fetch external resources
- [ ] Try internal targets: `http://127.0.0.1`, `http://localhost`
- [ ] Try cloud metadata: `http://169.254.169.254/latest/meta-data/`
- [ ] Test with different protocols: `file://`, `gopher://`, `dict://`
- [ ] Try bypass techniques: decimal IP, IPv6, DNS rebinding
- [ ] Check for blind SSRF (use Burp Collaborator/webhook.site)
