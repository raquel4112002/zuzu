#!/usr/bin/env python3
"""Orchestrator report processor — updates state based on results.
Upgraded with new phases: vhost_enum, sensitive_files, cve_research, cred_reuse, web_app_admin.

Fix A (invariants): the orchestrator now refuses to advance into a phase
whose preconditions are not met (e.g. `postex` without a real shell, or
`report` without a flag). Weak models often *claim* progress they don't
have and then loop forever. The invariant guards reject the transition,
rewind sub_phase, and emit a clear correction so `think` puts the model
back on the right track instead of pretending state advanced.
"""
import json, sys, os, re

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'
result = sys.argv[2] if len(sys.argv) > 2 else ''

with open(state_file) as f:
    s = json.load(f)

# Ensure new state fields exist
if 'subdomains' not in s:
    s['subdomains'] = []
if 'rejected_transitions' not in s:
    s['rejected_transitions'] = []
if 'entities' not in s:
    # Fix #3 — structured slots so weak models don't have to re-parse prose.
    # `names`     : full-name strings extracted from any prose (team page,
    #               author bylines, etc.)
    # `usernames` : login-style identifiers derived from names + observed
    #               accounts. Lower-case, deduped.
    # `emails`    : email addresses seen anywhere
    # `tech`      : product+version pairs (e.g. "Flowise 3.0.5")
    # `cves`      : CVEs mentioned in any report
    # `endpoints` : web endpoints actually probed (incl. responses)
    s['entities'] = {
        'names': [],
        'usernames': [],
        'emails': [],
        'tech': [],
        'cves': [],
        'endpoints': [],
    }

target = s['target']
phase = s['phase']
sub = s['sub_phase']

# Log the action (raw, before any guards run)
s['phase_history'].append({"phase": phase, "sub": sub, "result": result[:500]})

# ═══════════════════════════════════════════════════════════════
# ENTITY EXTRACTION (Fix #3)
# Run on EVERY report so entities accumulate across phases. Weak models
# only see the prose they typed; this lets `think` reason over structured
# data they couldn't reliably re-parse.
# ═══════════════════════════════════════════════════════════════

def _add_unique(lst, items, lowercase=False):
    """Append items to lst preserving order, deduplicating case-insensitively.
    If lowercase=True, store the lowercased form."""
    seen = {x.lower() for x in lst}
    for it in items:
        if not it:
            continue
        norm = it.lower() if lowercase else it
        key = norm.lower()
        if key in seen:
            continue
        seen.add(key)
        lst.append(norm)


def _extract_entities(text):
    """Pull structured entities out of free-text. Conservative — we'd rather
    miss an entity than poison state with garbage."""
    if not text:
        return {}
    out = {'names': [], 'usernames': [], 'emails': [], 'tech': [], 'cves': [], 'endpoints': []}

    # CVEs — unambiguous pattern
    out['cves'] = re.findall(r'CVE-\d{4}-\d{4,7}', text)

    # Emails — standard pattern
    out['emails'] = re.findall(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', text)

    # Full names — "Firstname Lastname" or "Firstname Middle Lastname"
    # Constraints to avoid false positives:
    #   - Each token starts uppercase, rest lowercase (skips ALLCAPS noise)
    #   - 2-3 tokens
    #   - Not preceded by a code/path character (avoids matching things
    #     like 'Common Name' inside a URL)
    name_blacklist = {
        # Common false positives in our domain
        'Domain Admin', 'Active Directory', 'Domain Controller',
        'Common Name', 'User Found', 'User Not', 'Not Found',
        'Open Source', 'Build AI', 'Open Graph', 'Twitter Card',
        'Apache License', 'Web Server', 'Web Application',
        'Reverse Shell', 'Bind Shell', 'Web App',
        'Remote Code', 'Code Execution', 'File Upload',
        'Path Traversal', 'Stack Trace', 'Status Code',
        'Content Type', 'Host Header', 'User Agent',
        'Privilege Escalation', 'Lateral Movement',
    }
    # Title nouns: if a 'name' candidate's tokens are all in this set,
    # it's a job title, not a person.
    title_words = {
        'Director', 'Manager', 'Officer', 'President', 'Engineer',
        'Developer', 'Administrator', 'Operator', 'Analyst', 'Architect',
        'Lead', 'Head', 'Chief', 'Senior', 'Junior', 'Principal', 'Staff',
        'Vice', 'Executive', 'Associate', 'Consultant',
        'Financial', 'Technical', 'Risk', 'Compliance', 'Security',
        'Systems', 'Operations', 'Management', 'Marketing', 'Sales',
        'Managing', 'Acting', 'Interim', 'Founding',
        'Capital', 'Credit', 'Strategy',
    }
    # If the *first* token is a title noun, also reject (e.g. "Head Of", "Chief Risk").
    leading_title_tokens = {
        'Head', 'Chief', 'Senior', 'Junior', 'Vice', 'Acting', 'Interim',
        'Managing', 'Lead', 'Principal', 'Staff', 'Associate', 'Founding',
    }
    stop_tokens = {
        'The', 'And', 'Or', 'But', 'For', 'With', 'From',
        'This', 'That', 'Of', 'In', 'On', 'At', 'By', 'To',
        # Common sentence-start verbs / connectives that get capitalized
        'Found', 'Got', 'Had', 'Has', 'Have', 'Will', 'Would', 'Could',
        'Should', 'Can', 'May', 'Must', 'Need', 'Tried', 'Trying',
        'Got', 'Get', 'Try', 'Use', 'Using', 'Used', 'Run', 'Ran',
        'Check', 'Checking', 'Test', 'Testing', 'Verify',
        'See', 'Seen', 'Look', 'Looking', 'Note', 'Confirmed',
        'Detected', 'Discovered', 'Identified', 'Observed',
        # Common file/system words that look like names
        'File', 'Files', 'User', 'Users', 'Group', 'Groups',
        'Service', 'Services', 'Port', 'Ports', 'Host', 'Hosts',
    }
    for m in re.finditer(r'(?<![A-Za-z/_\-.])([A-Z][a-z]{1,15}(?:\s+[A-Z][a-z]{1,15}){1,2})(?![A-Za-z])', text):
        name = m.group(1).strip()
        if name in name_blacklist:
            continue
        toks = name.split()
        if any(t in stop_tokens for t in toks):
            continue
        # Reject if every token is a title word
        if all(t in title_words for t in toks):
            continue
        # Reject if first token is a leading-title indicator
        if toks[0] in leading_title_tokens:
            continue
        # Reject if last token is a title word AND the name has only 2 tokens
        # (catches "Marcus Manager", "John Director")
        if len(toks) == 2 and toks[-1] in title_words:
            continue
        out['names'].append(name)

    # Tech: "Product X.Y" or "Product X.Y.Z" — must have a version number
    for m in re.finditer(r'\b([A-Z][A-Za-z0-9_-]{2,30}(?:\s+[A-Za-z0-9_-]+){0,2})\s+(\d+\.\d+(?:[.\-][\w]+)*)\b', text):
        product, version = m.group(1).strip(), m.group(2).strip()
        # Filter out obvious non-tech (CVE-2024-xxxx etc. handled separately)
        if product.startswith('CVE'):
            continue
        out['tech'].append(f"{product} {version}")

    # Endpoints: paths like /api/v1/foo, /signin, /admin/dashboard
    out['endpoints'] = re.findall(r'(?<![A-Za-z0-9])(/[a-z0-9][\w/.-]{0,60})', text)
    # Trim obvious junk
    out['endpoints'] = [e for e in out['endpoints']
                        if not e.endswith(('.css', '.js', '.png', '.jpg', '.svg', '.ico'))
                        and len(e) >= 3]

    return out


def _refresh_usernames(state):
    """Derive plausible usernames from extracted names. Each name yields:
        firstname, lastname, firstinitial+lastname, firstname+lastinitial,
        firstname.lastname, flastname (HTB/AD common shapes).
    Plus any explicit usernames from earlier credentials.
    """
    out = []
    for name in state['entities'].get('names', []):
        toks = [t.lower() for t in name.split()]
        if len(toks) >= 2:
            first, last = toks[0], toks[-1]
            out.extend([first, last, first[0] + last, first + last[0],
                        f"{first}.{last}", f"{first}{last}"])
    # Pull usernames from credentials list too
    for c in state.get('credentials') or []:
        if isinstance(c, dict) and c.get('user') and c['user'] not in ('app_secret', 'unknown'):
            out.append(c['user'].lower())
    state['entities']['usernames'] = []
    _add_unique(state['entities']['usernames'], out, lowercase=True)


# Run extraction on the new report text and merge into state
_new_ents = _extract_entities(result)
_add_unique(s['entities']['names'], _new_ents.get('names', []))
_add_unique(s['entities']['emails'], _new_ents.get('emails', []), lowercase=True)
_add_unique(s['entities']['tech'], _new_ents.get('tech', []))
_add_unique(s['entities']['cves'], _new_ents.get('cves', []))
_add_unique(s['entities']['endpoints'], _new_ents.get('endpoints', []))
_refresh_usernames(s)

# ═══════════════════════════════════════════════════════════════
# INVARIANT HELPERS
# ═══════════════════════════════════════════════════════════════

def _has_real_shell(state):
    """True iff we have credible evidence of a shell on the target.
    Not just 'admin web access' or 'logged into a portal'."""
    shells = state.get('shells') or []
    if not shells:
        return False
    # Reject placeholder/web-only entries
    junk = ('admin access', 'admin panel', 'dashboard',
            'authenticated', 'web access', 'portal', 'logged in')
    for sh in shells:
        s_text = sh if isinstance(sh, str) else str(sh)
        s_low = s_text.lower()
        if any(j in s_low for j in junk) and not any(
            real in s_low for real in ('uid=', 'reverse shell', 'bind shell',
                                       'meterpreter', 'ssh shell', 'wmiexec',
                                       'evil-winrm', 'psexec', 'www-data',
                                       'bash$', 'sh$', '/bin/bash', '/bin/sh',
                                       'rce confirmed')):
            continue
        return True
    return False


def _has_any_flag(state):
    flags = state.get('flags') or {}
    return any(bool(v) for v in flags.values())


def _reject(reason, rewind_phase=None, rewind_sub=None):
    """Log a rejected transition, optionally rewind to a safer state,
    and print a clear correction. Caller should `return`/short-circuit
    after calling this so the normal transition logic doesn't run."""
    s['rejected_transitions'].append({
        "from_phase": phase,
        "from_sub": sub,
        "reason": reason[:300],
        "raw_result": result[:200],
    })
    if rewind_phase is not None:
        s['phase'] = rewind_phase
    if rewind_sub is not None:
        s['sub_phase'] = rewind_sub
    # Do NOT clear `attempt` — this is a correction, not a success.
    # Bump it so stuck-reasoning kicks in faster on repeat offenders.
    s['attempt'] = s.get('attempt', 0) + 1
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║  🛑 INVARIANT VIOLATION — transition rejected               ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()
    print(f"  Reason: {reason}")
    print()
    if rewind_phase is not None or rewind_sub is not None:
        print(f"  Rewound to: {s['phase']}/{s['sub_phase']}")
    print("  The orchestrator will not pretend you have access you don't have.")
    print("  Run: bash scripts/orchestrator.sh think    ← for the corrected next action")
    with open(state_file, 'w') as f:
        json.dump(s, f, indent=2)
    sys.exit(0)


# ═══════════════════════════════════════════════════════════════
# PRE-TRANSITION GUARDS — run BEFORE the phase logic below
# ═══════════════════════════════════════════════════════════════

# Guard 1: model is in postex but never actually got a shell.
# This was the #1 failure mode on 2million.htb (7 errors in a row).
if phase == 'postex' and not _has_real_shell(s):
    _reject(
        "You are in 'postex' but the orchestrator has no logged shell. "
        "Web/portal access is NOT a shell. Get RCE first, then report it "
        "with a verified shell indicator (uid=, www-data, reverse shell, etc.).",
        rewind_phase='exploit',
        rewind_sub='execute',
    )

# Guard 2: model is trying to write the report but no flag was captured.
# Allow it only if user explicitly says 'skip' or 'abandon' so an aborted
# engagement can still produce a partial report.
if phase == 'report' and not _has_any_flag(s):
    rl = result.lower()
    if not any(tok in rl for tok in ('skip', 'abandon', 'partial', 'no flag', 'failed engagement')):
        _reject(
            "You are in 'report' phase but no flags were captured. "
            "Either (a) keep working — go back to postex/privesc, or "
            "(b) explicitly mark this as a partial/abandoned engagement "
            "by including 'partial' or 'abandon' in your report message.",
            rewind_phase='postex',
            rewind_sub='privesc_enum' if _has_real_shell(s) else 'cred_reuse',
        )

# Guard 4 (Fix #4 — stuck-blocking): when the orchestrator is stuck (attempt
# >= 2 OR last 3 phase_history entries are same sub OR last 2 errors same sub
# OR any rejected_transitions), the NEXT `report` must include a worksheet.
# A worksheet is identified by either an explicit "WORKSHEET:" marker OR by
# at least 3 of the H1:/H2:/H3: hypothesis lines that orch-think prints.
# This forces weak models to actually pause and reason instead of blindly
# rerunning the same failed approach.
#
# Bypass: include the literal string "BYPASS_STUCK_GATE" in the report when
# you genuinely have new evidence and want to advance. Auditable in state.
def _is_stuck(state):
    """Mirror of orch-think.py is_stuck logic, kept in sync deliberately."""
    history = state.get('phase_history', []) or []
    errs = state.get('errors', []) or []
    rej = state.get('rejected_transitions', []) or []
    p, sb = state['phase'], state['sub_phase']
    same_3 = (len(history) >= 3 and
              all(h.get('phase') == p and h.get('sub') == sb for h in history[-3:]))
    same_2_err = (len(errs) >= 2 and
                  all(e.get('phase') == p and e.get('sub') == sb for e in errs[-2:]))
    return state.get('attempt', 0) >= 2 or same_3 or same_2_err or len(rej) >= 1


def _has_worksheet(text):
    """Does the report text contain a stuck-reasoning worksheet?
    Accept either an explicit marker or 3 hypothesis lines."""
    if not text:
        return False
    t = text.lower()
    if 'worksheet:' in t or 'bypass_stuck_gate' in t:
        return True
    # H1: ... H2: ... H3: ... — at least 3 hypothesis lines
    h_count = sum(1 for tag in ('h1:', 'h2:', 'h3:') if tag in t)
    return h_count >= 3


if _is_stuck(s) and not _has_worksheet(result):
    # Don't rewind state — just block. The model needs to redo the report
    # with a real worksheet. We log the rejection so audit shows it happened.
    s['rejected_transitions'].append({
        "from_phase": phase,
        "from_sub": sub,
        "reason": "Stuck-gate: report submitted without worksheet while loop was detected.",
        "raw_result": result[:200],
    })
    with open(state_file, 'w') as f:
        json.dump(s, f, indent=2)
    print("╔════════════════════════════════════════════════════════════╗")
    print("║  🚧 STUCK GATE — report blocked. Worksheet required.            ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print()
    print(f"  The orchestrator detected a loop ({phase}/{sub}, attempt={s.get('attempt',0)}).")
    print("  Your report did NOT contain a worksheet, so it was REJECTED.")
    print()
    print("  Required: include AT LEAST 3 hypothesis lines in your report:")
    print("     H1: <one-line hypothesis> -> test: <command or check>")
    print("     H2: <one-line hypothesis> -> test: <command or check>")
    print("     H3: <one-line hypothesis> -> test: <command or check>")
    print()
    print("  Then pick ONE hypothesis, run its test, and report the OUTCOME of")
    print("  that test (not the next attack idea). Dead hypotheses are progress.")
    print()
    print("  Run: bash scripts/orchestrator.sh think    ← to see the full worksheet")
    print()
    print("  Bypass (use only with NEW evidence): include 'BYPASS_STUCK_GATE'")
    print("  in your next report. It will be logged in state for audit.")
    sys.exit(0)


# Guard 3: model claims a flag without an MD5-shaped string anywhere.
# Not a hard reject — just refuse to record fake flags. Real HTB flags
# are 32 hex chars; we let the per-phase logic capture them, but if a
# model is yelling 'GOT FLAG' without one we strip the false positive.
if (phase == 'postex' and sub in ('user_flag', 'root_flag')
        and re.search(r'\b(got|found|captured|flag)\b', result.lower())
        and not re.search(r'[a-f0-9]{32}', result)):
    print("⚠️  Claim of flag without 32-hex-char hash. Not recording flag.")
    print("    If you really have it, paste the raw hash in the report string.")
    # Don't reject the transition — fall through, but per-phase logic
    # will see no hash and not record a flag.


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
    rl = result.lower()

    # Distinguish *real* shell evidence from *web/portal* access.
    # Real shell needs explicit shell-indicator OR an OS uid signature.
    real_shell_markers = (
        'uid=', 'gid=', 'reverse shell', 'bind shell', 'meterpreter',
        'evil-winrm', 'wmiexec', 'psexec', 'www-data', 'rce confirmed',
        '/bin/bash', '/bin/sh', 'nt authority', 'system32',
        'got shell', 'shell on target', 'rev shell', 'callback received',
    )
    web_admin_markers = (
        'admin panel', 'admin dashboard', 'admin access', 'dashboard',
        'node secret', 'api access', 'api token', 'authenticated session',
        'logged in', 'admin login successful', 'cms admin',
    )

    has_real_shell = any(m in rl for m in real_shell_markers)
    has_web_admin = any(m in rl for m in web_admin_markers)

    if has_real_shell:
        s['shells'].append(result[:200])
        s['sub_phase'] = 'stabilize'
        print("✅ Shell obtained (verified marker)! Moving to stabilization")
    elif has_web_admin:
        # Web admin access is progress, but it is NOT a system shell.
        # Stay in exploit phase, escalate via web_app_admin sub-phase.
        s['findings'].append(f"Web admin access (no shell yet): {result[:200]}")
        s['sub_phase'] = 'web_app_admin'
        print("✅ Web admin access obtained — still need RCE for a real shell.")
    else:
        s['findings'].append(f"Exploit result: {result[:200]}")
        print("⚠️  No shell yet. Try a different vector or report error.")

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
    
    # If we got a shell from web app admin, go to stabilize.
    # Otherwise STAY in web_app_admin — do not pretend we have shell.
    rl_admin = result.lower()
    real_shell_markers_admin = (
        'uid=', 'gid=', 'reverse shell', 'bind shell', 'meterpreter',
        'www-data', 'rce confirmed', '/bin/bash', '/bin/sh',
        'callback received', 'got shell',
    )
    if any(m in rl_admin for m in real_shell_markers_admin):
        s['shells'].append(result[:200])
        s['sub_phase'] = 'stabilize'
        print("✅ Shell from web app admin! Moving to stabilization")
    else:
        # Stay here — keep hunting for RCE inside the admin surface.
        # `think` will surface concrete RCE-via-admin avenues.
        print("ℹ️  Web admin processed but no shell yet — keep escalating in web_app_admin.")

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
