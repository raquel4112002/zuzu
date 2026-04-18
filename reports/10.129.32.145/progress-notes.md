# Snapped (10.129.32.145) — Active HTB Box — Progress Notes

## Status: User Pwned, Root In Progress

### Attack Chain So Far
1. Nmap → ports 22, 80 → snapped.htb, admin.snapped.htb (nginx-ui v2.3.2)
2. CVE-2026-27944 → unauthenticated backup download + AES key in headers → decrypt
3. Extracted: JWT/Node/Crypto secrets, SQLite DB with bcrypt hashes
4. john → jonathan:linkinpark
5. SSH → user flag: f985160e9182da863ee8c9cd7fc94798
6. CVE-2026-33026 → backup restore tamper → injected StartCmd=bash → www-data terminal
7. CVE-2026-33032 → MCP session via SSE + Node Secret auth → can list/read configs

### Root Privesc — What I've Tried
- [ ] Kernel exploit (6.17.0 — very new, no known exploit)
- [ ] SUID binaries — nothing unusual
- [ ] sudo — jonathan has no sudo
- [ ] Capabilities — nothing useful
- [ ] Writable systemd — symlinks to /dev/null (red herring)
- [ ] MCP config write — permission denied (www-data can't write /etc/nginx/)
- [ ] Backup restore nginx configs — permission denied (www-data can't clean /etc/nginx/conf.d)
- [ ] RestartCmd injection — runs as www-data, not root
- [ ] nginx-ui logrotate — disabled, and runs as www-data anyway

### Root Privesc — Untried Paths
- [ ] The nginx-ui binary itself (owned by UID 1001) — can we replace it?
- [ ] The database.db — can we inject something that gets executed?
- [ ] Craft malicious .so and use load_module — but need write to /etc/nginx/ or a module dir
- [ ] Check for cron jobs that process www-data files
- [ ] Internal services on localhost
- [ ] Mail for root
- [ ] Look for a kernel exploit specific to 6.17.x
- [ ] Check if there's a custom systemd timer that runs as root and processes nginx configs
- [ ] linpeas/pspy for hidden processes
