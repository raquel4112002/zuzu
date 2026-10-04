#!/usr/bin/env bash
# flag.sh — Persist a flag THE INSTANT you read it. Not at report time.
#
# WHY: models tend to keep the flag in context and only write loot/user.txt +
# loot/root.txt at the end (same mtime) — which (a) loses the capture TIME
# (can't tell t->user from t->root) and (b) LOSES THE FLAG if the box/session
# dies first (exactly what bit Nimbus: got user, box died, flag only in context).
#
# Writing the flag here, at capture, fixes both: it persists immediately
# (survives a box re-spawn) and gives loot/<flag>.txt the correct mtime, so
# score.py's time-to-flag becomes real and separable. Also stamps the timeline.
#
# Usage:
#   bash scripts/flag.sh user <value> [target]
#   bash scripts/flag.sh root <value> [target]
#
# Run it the MOMENT you see a flag value — before continuing, before the report.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"

KIND="${1:-}"; VALUE="${2:-}"; TARGET="${3:-}"
case "$KIND" in user|root) ;; *) echo "Usage: flag.sh <user|root> <value> [target]"; exit 2;; esac
[[ -n "$VALUE" ]] || { echo "Usage: flag.sh $KIND <value> [target]"; exit 2; }

[[ -z "$TARGET" && -f "$STATE" ]] && TARGET=$(python3 -c "import json;print(json.load(open('$STATE')).get('target') or '')" 2>/dev/null)
[[ -n "$TARGET" ]] || { echo "No target. Usage: flag.sh $KIND <value> <target>"; exit 1; }
SLUG=$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')
DIR="$WS/reports/$SLUG"; LOOT="$DIR/loot"
mkdir -p "$LOOT"

OUT="$LOOT/$KIND.txt"
if [[ -s "$OUT" ]] && [[ "$(cat "$OUT" 2>/dev/null)" != "$VALUE" ]]; then
  echo "⚠  $OUT already holds a different value — keeping a copy at $OUT.prev"
  cp "$OUT" "$OUT.prev"
fi
printf '%s\n' "$VALUE" > "$OUT"
echo "🚩 $KIND.txt PERSISTED -> reports/$SLUG/loot/$KIND.txt  ($VALUE)"

# Stamp the capture time on the timeline (best-effort).
bash "$WS/scripts/phase.sh" "$KIND-flag" >/dev/null 2>&1 || true
echo "   ⏱  timeline stamped: $KIND-flag"

if [[ "$KIND" == root ]]; then
  echo "   → box likely done. Verify: bash scripts/stop-gate.sh $TARGET --why"
else
  echo "   → user captured. Keep going for root (objective #2). Don't wait for the report."
fi
