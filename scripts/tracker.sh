#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# ZUZU ATTACK TRACKER — Never Lose Your Place
# ═══════════════════════════════════════════════════════════════
# Tracks attack progress so the model ALWAYS knows where it is.
# 
# Usage:
#   bash scripts/tracker.sh status                    # Where am I?
#   bash scripts/tracker.sh start <target> [type]     # Start new engagement
#   bash scripts/tracker.sh next                      # What's my next step?
#   bash scripts/tracker.sh done <step>               # Mark step as done
#   bash scripts/tracker.sh found <finding>           # Log a finding
#   bash scripts/tracker.sh creds <user> <pass>       # Log credentials found
#   bash scripts/tracker.sh shell <type> <target>     # Log shell obtained
#   bash scripts/tracker.sh reset                     # Reset tracker
# ═══════════════════════════════════════════════════════════════

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$WORKSPACE/state/attack-state.json"
FINDINGS_FILE="$WORKSPACE/state/findings.log"

mkdir -p "$WORKSPACE/state"

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  echo '{"target":"","type":"","phase":"idle","steps_done":[],"current_step":"","creds":[],"shells":[],"findings":[]}' > "$STATE_FILE"
fi

ACTION="${1}"

case "$ACTION" in

  # ─── STATUS ─────────────────────────────────────────────
  status)
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  📊 ATTACK TRACKER STATUS                           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    
    python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f: s = json.load(f)
except: print('  Error reading state file'); sys.exit(1)

if s.get('phase') == 'idle' or not s.get('target'):
    print()
    print('  Status: IDLE — No active engagement')
    print('  Start one with: bash scripts/tracker.sh start <target> [type]')
    print()
    sys.exit(0)

print()
print(f'  Target:       {s[\"target\"]}')
print(f'  Type:         {s[\"type\"]}')
print(f'  Phase:        {s[\"phase\"]}')
print(f'  Current Step: {s[\"current_step\"]}')
print()
print('  ── Steps Completed ──')
for step in s.get('steps_done', []):
    print(f'  ✅ {step}')
print()
print('  ── Credentials Found ──')
for cred in s.get('creds', []):
    print(f'  🔑 {cred}')
print()
print('  ── Shells Obtained ──')
for shell in s.get('shells', []):
    print(f'  💀 {shell}')
print()
print('  ── Findings ──')
for f in s.get('findings', []):
    print(f'  📝 {f}')
print()
print('  Run: bash scripts/tracker.sh next    ← for next step')
"
    ;;

  # ─── START ──────────────────────────────────────────────
  start)
    TARGET="${2}"
    TYPE="${3:-auto}"
    
    if [ -z "$TARGET" ]; then
      echo "Usage: bash scripts/tracker.sh start <target> [web|network|ad|api|cloud|auto]"
      exit 1
    fi
    
    # Create report directory
    REPORT_DIR="$WORKSPACE/reports/${TARGET//\//-}"
    mkdir -p "$REPORT_DIR"
    
    cat > "$STATE_FILE" << EOF
{"target":"$TARGET","type":"$TYPE","phase":"recon","steps_done":[],"current_step":"recon-1-portscan","creds":[],"shells":[],"findings":[],"report_dir":"$REPORT_DIR"}
EOF
    
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  🎯 ENGAGEMENT STARTED                              ║"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║  Target: $TARGET"
    echo "║  Type:   $TYPE"
    echo "║  Report: $REPORT_DIR"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║  Run: bash scripts/tracker.sh next                  ║"
    echo "║  to see your first step.                            ║"
    echo "╚══════════════════════════════════════════════════════╝"
    ;;

  # ─── NEXT STEP ──────────────────────────────────────────
  next)
    eval $(python3 -c "
import json
with open('$STATE_FILE') as f: s = json.load(f)
print(f'TARGET=\"{s[\"target\"]}\"')
print(f'TYPE=\"{s[\"type\"]}\"')
print(f'PHASE=\"{s[\"phase\"]}\"')
print(f'CURRENT=\"{s[\"current_step\"]}\"')
" 2>/dev/null)
    
    if [ "$PHASE" = "idle" ] || [ -z "$TARGET" ]; then
      echo "No active engagement. Run: bash scripts/tracker.sh start <target>"
      exit 1
    fi
    
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  👉 NEXT STEP                                       ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    
    case "$CURRENT" in
      recon-1-portscan)
        echo "  STEP: Port Scan"
        echo "  ─────────────────────────────────────────────"
        echo "  Run this command:"
        echo ""
        echo "    bash scripts/attack.sh $TARGET"
        echo ""
        echo "  Then mark done:"
        echo "    bash scripts/tracker.sh done recon-1-portscan"
        echo ""
        echo "  After this, log what you found:"
        echo "    bash scripts/tracker.sh found 'port 80 open - Apache 2.4.51'"
        echo "    bash scripts/tracker.sh found 'port 445 open - SMB'"
        echo "    bash scripts/tracker.sh found 'port 22 open - SSH'"
        ;;
      recon-2-enumerate)
        echo "  STEP: Service Enumeration"
        echo "  ─────────────────────────────────────────────"
        echo "  For EACH open port, run the matching commands."
        echo "  Read: knowledge-base/checklists/enumeration-checklist.md"
        echo ""
        echo "  Common:"
        echo "    Web (80/443):  whatweb http://$TARGET && nikto -h http://$TARGET"
        echo "    SMB (445):     enum4linux -a $TARGET"
        echo "    SSH (22):      ssh -v $TARGET (check banner/version)"
        echo "    FTP (21):      ftp $TARGET (try anonymous)"
        echo ""
        echo "  Then: bash scripts/tracker.sh done recon-2-enumerate"
        ;;
      vuln-1-scan)
        echo "  STEP: Vulnerability Scanning"
        echo "  ─────────────────────────────────────────────"
        echo "  Run automated vuln scanners:"
        echo ""
        echo "    nuclei -u http://$TARGET -severity critical,high"
        echo "    nikto -h http://$TARGET"
        echo ""
        echo "  For each service version found, research exploits:"
        echo "    bash scripts/research.sh <service> <version>"
        echo ""
        echo "  Then: bash scripts/tracker.sh done vuln-1-scan"
        ;;
      vuln-2-manual)
        echo "  STEP: Manual Vulnerability Testing"
        echo "  ─────────────────────────────────────────────"
        echo "  Read: knowledge-base/mitre-attack/techniques/web-exploitation.md"
        echo ""
        echo "  Test for:"
        echo "    SQLi:  sqlmap -u 'http://$TARGET/page?id=1' --batch --dbs"
        echo "    XSS:   Try <script>alert(1)</script> in all inputs"
        echo "    LFI:   Try ../../etc/passwd in file parameters"
        echo "    SSRF:  Try http://127.0.0.1 in URL parameters"
        echo ""
        echo "  Then: bash scripts/tracker.sh done vuln-2-manual"
        ;;
      exploit-1-initial)
        echo "  STEP: Exploitation — Get Initial Access"
        echo "  ─────────────────────────────────────────────"
        echo "  Use the vulnerabilities you found to get a shell."
        echo ""
        echo "  Need a reverse shell? Read:"
        echo "    knowledge-base/checklists/reverse-shells.md"
        echo ""
        echo "  Set up listener:"
        echo "    rlwrap nc -lvnp 4444"
        echo ""
        echo "  When you get a shell:"
        echo "    bash scripts/tracker.sh shell reverse $TARGET"
        echo "    bash scripts/tracker.sh done exploit-1-initial"
        ;;
      postex-1-privesc)
        echo "  STEP: Privilege Escalation"
        echo "  ─────────────────────────────────────────────"
        echo "  Read: playbooks/privilege-escalation.md"
        echo ""
        echo "  Linux:"
        echo "    sudo -l"
        echo "    find / -perm -4000 -type f 2>/dev/null"
        echo "    Download and run linpeas.sh"
        echo ""
        echo "  Windows:"
        echo "    whoami /all"
        echo "    Download and run winpeas.exe"
        echo ""
        echo "  Then: bash scripts/tracker.sh done postex-1-privesc"
        ;;
      postex-2-loot)
        echo "  STEP: Post-Exploitation — Loot & Credentials"
        echo "  ─────────────────────────────────────────────"
        echo "  Grab everything valuable:"
        echo ""
        echo "  Linux:"
        echo "    cat /etc/shadow"
        echo "    find / -name '*.conf' -exec grep -l 'pass' {} \\;"
        echo "    cat ~/.bash_history"
        echo ""
        echo "  Windows:"
        echo "    impacket-secretsdump DOMAIN/user:pass@$TARGET"
        echo "    mimikatz: sekurlsa::logonpasswords"
        echo ""
        echo "  Log creds: bash scripts/tracker.sh creds <user> <pass>"
        echo "  Then: bash scripts/tracker.sh done postex-2-loot"
        ;;
      postex-3-lateral)
        echo "  STEP: Lateral Movement"
        echo "  ─────────────────────────────────────────────"
        echo "  Read: knowledge-base/mitre-attack/techniques/lateral-movement-deep.md"
        echo ""
        echo "  Try credentials on other hosts:"
        echo "    crackmapexec smb SUBNET/24 -u USER -p PASS"
        echo "    crackmapexec smb SUBNET/24 -u USER -H HASH"
        echo ""
        echo "  Then: bash scripts/tracker.sh done postex-3-lateral"
        ;;
      report)
        echo "  STEP: Write the Report"
        echo "  ─────────────────────────────────────────────"
        echo "  Copy and fill the template:"
        echo "    cp templates/attack-report-template.md reports/${TARGET//\//-}/report.md"
        echo ""
        echo "  Include ALL findings, credentials, shells, and steps."
        echo "  Run: bash scripts/tracker.sh status  ← to see everything you found"
        echo ""
        echo "  Then: bash scripts/tracker.sh done report"
        ;;
      complete)
        echo "  🎉 ENGAGEMENT COMPLETE!"
        echo ""
        echo "  All steps done. Report should be in reports/"
        echo "  Run: bash scripts/tracker.sh status  ← for final summary"
        ;;
      *)
        echo "  Unknown step: $CURRENT"
        echo "  Run: bash scripts/tracker.sh status"
        ;;
    esac
    ;;

  # ─── MARK DONE ──────────────────────────────────────────
  done)
    STEP="${2}"
    if [ -z "$STEP" ]; then
      echo "Usage: bash scripts/tracker.sh done <step-name>"
      exit 1
    fi
    
    # Read current state
    CURRENT=$(cat "$STATE_FILE" | grep -o '"current_step":"[^"]*"' | cut -d'"' -f4)
    
    # Add to steps_done
    python3 -c "
import json
with open('$STATE_FILE') as f: state = json.load(f)
if '$STEP' not in state['steps_done']:
    state['steps_done'].append('$STEP')

# Advance to next step
progression = {
    'recon-1-portscan': 'recon-2-enumerate',
    'recon-2-enumerate': 'vuln-1-scan',
    'vuln-1-scan': 'vuln-2-manual',
    'vuln-2-manual': 'exploit-1-initial',
    'exploit-1-initial': 'postex-1-privesc',
    'postex-1-privesc': 'postex-2-loot',
    'postex-2-loot': 'postex-3-lateral',
    'postex-3-lateral': 'report',
    'report': 'complete'
}

phases = {
    'recon-1-portscan': 'recon',
    'recon-2-enumerate': 'recon',
    'vuln-1-scan': 'vulnerability-assessment',
    'vuln-2-manual': 'vulnerability-assessment',
    'exploit-1-initial': 'exploitation',
    'postex-1-privesc': 'post-exploitation',
    'postex-2-loot': 'post-exploitation',
    'postex-3-lateral': 'post-exploitation',
    'report': 'reporting',
    'complete': 'complete'
}

next_step = progression.get('$STEP', state['current_step'])
state['current_step'] = next_step
state['phase'] = phases.get(next_step, state['phase'])

with open('$STATE_FILE', 'w') as f: json.dump(state, f)
print(f'✅ Marked done: $STEP')
print(f'👉 Next step: {next_step}')
print(f'📍 Phase: {state[\"phase\"]}')
" 2>/dev/null || echo "Error updating state"
    
    echo ""
    echo "Run: bash scripts/tracker.sh next    ← to see what to do"
    ;;

  # ─── LOG FINDING ────────────────────────────────────────
  found)
    shift
    FINDING="$*"
    echo "[$(date '+%H:%M')] $FINDING" >> "$FINDINGS_FILE"
    
    python3 -c "
import json
with open('$STATE_FILE') as f: state = json.load(f)
state['findings'].append('$FINDING')
with open('$STATE_FILE', 'w') as f: json.dump(state, f)
" 2>/dev/null
    
    echo "📝 Logged: $FINDING"
    ;;

  # ─── LOG CREDENTIALS ────────────────────────────────────
  creds)
    USER="${2}"
    PASS="${3}"
    echo "[$(date '+%H:%M')] CREDS: $USER:$PASS" >> "$FINDINGS_FILE"
    
    python3 -c "
import json
with open('$STATE_FILE') as f: state = json.load(f)
state['creds'].append('$USER:$PASS')
with open('$STATE_FILE', 'w') as f: json.dump(state, f)
" 2>/dev/null
    
    echo "🔑 Logged credentials: $USER:$PASS"
    echo ""
    echo "  Now try them on all services:"
    TARGET=$(cat "$STATE_FILE" | grep -o '"target":"[^"]*"' | cut -d'"' -f4)
    echo "    crackmapexec smb $TARGET -u $USER -p '$PASS'"
    echo "    crackmapexec winrm $TARGET -u $USER -p '$PASS'"
    echo "    evil-winrm -i $TARGET -u $USER -p '$PASS'"
    echo "    ssh $USER@$TARGET"
    ;;

  # ─── LOG SHELL ──────────────────────────────────────────
  shell)
    SHELL_TYPE="${2}"
    SHELL_TARGET="${3}"
    echo "[$(date '+%H:%M')] SHELL: $SHELL_TYPE on $SHELL_TARGET" >> "$FINDINGS_FILE"
    
    python3 -c "
import json
with open('$STATE_FILE') as f: state = json.load(f)
state['shells'].append('$SHELL_TYPE on $SHELL_TARGET')
with open('$STATE_FILE', 'w') as f: json.dump(state, f)
" 2>/dev/null
    
    echo "💀 Shell logged: $SHELL_TYPE on $SHELL_TARGET"
    echo ""
    echo "  Next: stabilize your shell and escalate privileges"
    echo "  Read: playbooks/privilege-escalation.md"
    ;;

  # ─── RESET ──────────────────────────────────────────────
  reset)
    echo '{"target":"","type":"","phase":"idle","steps_done":[],"current_step":"","creds":[],"shells":[],"findings":[]}' > "$STATE_FILE"
    > "$FINDINGS_FILE" 2>/dev/null
    echo "🔄 Tracker reset"
    ;;

  *)
    echo "Usage: bash scripts/tracker.sh <status|start|next|done|found|creds|shell|reset>"
    ;;
esac
