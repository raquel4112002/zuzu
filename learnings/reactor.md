# Reactor (HTB, easy, Linux) — Quick Reference

**Flags:** user+root captured (values kept out of git) | 33m wall

## Chain
1. Only 22 + 3000 (Next.js 15.0.3, single static page — Recon is a trap; dirbust yields nothing)
2. CVE-2025-55182 "React2Shell" (RSC/Server-Action proto pollution, unauth RCE as `node` uid 999)
3. `/opt/reactor-app/reactor.db` SQLite `users` table → raw MD5 → `engineer:reactor1` → SSH
4. Root: `127.0.0.1:9229` Node inspector on root-owned `/opt/uptime-monitor/worker.js`
   → `node inspect` REPL → `exec("process.mainModule.require('child_process').execSync(...)")`

## Reusable lessons
- React2Shell 500+numeric digest = pollution landed but digest needs the
  `NEXT_REDIRECT;push;/login?a=${res};307;` wrapper to ride the 303 (scanner.py:177).
- node inspect REPL over piped stdin: output lags one command; use file capture
  (`> /tmp/o; chmod 644`) + read as low-priv user, not stdout parsing.
- Easy-box fingerprint → CVE-first: 15 min of recon + version pin = the whole chain.
- "Rate-limited" assumptions need an empirical probe before handoff (old session
  burned 20 min on an untested rate limit; there was none).
