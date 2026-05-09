#!/usr/bin/env bash
# stop-gate.sh — Deterministic check whether an engagement is allowed to
# stop. A weak LLM cannot self-rationalise its way past this script.
#
# Usage:
#   bash scripts/stop-gate.sh <target>          # exits 0 if stop is OK
#   bash scripts/stop-gate.sh <target> --why    # also prints the reasoning
#
# Exit codes:
#   0 — stop is permitted (a real success or fully-documented blocker)
#   1 — stop is NOT permitted (keep working — reason printed)
#   2 — usage error
#
# Stop is permitted iff at least one of:
#   A) reports/<target>/loot/user.txt   AND  reports/<target>/loot/root.txt
#      both exist and are non-empty (HTB-style flags).
#   B) reports/<target>/loot/<anything>flag<anything>.txt exists, non-empty,
#      and ENGAGEMENT.md "Flags / proof" section has at least one ticked box.
#   C) ENGAGEMENT.md "Stuck-gate / hypotheses" section contains 3 hypotheses
#      AND each has a non-pending result line, AND notes.md has the same
#      three hypothesis labels (H1/H2/H3) recorded.
#
# Anything else → keep working.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"
VERBOSE="${2:-}"

if [[ -z "$TARGET" ]]; then
  echo "Usage: bash scripts/stop-gate.sh <target> [--why]"
  exit 2
fi

SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"

if [[ ! -d "$DIR" ]]; then
  echo "❌ No engagement folder for '$TARGET'. Run: bash scripts/pentest.sh $TARGET"
  exit 1
fi

reason() {
  if [[ "$VERBOSE" == "--why" ]]; then
    echo "$1"
  fi
}

# A) HTB-style flags
USER_F="$DIR/loot/user.txt"
ROOT_F="$DIR/loot/root.txt"
if [[ -s "$USER_F" && -s "$ROOT_F" ]]; then
  reason "✅ STOP OK — user.txt and root.txt both present and non-empty."
  exit 0
fi

# B) Generic flag file + ticked proof box in ENGAGEMENT.md
ENG="$DIR/ENGAGEMENT.md"
if compgen -G "$DIR/loot/*flag*.txt" >/dev/null 2>&1; then
  if [[ -f "$ENG" ]] && grep -qE '^\s*-\s*\[x\].*(flag|proof|root\.txt|user\.txt|domain admin)' "$ENG" -i; then
    reason "✅ STOP OK — flag file in loot/ and ENGAGEMENT.md proof box ticked."
    exit 0
  fi
fi

# C) Documented blocker — 3 hypotheses with non-pending results
if [[ -f "$ENG" ]]; then
  H_LINES=$(grep -cE '^\s*-\s*\*\*H[123]\*\*' "$ENG" 2>/dev/null || echo 0)
  PENDING=$(grep -cE 'Result:\s*_pending_' "$ENG" 2>/dev/null || echo 0)
  if (( H_LINES >= 3 )) && (( PENDING == 0 )); then
    NOTES="$DIR/notes.md"
    if [[ -f "$NOTES" ]] && grep -q "H1" "$NOTES" && grep -q "H2" "$NOTES" && grep -q "H3" "$NOTES"; then
      reason "✅ STOP OK — three hypotheses falsified in ENGAGEMENT.md and recorded in notes.md."
      exit 0
    else
      reason "❌ Keep working. ENGAGEMENT.md has 3 hypotheses but notes.md is missing H1/H2/H3 evidence."
      exit 1
    fi
  fi
fi

# Otherwise: not allowed to stop. Tell the model exactly what's missing.
cat <<EOF
❌ STOP NOT PERMITTED — engagement is not finished.

Target: $TARGET
Folder: $DIR

To stop, satisfy ONE of:

 A) Capture flags
    Create non-empty files:
      $DIR/loot/user.txt
      $DIR/loot/root.txt

 B) Generic proof + ticked engagement box
    - Drop a *flag*.txt into $DIR/loot/
    - Tick a "Flags / proof" checkbox in $DIR/ENGAGEMENT.md
      (e.g. "- [x] root.txt — <hash>")

 C) Documented blocker (only if attack genuinely impossible right now)
    - Fill the "Stuck-gate / hypotheses" section in ENGAGEMENT.md with
      H1, H2, H3 — each with a falsifier command and a non-pending Result.
    - Mirror H1/H2/H3 evidence into $DIR/notes.md.

Until then: bash scripts/orchestrator.sh think
EOF
exit 1
