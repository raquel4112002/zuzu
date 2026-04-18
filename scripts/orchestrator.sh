#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# ZUZU ATTACK ORCHESTRATOR — Autonomous Phase Controller
# ═══════════════════════════════════════════════════════════════
# The brain that breaks a full engagement into micro-tasks.
# A model calls this, gets ONE clear instruction, executes it,
# reports back, and gets the NEXT instruction. No improvisation.
#
# Usage:
#   bash scripts/orchestrator.sh init <target>              # Start
#   bash scripts/orchestrator.sh think                      # Next action
#   bash scripts/orchestrator.sh report <result>            # Report result
#   bash scripts/orchestrator.sh error <what_failed>        # Report failure
#   bash scripts/orchestrator.sh status                     # Full status
#   bash scripts/orchestrator.sh decide <question>          # Decision help
# ═══════════════════════════════════════════════════════════════

set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$WORKSPACE/scripts"
STATE_DIR="$WORKSPACE/state"
STATE_FILE="$STATE_DIR/orchestrator.json"
ACTION_LOG="$STATE_DIR/action-log.md"
ERRORS_LOG="$STATE_DIR/errors.log"

mkdir -p "$STATE_DIR"

ACTION="${1}"
shift 2>/dev/null || true
ARGS="$*"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

case "$ACTION" in

  # ═══ INIT ═══════════════════════════════════════════════
  init)
    TARGET="$ARGS"
    if [ -z "$TARGET" ]; then
      echo "Usage: bash scripts/orchestrator.sh init <target>"
      exit 1
    fi
    
    REPORT_DIR="$WORKSPACE/reports/${TARGET//\//-}"
    mkdir -p "$REPORT_DIR"
    
    python3 -c "
import json
state = {
    'target': '$TARGET',
    'report_dir': '$REPORT_DIR',
    'phase': 'recon',
    'sub_phase': 'portscan',
    'attempt': 0,
    'max_retries': 3,
    'ports': {'tcp': [], 'udp': []},
    'services': {},
    'hostnames': [],
    'web_paths': [],
    'credentials': [],
    'shells': [],
    'findings': [],
    'flags': {},
    'files_read': [],
    'commands_run': [],
    'errors': [],
    'decision_log': [],
    'phase_history': []
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"
    
    echo "# Attack Log — $TARGET" > "$ACTION_LOG"
    echo "Started: $(timestamp)" >> "$ACTION_LOG"
    echo "" >> "$ACTION_LOG"
    
    cat << EOF
╔══════════════════════════════════════════════════════════════╗
║  🧠 ORCHESTRATOR INITIALIZED                                ║
╠══════════════════════════════════════════════════════════════╣
║  Target: $TARGET
║                                                              ║
║  THE LOOP:                                                   ║
║  1. bash scripts/orchestrator.sh think         ← What to do ║
║  2. [Run the command it gives you]                           ║
║  3. bash scripts/orchestrator.sh report "..."  ← Report     ║
║  4. GOTO 1                                                   ║
║                                                              ║
║  If something fails:                                         ║
║     bash scripts/orchestrator.sh error "..."                 ║
║                                                              ║
║  START NOW:                                                  ║
║     bash scripts/orchestrator.sh think                       ║
╚══════════════════════════════════════════════════════════════╝
EOF
    ;;

  # ═══ THINK ══════════════════════════════════════════════
  think)
    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No active engagement. Run: bash scripts/orchestrator.sh init <target>"
      exit 1
    fi
    python3 "$SCRIPTS_DIR/orch-think.py" "$STATE_FILE"
    ;;

  # ═══ REPORT ═════════════════════════════════════════════
  report)
    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No active engagement."
      exit 1
    fi
    
    # Get phase/sub for logging
    PHASE=$(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(s['phase']+'/'+s['sub_phase'])")
    
    python3 "$SCRIPTS_DIR/orch-report.py" "$STATE_FILE" "$ARGS"
    
    echo "## $(timestamp) — $PHASE" >> "$ACTION_LOG"
    echo "Result: $ARGS" >> "$ACTION_LOG"
    echo "" >> "$ACTION_LOG"
    ;;

  # ═══ ERROR ══════════════════════════════════════════════
  error)
    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No active engagement."
      exit 1
    fi
    
    echo "$(timestamp) ERROR: $ARGS" >> "$ERRORS_LOG"
    python3 "$SCRIPTS_DIR/orch-error.py" "$STATE_FILE" "$ARGS"
    ;;

  # ═══ STATUS ═════════════════════════════════════════════
  status)
    if [ ! -f "$STATE_FILE" ]; then
      echo "No active engagement. Run: bash scripts/orchestrator.sh init <target>"
      exit 0
    fi
    python3 "$SCRIPTS_DIR/orch-status.py" "$STATE_FILE"
    ;;

  # ═══ DECIDE ═════════════════════════════════════════════
  decide)
    if [ ! -f "$STATE_FILE" ]; then
      echo "ERROR: No active engagement."
      exit 1
    fi
    
    python3 -c "
import json
question = '''$ARGS'''
with open('$STATE_FILE') as f:
    s = json.load(f)

print('╔══════════════════════════════════════════════════════════════╗')
print('║  🤔 DECISION HELPER                                         ║')
print('╚══════════════════════════════════════════════════════════════╝')
print()
print(f'  Question: {question}')
print()

q = question.lower()

if 'port' in q:
    print('  Priority: Web(80/443) → SMB(445) → FTP(21) → DB → SSH(22)')
elif 'exploit' in q or 'attack' in q or 'vuln' in q:
    print('  Priority: CmdInj → SQLi → FileUpload → KnownCVE → DefaultCreds → BruteForce')
elif 'privesc' in q or 'privilege' in q or 'root' in q:
    print('  Priority: sudo -l → SUID → cron → kernel → docker → capabilities → NFS')
elif 'transfer' in q or 'upload' in q:
    print('  Methods: python3 -m http.server → scp → base64 paste → nc → SMB share')
else:
    print('  Framework: Easiest path? → Largest surface? → Most likely misconfig?')
    print()
    print('  Current findings:')
    for f in s.get('findings', []):
        print(f'    📝 {f}')

s['decision_log'].append({'question': question[:200]})
with open('$STATE_FILE', 'w') as f:
    json.dump(s, f, indent=2)
"
    ;;

  # ═══ RESET ══════════════════════════════════════════════
  reset)
    rm -f "$STATE_FILE" "$ACTION_LOG" "$ERRORS_LOG"
    echo "🔄 Orchestrator reset"
    ;;

  *)
    echo "═══ ZUZU ATTACK ORCHESTRATOR ═══"
    echo ""
    echo "Usage: bash scripts/orchestrator.sh <command> [args]"
    echo ""
    echo "  init <target>          Start new engagement"
    echo "  think                  Get next action (THE MAIN LOOP)"
    echo "  report <result>        Report what happened"
    echo "  error <what_failed>    Report failure (gets fix)"
    echo "  status                 Full engagement status"
    echo "  decide <question>      Help making decisions"
    echo "  reset                  Clear state"
    ;;
esac
