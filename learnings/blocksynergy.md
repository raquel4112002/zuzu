# Learning: blocksynergy (hard) — 2026-10-06
tags: linux,web,blockchain,ssrf,rce,privesc,backup,docker,python

## Signal → vuln class (when you see X, pursue Y)
- root cron tars a USER-WRITABLE tree that a root daemon later restores from a verified archive -> plant a SUID/uid=0-header payload INSIDE that tree; root's own genuine archive carries it home

## What worked (the insight, generalized — NOT box-specific steps)
- Two insights. (1) A sink whose URL parser drops everything after '/' and mangles spaces is beatable, not fatal: use ${IFS} for spaces and base32 (never base64 - its alphabet has '/') to smuggle arbitrary data: echo${IFS}<B32>|base32${IFS}-d|bash. That converts a crippled injection into unrestricted RCE and removes all payload constraints. (2) For backup/restore privesc the trigger lives in the BACKED-UP tree itself, not in a separate requests dir, and you do NOT need to win a TOCTOU race or forge a checksum: if the tree is user-writable, wait for root's own */5 backup tick so root's checksummed archive contains your payload, then trigger the restore - root extracts its own verified archive as root. tar honours uid/gid/mode declared in archive headers, so a non-root process can craft members claiming uid=0 mode=4755.

## Dead-ends (don't waste time here next time)
- Hunting the trigger in /var/restore_work (wrong dir) and sizing test windows to an imagined ~10-minute poll when real latency was ~9s. Hammering the per-IP-limited vsftpd from scripts, which blinded the root daemon ('Backup not found on the Server!'). Uploading my own archive / pre-creating the tar -> guaranteed checksum mismatch. Trusting the writeup's 'inotify TOCTOU race' as the only route. Over-maintaining an SSRF chain after an on-box shell existed (localhost curls the source-IP-gated panel directly). Malformed JSON to a stateful shared ledger -> poisoned the box, forced a reset.

## CVE / technique refs
- BlockSynergy HTB; base32 loader; tar header uid spoofing; systemd restore.service
