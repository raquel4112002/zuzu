#!/usr/bin/env python3
"""Orchestrator report processor — updates state based on results."""
import json, sys, os, re

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'
result = sys.argv[2] if len(sys.argv) > 2 else ''

with open(state_file) as f:
    s = json.load(f)

target = s['target']
phase = s['phase']
sub = s['sub_phase']

# Log the action
s['phase_history'].append({"phase": phase, "sub": sub, "result": result[:500]})

# ─── SMART PHASE TRANSITIONS ─────────────────

if phase == 'recon' and sub == 'portscan':
    # Parse ports from result
    ports_found = re.findall(r'port\s*(\d+)\s+open\s+(\S+)\s*(.*?)(?:,|$)', result.lower())
    for port, svc, ver in ports_found:
        s['ports']['tcp'].append(int(port))
        s['services'][port] = {"service": svc, "version": ver.strip()}
    
    s['findings'].append(f"Open TCP ports: {', '.join(str(p) for p in s['ports']['tcp'])}")
    
    # Check for hostname redirect
    if 'redirect' in result.lower() or '.htb' in result.lower() or 'hostname' in result.lower():
        hostnames = re.findall(r'(?:http[s]?://)?([a-zA-Z0-9.-]+\.(?:htb|local|internal|corp))', result)
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
    
    s['sub_phase'] = 'service_enum'
    print("✅ UDP scan processed")

elif phase == 'recon' and sub == 'hostname_check':
    s['sub_phase'] = 'service_enum'
    print("✅ Hostname configured")

elif phase == 'recon' and sub == 'service_enum':
    s['findings'].append(f"Enumeration: {result[:200]}")
    
    has_web = any(p in s['ports']['tcp'] for p in [80, 443, 8080, 8443])
    if has_web:
        s['phase'] = 'web_enum'
        s['sub_phase'] = 'tech_detect'
    else:
        s['phase'] = 'web_enum'
        s['sub_phase'] = 'vuln_scan'
    print("✅ Enumeration processed, moving to web enum")

elif phase == 'web_enum' and sub == 'tech_detect':
    s['findings'].append(f"Web tech: {result[:200]}")
    
    if 'api' in result.lower():
        s['web_paths'].append('/api')
    if 'login' in result.lower():
        s['web_paths'].append('/login')
    if 'admin' in result.lower():
        s['web_paths'].append('/admin')
    if 'invite' in result.lower():
        s['web_paths'].append('/invite')
    
    s['sub_phase'] = 'dir_bruteforce'
    print("✅ Tech detection done")

elif phase == 'web_enum' and sub == 'dir_bruteforce':
    paths = re.findall(r'(/[a-zA-Z0-9_./-]+)', result)
    s['web_paths'].extend(paths)
    s['web_paths'] = list(set(s['web_paths']))
    s['findings'].append(f"Web paths: {', '.join(paths[:10])}")
    
    if any('api' in p.lower() for p in s['web_paths']):
        s['sub_phase'] = 'api_enum'
    else:
        s['sub_phase'] = 'vuln_scan'
    print("✅ Directory scan processed")

elif phase == 'web_enum' and sub == 'api_enum':
    s['findings'].append(f"API: {result[:300]}")
    s['sub_phase'] = 'vuln_scan'
    print("✅ API enumeration processed")

elif phase == 'web_enum' and sub == 'vuln_scan':
    s['findings'].append(f"Vulns: {result[:300]}")
    s['phase'] = 'exploit'
    s['sub_phase'] = 'plan'
    print("✅ Vuln scan done, moving to exploitation")

elif phase == 'exploit' and sub == 'plan':
    s['attack_plan'] = result
    s['sub_phase'] = 'execute'
    print(f"✅ Attack plan set: {result[:100]}")

elif phase == 'exploit' and sub == 'execute':
    if any(kw in result.lower() for kw in ['shell', 'rce', 'access', 'reverse', 'connect']):
        s['shells'].append(result[:200])
        s['sub_phase'] = 'stabilize'
        print("✅ Shell obtained! Moving to stabilization")
    else:
        s['findings'].append(f"Exploit result: {result[:200]}")
        print("⚠️  No shell yet. Try again or report error")

elif phase == 'exploit' and sub == 'stabilize':
    s['findings'].append(f"System info: {result[:300]}")
    
    # Check for creds in result
    env_user = re.findall(r'DB_(?:USER(?:NAME)?)\s*=\s*(\S+)', result)
    env_pass = re.findall(r'DB_(?:PASS(?:WORD)?)\s*=\s*(\S+)', result)
    
    if env_user and env_pass:
        s['credentials'].append({"user": env_user[0], "pass": env_pass[0], "source": ".env"})
    
    # Generic password patterns
    other_creds = re.findall(r'(?:password|passwd|pass)[=:]\s*(\S+)', result, re.IGNORECASE)
    for p in other_creds:
        if p not in [c.get('pass','') for c in s['credentials'] if isinstance(c, dict)]:
            s['credentials'].append({"user": "unknown", "pass": p, "source": "discovered"})
    
    s['phase'] = 'postex'
    s['sub_phase'] = 'user_flag'
    print("✅ Shell stabilized, moving to post-exploitation")

elif phase == 'postex' and sub == 'user_flag':
    flags = re.findall(r'[a-f0-9]{32}', result)
    if flags:
        s['flags']['user'] = flags[0]
        print(f"✅ USER FLAG: {flags[0]}")
    else:
        print("⚠️  No flag found in result, continuing anyway")
    
    s['sub_phase'] = 'privesc_enum'

elif phase == 'postex' and sub == 'privesc_enum':
    s['findings'].append(f"Privesc enum: {result[:300]}")
    
    # Detect common vectors
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
    if any(h in result for h in ['$y$', '$6$', '$2y$', '$1$', '$5$']):
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
