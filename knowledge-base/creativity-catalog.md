# Creativity Catalog — Universal Attack Patterns

> **When stuck on a novel target, read this. Don't run more nmap.**
>
> This file is *patterns*, not products. Every entry is a class of bug
> that recurs across ages, languages, and stacks. Ask of each: *could
> this pattern apply here, even though I haven't seen it on this exact
> stack?*

How to use:

1. Pick the entry whose preconditions match what you've already seen.
2. Generate one specific hypothesis for the current target.
3. Add it to the bank: `bash scripts/hypotheses.sh add "..." --falsifier "..."`.
4. Repeat for at least 3 patterns before giving up.

---

## A. Parser confusion (different components disagree about the input)

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **HTTP request smuggling (CL.TE / TE.CL / TE.TE)** | Two HTTP processors in series (LB → app, CDN → origin) | `smuggler.py` against the front; `\r\n` injection in `Transfer-Encoding` |
| **Path normalisation mismatch** | Reverse proxy + app stack | `curl 'http://t/admin/..%2f..%2fpublic/'`; `%2e%2e/`, `..;/`, double slashes |
| **JSON parser quirks** | Backend in language A, validator in language B | duplicate keys (`{"role":"user","role":"admin"}`), `__proto__`, big numbers, NaN, +Infinity, comments |
| **XML / SOAP parser** | Anything quoting "enterprise" | XXE (`<!ENTITY xxe SYSTEM "file:///etc/passwd">`), XInclude, billion laughs |
| **Multipart parser** | Upload endpoint | filename `"; rce=$(id)"` (legacy parsers), CRLF in field name, dual `Content-Disposition` |
| **Charset/encoding ambiguity** | UTF-7, UTF-16-BOM, mixed encodings | `<%2Fscript>`, UTF-7 `+ADw-script+AD4-`, IDN homoglyphs |
| **Polyglot files** | Image/PDF/zip uploads with logic | a file that's both a valid PNG and a valid PHP/ZIP |
| **Length / type confusion** | C-backed parsers, integer fields | negative length, `INT_MAX+1`, `0x80000000`, empty array where object expected |

---

## B. Trust boundary violations

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **Header spoofing across the proxy** | App reads `X-Forwarded-For`, `X-Real-IP`, `X-Original-URL`, `X-Rewrite-URL` | `curl -H 'X-Forwarded-For: 127.0.0.1' …/admin` |
| **Host-header rerouting** | Multi-tenant or vhost-based dispatch | `curl -H 'Host: internal-admin.local' http://target/` |
| **SSRF to localhost / metadata** | Server fetches user URLs | `?url=http://127.0.0.1:8080/admin`, `…/169.254.169.254/latest/meta-data/`, `gopher://`, file://, dict:// |
| **DNS rebinding** | Server fetches user URL once-then-trust | hostname that resolves to public then localhost |
| **CRLF / log injection upstream** | App passes user input into upstream HTTP | `?q=foo%0d%0aX-Admin:%20true` |
| **Response splitting** | Outdated app server | header value with `\r\n\r\n<html>…` |
| **Internal-only trust** | "It's only on the cluster network" | enumerate sibling pods, internal API, sidecar admin |

---

## C. Authentication & authorisation edges

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **JWT `alg: none`** | JWTs in cookies/headers | re-sign with `{"alg":"none"}`, drop signature |
| **JWT key confusion (HS256 ↔ RS256)** | App uses RS256 in prod | re-sign with HS256 using public key as secret |
| **Weak HMAC secret** | JWT or session signing | `hashcat -m 16500` against the token |
| **Mass assignment** | `User.update(req.body)` style | POST with extra `{"role":"admin","is_admin":true}` |
| **IDOR (predictable IDs, sequential, GUIDv1)** | `/users/123` | iterate IDs, GUIDv1 timestamp prediction |
| **Race / TOCTOU** | "you can only redeem once", "balance check" | parallel requests with same token |
| **Session fixation / desync** | Login form sets cookie before login | log in with attacker-known cookie |
| **2FA bypass** | Step-up flow | replay step-1 token, skip /verify2fa, response-tamper |
| **Password reset** | Token in email | predictable token, leaked Referer, host-header poisoning, time-window window |
| **OAuth / SSO** | Third-party login | open redirect → token theft, state param missing, scope creep, mix-up attack |
| **API key in JS bundle / mobile app** | "keep it client-side" | `grep -roE 'AIza[0-9A-Za-z_-]{35}' …` |
| **Deny-list bypass** | `if (path.startsWith('/admin'))` | `/Admin`, `/admin/`, `/admin..`, `//admin`, `/%61dmin` |
| **HTTP method override** | `?_method=PUT` or `X-HTTP-Method-Override` | swap GET/POST guard |
| **Role / scope param tampering** | client sends role | flip "user" → "admin" in client storage / form |

---

## D. Server-side execution

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **SQLi (in)** | input → DB | error-based, time-based, second-order |
| **NoSQLi** | Mongo/Redis | `{"$ne": null}`, JS injection in `$where` |
| **Command injection** | filename/URL/CLI flag passes user input | `;id`, `\`id\``, `$(id)`, `\|id`, newline injection |
| **SSTI (Jinja2, ERB, Twig, Velocity, Freemarker, Lua)** | template renders user data | `{{7*7}}`, `${{7*7}}`, `<%= 7*7 %>`, `#{7*7}` |
| **Deserialisation** | cookies/POST contain serialised objects | Java (ysoserial), .NET (ysoserial.net), PHP (phpggc), Python pickle, Ruby Marshal |
| **Sandbox escape** | Lua/JS/Python sandboxes | dunder traversal, FFI, prototype pollution, child_process |
| **LDAP injection** | search filter built from input | `*)(uid=*)(\|(uid=*`, `*)(objectClass=*` |
| **Code eval endpoints** | dev/debug feature left on | `/eval`, `/exec`, `/console`, `/debug`, `/_query` |
| **Polymorphic upload → exec** | upload + serve | `.phtml` if `.php` blocked, `.htaccess` upload, ASP `;.jpg`, JSP polyglot |
| **Archive extraction** | unzip, tar, plugin install | zip slip (`../../../etc/cron.d/x`), symlink in tar, CVE-2025-4517 (tarfile filter bypass) |
| **Image processing** | ImageMagick, exiftool, ffmpeg | MSL/MVG payloads, exiftool DjVu RCE, ffmpeg HLS SSRF |

---

## E. Cryptographic / token weaknesses

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **Predictable token / nonce** | Math.random, time-seeded | collect tokens, fit RNG |
| **ECB mode** | repeating ciphertext blocks | `cryptanalyze` byte-flip cookies |
| **Padding oracle** | error differs by validity | Padbuster on cookies/CBC |
| **Truncated tag / weak HMAC** | 32-bit or 64-bit auth tag | length-extension, brute |
| **Reusing nonce / IV** | encrypt twice with same nonce | XOR ciphertexts |
| **Subtle compare bypass** | `==` instead of constant-time | timing attack on auth |

---

## F. Identity & data edges

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **Unicode confusables in usernames** | Identity lookup | register `аdmin` (Cyrillic а) |
| **Case-folding collisions** | DB collation | `ADMIN` vs `Admin` vs `aDMIN` |
| **Trailing whitespace / null byte** | trim mismatch | `admin ` (space), `admin%00` |
| **Email parsing** | `+`, `.`, comments, quoted local | `admin+evil@…`, `"a@b"@c.d`, RFC-5321 vs 5322 |
| **Phone number / OTP** | format normalisation | leading +, leading zeros, country code spoofing |

---

## G. Operations / deployment leftovers

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **`.git/` in webroot** | naive deploy | `curl …/.git/HEAD`, `git-dumper` |
| **`.env`, `config.yml`, `id_rsa`, `*.bak`** | accidental commit / copy | gobuster with `raft-large-files.txt` |
| **Docker socket exposed** | `/var/run/docker.sock` mounted | `docker -H unix:///var/run/docker.sock ps` |
| **Kubelet readonly :10255** / **etcd :2379** | flat cluster | `curl …:10255/pods`, etcd dump |
| **Node exporter, Prometheus, Grafana on web** | `/metrics`, `/api/datasources` | `curl …/metrics`, default Grafana admin/admin |
| **Default vendor creds** | unchanged install | manufacturer:manufacturer, admin:admin, etc. (try first) |
| **Internal admin port on different host** | "split admin" | nmap each host on 8080,9090,10000,15672,5601 |
| **Shadow services** | dev branches deployed | `dev.target`, `staging.target`, `old.target`, IP probe of nearby /24 |
| **Backup files** | `.bak`, `.old`, `~`, `.swp`, `.orig` | dirbust with curated wordlist |
| **Debug headers / panels** | `Strapi`, `Django debug`, Werkzeug pin | `?__debug__`, `/debugbar`, `/admin/__debug__` |
| **Outdated dependency in JS bundle** | webpack `vendor.js` | `retire.js` against the bundle |
| **CI/CD artefacts** | exposed CI logs | search GitHub for org → leaked tokens, `.github/workflows/*.yml` |

---

## H. Side channels & timing

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **User-existence oracles** | login error differs ("user not found" vs "wrong pass") | login + watch response time / size |
| **Cache-based oracles** | personalised content cached | timing diff on first vs subsequent request |
| **Network-level side channel** | `nft` / WAF blocks reveal info | RST vs DROP, ICMP unreachable patterns |

---

## I. Supply chain / trust transitivity

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **Dependency confusion** | private npm/pypi names guessable | check `package-lock.json` for internal-looking names not on public registry |
| **Compromised plugin / theme** | WP/Joomla/Drupal | `wpscan --enumerate vt`, plugin-specific CVEs |
| **Mirror / CDN takeover** | typo'd CDN host or expired bucket | dig hosts in HTML for NXDOMAIN / dangling references |
| **Vendor backdoor / shared key** | re-used SSH key, default cert | hashes of common vendor keys, default-cert fingerprint check |

---

## J. Out-of-band & async

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **Email / DNS / HTTP callback** | server fetches a thing in response to user input | use a Burp Collaborator–style canary (`bash scripts/canary.sh` or webhook.site) |
| **Job queue / background worker** | upload now, processed later | give the worker time, watch for connections |
| **Webhook auth missing / forgeable** | inbound webhooks | spoof source IP, replay payloads, predictable secret |

---

## K. The "looks static but isn't" pattern

Any of these can be live attack surface:

- A "static" PDF that runs JS (XFA/AcroForm).
- A "config file" the app re-reads on every request.
- An image whose EXIF / IPTC fields are reflected to admin tools.
- A "log file" tailed and rendered in an admin UI without escaping.
- A static site generator that runs a build hook on commit.
- A `.well-known/openid-configuration` whose `authorization_endpoint`
  the SSO library trusts blindly.

---

## L. Operator / human factor (often the shortest chain)

| Pattern | Trigger | Sample falsifier |
|---|---|---|
| **Stored XSS that fires in admin** | user content rendered in admin panel | inject `<script>fetch('/admin/api/users')…</script>` |
| **Pivot via the admin's session** | XSS or CSRF + admin's higher rights | call admin-only endpoints from XSS payload |
| **Open registration → privileged role** | self-signup defaults to `member` but hidden role params accepted | mass-assign role on signup |
| **Forgotten / left-by-the-vendor accounts** | `vendor`, `support`, `service`, `backup`, `monitoring` | spray these usernames first |
| **Customer support tooling** | internal support portal exposed | `/support`, `/helpdesk`, `/internal/admin` |

---

## M. The chain mindset

A finding is rarely the prize. The prize is the *chain*. After every
confirmed hypothesis, ask:

1. **What does this give me access to that I didn't have?** (read-only?
   write? exec? identity?)
2. **What component does that thing trust?** (e.g., the queue processor
   trusts the file in the upload dir.)
3. **What does that component touch that I want?** (e.g., the queue
   processor runs as root.)
4. **Is there a primitive between A and B I'm missing?** (e.g., I have
   write to the upload dir → can I influence what the processor reads?
   Can I race it?)

Add the answer as the next hypothesis. Repeat until you reach the
crown jewel (root, DA, the flag, data exfil).

---

## How this catalog stays useful

When you discover a new universal pattern, add it here. Keep entries
*pattern*-shaped: a class of bug, a generic precondition, a one-line
falsifier. If you find yourself writing a product name, you're writing
a runbook — put it in `playbooks/runbooks/` instead.
