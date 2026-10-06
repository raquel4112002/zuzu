# Learning: management (easy) — 2026-10-04
tags: spa,encrypted-js,aes-gcm,client-side,nginx,crypto

## Signal → vuln class (when you see X, pursue Y)
- a 'Loading…' SPA whose index.html fetches assets/app.enc and AES-GCM-decrypts+evals it with an INLINE key in the <script> -> the real app logic/endpoints are in app.enc; decrypt it client-side to recover the attack surface

## What worked (the insight, generalized — NOT box-specific steps)
- (open) grab KEY + iv(first 12 bytes) from the HTML, decrypt assets/app.enc with AES-GCM -> read the recovered JS for routes/creds/vulns

## Dead-ends (don't waste time here next time)
- treating the landing HTML as content/flag; dir-busting a client-rendered SPA; gpt-oss/gemma both failed here

## CVE / technique refs
- obfuscator-io-js-deobfuscation (adjacent), web-browsing
