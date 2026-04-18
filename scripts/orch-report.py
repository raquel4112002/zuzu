#!/usr/bin/env python3
"""Orchestrator report processor — updates state based on results.
Upgraded with new phases: vhost_enum, sensitive_files, cve_research, cred_reuse, web_app_admin."""
import json, sys, os, re

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'
result = sys.argv[2] if len(sys.argv) > 2 else ''

with open(state_file) as f:
    s = json.load(f)

# Ensure new state fields exist
if 'subdomains' not in s:
    s['subdomains'] = []

target = s['target']
phase = s['phase']
sub = s['sub_phase']

# Log the action
s['phase_history'].append({"phase": phase, "sub": sub, "result": result[:500]})

# ═══════════════════════════════════════════════════════════════
# RECON PHASE TRANSITIONS
# ═══════════════════════════════════════════════════════════════

if phase == 'recon' and sub == 'portscan':
    ports_found = re.findall(r'port\s*(\d+)\s+open\s+(\S+)\s*(.*?)(?:,|$)', result.lower())
    for port, svc, ver in ports_found:
        s['ports']['tcp'].append(int(port))
        s['services'][port] = {"service": svc, "version": ver.strip()}
    
    s['findings'].append(f"Open TCP ports: {', '.join(str(p) for p in s['ports']['tcp'])}")
    
    # Check for hostname redirect
    if 'redirect' in result.lower() or '.htb' in result.lower() or 'hostname' in result.lower():
        hostnames = re.findall(r'(?:http[s]?://)?([a-zA-Z0-9.-]+\.(?:htb|local|internal|corp|box))', result)
        if hostnames:
            s['hostnames'] = list(set(hostnames))
            s['sub_phase'] = 'hostname_check'
            s['findings'].append(f"Hostnames found: {', '.join(hostnames)}")
        else:
            s['sub_phase'] = 'udp_scan'
    else:
        s['sub_phase'] = 'udp_scan'
    
    print(f"✅ Logged {len(ports_found)} open ports")

elif phase == 'recon' and sub == 'udp_scan':
    udp_ports = re.findall(r'port\s*(\d+)\s+open\s+(\S+)', result.lower())
    for port, svc in udp_ports:
        s['ports']['udp'].append(int(port))
        s['services'][port] = {"service": svc, "version": ""}
    
    # NEW: If web ports found, go to vhost enumeration
    has_web = any(p in s['ports']['tcp'] for p in [80, 443, 8080, 8443])
    if has_web and s.get('hostnames'):
        s['sub_phase'] = 'vhost_enum'
    else:
        s['sub_phase'] = 'service_enum'
    print("✅ UDP scan processed")

elif phase == 'recon' and sub == 'hostname_check':
    # NEW: After hostname setup, go to vhost enumeration
    has_web = any(p in s['ports']['tcp'] for p in [80, 443, 8080, 8443])
    if has_web:
        s['sub_phase'] = 'vhost_enum'
    else:
        s['sub_phase'] = 'service_enum'
    print("✅ Hostname configured")

# ─── NEW: VHOST ENUMERATION ──────────────────
elif phase == 'recon' and sub == 'vhost_enum':
    # Parse subdomain results
    subs_found = re.findall(r'(?:found\s+)?([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.(?:htb|local|internal|corp|box))', result.lower())
    if subs_found:
        s['subdomains'] = list(set(s.get('subdomains', []) + subs_found))
        s['findings'].append(f"Subdomains found: {', '.join(subs_found)}")
        # Add to hostnames for later use
        s['hostnames'] = list(set(s.get('hostnames', []) + subs_found))
    
    if 'no subdomain' in result.lower() or not subs_found:
        s['findings'].append("No additional subdomains found")
    
    s['sub_phase'] = 'service_enum'
    print(f"✅ Vhost enumeration done. Found {len(subs_found)} subdomains")

elif phase == 'recon' and sub == 'service_enum':
    s['findings'].append(f"Enumeration: {result[:200]}")
    
    has_web = any(p in s['ports']['tcp'] for p in [80, 443, 8080, 8443])
    if has_web:
        s['phase'] = 'web_enum'
        s['sub_phase'] = 'tech_detect'
    else:
        s['phase'] = 'exploit'
        s['sub_phase'] = 'plan'
    print("✅ Enumeration processed")

# ═══════════════════════════════════════════════════════════════
# WEB ENUM PHASE TRANSITIONS
# ═══════════════════════════════════════════════════════════════

elif phase == 'web_enum' and sub == 'tech_detect':
    s['findings'].append(f"Web tech: {result[:200]}")
    
    for kw, path in [('api', '/api'), ('login', '/login'), ('admin', '/admin'), ('invite', '/invite')]:
        if kw in result.lower():
            s['web_paths'].append(path)
    
    # Detect specific web apps for CVE research
    app_keywords = ['nginx-ui', 'nginx ui', 'wordpress', 'jenkins', 'drupal', 'joomla',
                    'grafana', 'gitlab', 'kibana', 'phpmyadmin', 'webmin', 'tomcat']
    for kw in app_keywords:
        if kw in result.lower():
            s['findings'].append(f"Web app detected: {kw}")
    
    s['sub_phase'] = 'dir_bruteforce'
    print("✅ Tech detection done")

elif phase == 'web_enum' and sub == 'dir_bruteforce':
    paths = re.findall(r'(/[a-zA-Z0-9_./-]+)', result)
    s['web_paths'].extend(paths)
    s['web_paths'] = list(set(s['web_paths']))
    s['findings'].append(f"Web paths: {', '.join(paths[:10])}")
    
    # NEW: Go to sensitive files check before API enum
    s['sub_phase'] = 'sensitive_files'
    print("✅ Directory scan processed")

# ─── NEW: SENSITIVE FILES ─────────────────────
elif phase == 'web_enum' and sub == 'sensitive_files':
    s['findings'].append(f"Sensitive files: {result[:300]}")
    
    # Check if backup or important files found
    if any(kw in result.lower() for kw in ['backup', '200', '.env', 'api/backup', 'config']):
        s['findings'].append("⚠️ Sensitive files/endpoints found — investigate!")
    
    if any('api' in p.lower() for p in s['web_paths']):
        s['sub_phase'] = 'api_enum'
    else:
        s['sub_phase'] = 'cve_research'
    print("✅ Sensitive files check done")

elif phase == 'web_enum' and sub == 'api_enum':
    s['findings'].append(f"API: {result[:300]}")
    # NEW: Go to CVE research after API enum
    s['sub_phase'] = 'cve_research'
    print("✅ API enumeration processed")

# ─── NEW: CVE RESEARCH ────────────────────────
elif phase == 'web_enum' and sub == 'cve_research':
    s['findings'].append(f"CVE research: {result[:300]}")
    
    # Check if exploitable CVEs found
    cves = re.findall(r'CVE-\d{4}-\d{4,}', result)
    if cves:
        s['findings'].append(f"CVEs found: {', '.join(cves)}")
    
    s['sub_phase'] = 'vuln_scan'
    print(f"✅ CVE research done. Found {len(cves)} CVEs")

elif phase == 'web_enum' and sub == 'vuln_scan':
    s['findings'].append(f"Vulns: {result[:300]}")
    s['phase'] = 'exploit'
    s['sub_phase'] = 'plan'
    print("✅ Vuln scan done, moving to exploitation")

# ═══════════════════════════════════════════════════════════════
# EXPLOIT PHASE TRANSITIONS
# ═══════════════════════════════════════════════════════════════

elif phase == 'exploit' and sub == 'plan':
    s['attack_plan'] = result
    s['sub_phase'] = 'execute'
    print(f"✅ Attack plan set: {result[:100]}")

elif phase == 'exploit' and sub == 'execute':
    if any(kw in result.lower() for kw in ['shell', 'rce', 'access', 'reverse', 'connect', 'admin access', 'authenticated']):
        s['shells'].append(result[:200])
        # NEW: Check if we got admin web access (not a system shell)
        if any(kw in result.lower() for kw in ['admin access', 'admin panel', 'dashboard', 'authenticated', 'node secret', 'api access']):
            s['sub_phase'] = 'web_app_admin'
            print("✅ Admin web access obtained! Moving to web app exploitation")
        else:
            s['sub_phase'] = 'stabilize'
            print("✅ Shell obtained! Moving to stabilization")
    else:
        s['findings'].append(f"Exploit result: {result[:200]}")
        print("⚠️  No shell yet. Try again or report error")

# ─── NEW: WEB APP ADMIN EXPLOITATION ─────────
elif phase == 'exploit' and sub == 'web_app_admin':
    s['findings'].append(f"Web app admin: {result[:300]}")
    
    # Check for extracted secrets/creds
    secrets = re.findall(r'(?:secret|token|key|password)[=:]\s*(\S+)', result, re.IGNORECASE)
    for sec in secrets:
        s['credentials'].append({"user": "app_secret", "pass": sec, "source": "web_app"})
    
    # Check for hashes
    hashes = re.findall(r'\$2[ayb]\$\d+\$[./A-Za-z0-9]+', result)
    if hashes:
        s['findings'].append(f"Bcrypt hashes found: {len(hashes)}")
    
    # If we got a shell from web app admin, go to stabilize
    if any(kw in result.lower() for kw in ['shell', 'terminal', 'bash', 'www-data', 'reverse']):
        s['sub_phase'] = 'stabilize'
        print("✅ Shell from web app admin! Moving to stabilization")
    else:
        # Move to stabilize to gather system info
        s['sub_phase'] = 'stabilize'
        print("✅ Web app admin exploitation processed")

elif phase == 'exploit' and sub == 'stabilize':
    s['findings'].append(f"System info: {result[:300]}")
    
    env_user = re.findall(r'DB_(?:USER(?:NAME)?)\s*=\s*(\S+)', result)
    env_pass = re.findall(r'DB_(?:PASS(?:WORD)?)\s*=\s*(\S+)', result)
    
    if env_user and env_pass:
        s['credentials'].append({"user": env_user[0], "pass": env_pass[0], "source": ".env"})
    
    other_creds = re.findall(r'(?:password|passwd|pass)[=:]\s*(\S+)', result, re.IGNORECASE)
    for p in other_creds:
        if p not in [c.get('pass','') for c in s['credentials'] if isinstance(c, dict)]:
            s['credentials'].append({"user": "unknown", "pass": p, "source": "discovered"})
    
    s['phase'] = 'postex'
    # NEW: If we have creds, check credential reuse first
    if s['credentials']:
        s['sub_phase'] = 'cred_reuse'
    else:
        s['sub_phase'] = 'user_flag'
    print("✅ Shell stabilized, moving to post-exploitation")

# ═══════════════════════════════════════════════════════════════
# POSTEX PHASE TRANSITIONS
# ═══════════════════════════════════════════════════════════════

# ─── NEW: CREDENTIAL REUSE CHECK ─────────────
elif phase == 'postex' and sub == 'cred_reuse':
    s['findings'].append(f"Cred reuse: {result[:200]}")
    
    # Check if new creds/access found
    if any(kw in result.lower() for kw in ['success', 'logged in', 'shell', 'ssh', 'authenticated']):
        s['findings'].append("Credential reuse successful!")
    
    # Parse any cracked hashes
    cracked = re.findall(r'(\S+)\s*:\s*(\S+)\s*\(', result)
    for user, pwd in cracked:
        s['credentials'].append({"user": user, "pass": pwd, "source": "cracked"})
    
    s['sub_phase'] = 'user_flag'
    print("✅ Credential reuse check done")

elif phase == 'postex' and sub == 'user_flag':
    flags = re.findall(r'[a-f0-9]{32}', result)
    if flags:
        s['flags']['user'] = flags[0]
        print(f"✅ USER FLAG: {flags[0]}")
    else:
        print("⚠️  No flag found, continuing")
    
    s['sub_phase'] = 'privesc_enum'

elif phase == 'postex' and sub == 'privesc_enum':
    s['findings'].append(f"Privesc enum: {result[:300]}")
    
    rl = result.lower()
    if 'kernel' in rl or 'cve' in rl or 'overlay' in rl or 'fuse' in rl:
        s['privesc_vector'] = 'kernel exploit'
    elif 'sudo' in rl and ('root' in rl or 'NOPASSWD' in result):
        s['privesc_vector'] = 'sudo misconfiguration'
    elif '-rwsr' in result or 'suid' in rl:
        s['privesc_vector'] = 'SUID binary'
    elif 'docker' in rl:
        s['privesc_vector'] = 'docker group'
    elif 'cron' in rl and 'writable' in rl:
        s['privesc_vector'] = 'writable cron'
    elif 'mail' in rl and ('hint' in rl or 'patch' in rl or 'update' in rl or 'cve' in rl):
        s['privesc_vector'] = 'mail hint — check for CVE/exploit mentioned'
    elif 'writable' in rl and ('systemd' in rl or 'service' in rl):
        s['privesc_vector'] = 'writable systemd service'
    else:
        s['privesc_vector'] = 'manual analysis needed — check findings'
    
    s['sub_phase'] = 'privesc_exploit'
    print(f"✅ Privesc vector: {s['privesc_vector']}")

elif phase == 'postex' and sub == 'privesc_exploit':
    if 'root' in result.lower() or 'uid=0' in result:
        s['shells'].append('root shell')
        s['sub_phase'] = 'root_flag'
        print("✅ GOT ROOT! Getting flag...")
    else:
        print("⚠️  Not root yet. Try another vector or report error")

elif phase == 'postex' and sub == 'root_flag':
    flags = re.findall(r'[a-f0-9]{32}', result)
    if flags:
        s['flags']['root'] = flags[0]
        print(f"✅ ROOT FLAG: {flags[0]}")
    
    s['sub_phase'] = 'loot'

elif phase == 'postex' and sub == 'loot':
    s['findings'].append(f"Loot: {result[:300]}")
    if any(h in result for h in ['$y$', '$6$', '$2y$', '$1$', '$5$', '$2a$']):
        s['findings'].append("Password hashes collected")
    
    s['phase'] = 'report'
    s['sub_phase'] = 'write'
    print("✅ Loot collected, moving to reporting")

elif phase == 'report':
    s['phase'] = 'complete'
    s['sub_phase'] = 'done'
    print("✅ ENGAGEMENT COMPLETE!")

else:
    print(f"⚠️  Unknown phase transition: {phase}/{sub}")

# Reset attempt counter on success
s['attempt'] = 0

# Save
with open(state_file, 'w') as f:
    json.dump(s, f, indent=2)

print()
print("Run: bash scripts/orchestrator.sh think    ← for next action")
