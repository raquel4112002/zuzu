#!/usr/bin/env bash
# loop-guard.sh — Anti-spin tripwire (AGENTS.md R17).
#
# WHY: the bedside.htb run burned ~4h partly re-listing the same empty dirs
# every ~5 min and re-fuzzing a 404-ing route. Repeating a move that already
# answered (empty / 404 / identical output) is the loop spinning, not progress.
#
# Pass a short SIGNATURE of the move you are about to repeat (the command, or
# command+result class). The guard counts how many times it has seen that
# signature this engagement and escalates:
#   1st time  -> ok (exit 0)
#   2nd time  -> ⚠ warning (exit 0)
#   3rd+ time -> 🚨 PIVOT (exit 3)  — stop, falsify the hypothesis, change vector.
#
# Usage:
#   bash scripts/loop-guard.sh "ls /datastore (empty)"       # record + check
#   bash scripts/loop-guard.sh --reset                       # new vector/phase
#   bash scripts/loop-guard.sh --top                         # show hottest loops
#
# Scope is per-target (keyed off state/orchestrator.json).

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"

slug() {
  [[ -f "$STATE" ]] || { echo "_notarget"; return; }
  python3 -c "import json;print(json.load(open('$STATE'))['target'])" 2>/dev/null \
    | tr '/' '-' | tr -cd 'a-zA-Z0-9._-' || echo "_notarget"
}
LOG="$WS/state/loop-guard.$(slug).log"

case "${1:-}" in
  --reset)
    : > "$LOG" 2>/dev/null || true
    echo "[loop-guard] reset for $(slug)"; exit 0;;
  --top)
    [[ -f "$LOG" ]] || { echo "(no loops recorded)"; exit 0; }
    echo "── hottest loops (count · signature) ──"
    sort "$LOG" | uniq -c | sort -rn | head -15; exit 0;;
  "" )
    echo "Usage: loop-guard.sh \"<signature>\" | --reset | --top"; exit 2;;
esac

SIG="$(printf '%s' "$*" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')"
HASH="$(printf '%s' "$SIG" | cksum | cut -d' ' -f1)"
mkdir -p "$(dirname "$LOG")"
printf '%s\t%s\n' "$HASH" "$SIG" >> "$LOG"
N=$(cut -f1 "$LOG" | grep -cx "$HASH")

if   (( N >= 3 )); then
  echo "🚨 PIVOT (R17/R5) — you have repeated this move ${N}× this engagement:"
  echo "   \"$SIG\""
  echo "   It is answered. Record it as FALSIFIED and change vector NOW."
  echo "   (hypotheses.sh result <id> falsified; then list --rank for the next one)"
  exit 3
elif (( N == 2 )); then
  echo "⚠  loop-guard: 2nd time for \"$SIG\". One more = forced pivot (R17)."
  exit 0
else
  exit 0
fi
