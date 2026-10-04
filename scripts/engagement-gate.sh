#!/usr/bin/env bash
# engagement-gate.sh — Turn discipline from advice into a tripwire.
#
# THE PROBLEM (nest audit, 2026-10): every gate (stop-gate.sh, hypotheses.sh
# enforcement, loop-guard.sh) only runs if the model *volunteers* to call it.
# A weak model can declare "done" without ever touching the bank — exactly how
# GLM solved fireflow with a 0-item hypotheses.json. All the enforcement code
# is dead unless something invokes it at turn-end.
#
# This script is that something. It is designed to be the body of a Claude Code
# `Stop` hook. A Stop hook that exits 2 blocks turn-end and feeds its stderr
# back to the model — so the bypass is physically prevented, not just advised.
#
# OPT-IN (the operator enables this; it changes harness behavior for the agent):
#   Add to .claude/settings.json (or settings.local.json):
#     {
#       "hooks": {
#         "Stop": [
#           { "hooks": [ { "type": "command",
#               "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/engagement-gate.sh\"" } ] }
#         ]
#       }
#     }
#   It is quiet outside an active engagement, so it won't disturb normal chat.
#
# DESIGN: it is NARROW on purpose — it only BLOCKS the clear bypass, so it never
# gets in the way of normal progress/reporting mid-engagement:
#   * No active engagement (no state/orchestrator.json target) -> exit 0 (quiet).
#   * Engagement active, both flags captured -> exit 0 (stop-gate owns "done").
#   * Engagement active, NO flags, and the hypothesis bank is EMPTY (0 items)
#     -> exit 2 (BLOCK): the reasoning loop was bypassed. Populate the bank.
#   * Otherwise -> exit 0 but print stop-gate's reason as a nudge.
#
# Exit codes:  0 = ok to stop / proceed   2 = blocked (loop bypassed)

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"

# No active engagement -> never interfere.
[[ -f "$STATE" ]] || exit 0
TARGET=$(python3 -c "import json;print(json.load(open('$STATE')).get('target') or '')" 2>/dev/null) || exit 0
[[ -n "$TARGET" ]] || exit 0

SLUG=$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')
DIR="$WS/reports/$SLUG"
[[ -d "$DIR" ]] || exit 0

# Both flags present? stop-gate owns the "done" decision; don't block.
if [[ -s "$DIR/loot/user.txt" && -s "$DIR/loot/root.txt" ]]; then
  exit 0
fi

# How many hypotheses in the bank?
N=$(python3 -c "import json;print(len(json.load(open('$DIR/hypotheses.json')).get('items',[])))" 2>/dev/null || echo 0)

if [[ "${N:-0}" -eq 0 ]]; then
  echo "🚫 ENGAGEMENT GATE — the hypothesis bank for $TARGET is EMPTY and no flags are captured."
  echo "   You are about to stop having bypassed the entire reasoning loop (the"
  echo "   GLM/fireflow failure). This is not acceptable. Do this before stopping:"
  echo "     bash scripts/think.sh"
  echo "     bash scripts/hypotheses.sh add \"<H>\" --falsifier \"<cmd>\" --cost LOW --impact HIGH --phase enum"
  echo "   (≥5 open hypotheses during enumeration — AGENTS.md R3.)"
  exit 2
fi

# Bank is populated — advisory nudge with the real stop-gate verdict.
echo "ℹ️  engagement-gate: bank has $N hypotheses. stop-gate verdict:"
bash "$WS/scripts/stop-gate.sh" "$TARGET" --why 2>/dev/null | sed 's/^/   /' | head -6 || true
exit 0
