# Learning: cohort (medium) — 2026-10-11
tags: ssrf,marimo,packagekit,cve-2026-41651,privesc

## Signal → vuln class (when you see X, pursue Y)
- wildcard TLS cert SPA with a fetch-and-preview SSRF + a loopback notebook service -> enumerate the nginx /status endpoint and look for an internal-notes vhost that proxies the loopback service

## What worked (the insight, generalized — NOT box-specific steps)
- obfuscator.io bundle decrypts to a client app whose /api/validate is a GET-only SSRF; the real foothold is the marimo pre-auth /terminal/ws RCE (CVE-2026-39987) reachable only through a hidden nb-*.domain vhost that proxies loopback:8888 with websocket upgrade headers; privesc is PackageKit TOCTOU CVE-2026-41651 (install .deb as root via SIMULATE flag race)

## Dead-ends (don't waste time here next time)
- brute-forcing sudo (user NOT in sudoers), hunting a /root/maint-*.sh trigger that never runs, kernel-exploit paths (userns disabled + modprobe blacklists for algif_aead and esp/rxrpc)

## CVE / technique refs
- CVE-2026-39987,CVE-2026-41651,CVE-2026-75149
