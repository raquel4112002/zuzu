#!/usr/bin/env bash
# compact.sh — Context hygiene: re-anchor on disk, drop the scrollback.
#
# THE PROBLEM (Nimbus hard box, 2026-10): one engagement billed 283 MILLION
# cacheRead tokens across 1004 requests (~282k context PER request) = ~$11.48,
# almost all of it re-reading its own bloated context. A model wading through
# 280k tokens every turn is also LESS focused — expensive AND lost.
#
# Your context is NOT storage. Findings live on disk (target-model.md, surface.md,
# hypotheses.json, loot/, creds/). This prints a tight STATE DIGEST from those
# files so you can re-anchor and let old raw tool-output fall out of context.
#
# Run it periodically (every ~15-20 steps, or whenever the raw scrollback is
# mostly stale tool dumps). Then: rely on this digest, not the scrollback.
#
# Usage: bash scripts/compact.sh [target]

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"
TARGET="${1:-}"
[[ -z "$TARGET" && -f "$STATE" ]] && TARGET=$(python3 -c "import json;print(json.load(open('$STATE')).get('target') or '')" 2>/dev/null)
[[ -n "$TARGET" ]] || { echo "No target. Usage: compact.sh <target>"; exit 1; }
SLUG=$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')
D="$WS/reports/$SLUG"
[[ -d "$D" ]] || { echo "No engagement dir: $D"; exit 1; }

sec() { echo; echo "── $1 ──"; }

echo "═══════════ STATE DIGEST — $TARGET ═══════════"
echo "This is your durable state. DROP stale raw tool-output from context and"
echo "re-anchor HERE. Re-read a specific file only when you need its detail."

sec "OPEN PORTS / SERVICES (surface.md)"
grep -iE "^\s*[-|].*(open|tcp|udp|http|ssh|smb|:[0-9])" "$D/surface.md" 2>/dev/null | head -15 || echo "(surface.md empty — run recon)"

sec "TARGET MODEL — confirmed facts & edges (target-model.md)"
awk '/[Cc]onfirmed|[Ff]act|[Ee]dge|BYPASS|→|->/{print}' "$D/target-model.md" 2>/dev/null | grep -vE "^\s*$" | head -25 || echo "(target-model.md thin)"

sec "OPEN HYPOTHESES (ranked — your work queue)"
bash "$WS/scripts/hypotheses.sh" list --rank 2>/dev/null | grep -E "^\| H[0-9]" | head -12 || echo "(no bank)"

sec "CREDENTIALS / KEYS collected"
for f in "$D"/creds/*; do [[ -f "$f" ]] && { echo "• $(basename "$f"):"; head -6 "$f" 2>/dev/null | sed 's/^/    /'; }; done 2>/dev/null
ls "$D"/creds/* >/dev/null 2>&1 || echo "(none yet)"

sec "LOOT inventory (don't re-download — read from here)"
ls -1 "$D/loot" 2>/dev/null | head -25 || echo "(empty — SAVE findings here instead of keeping them in context)"

sec "FLAGS"
for fl in user root; do
  if [[ -s "$D/loot/$fl.txt" ]]; then echo "• $fl.txt ✓ ($(wc -c <"$D/loot/$fl.txt" | tr -d ' ') bytes)"; else echo "• $fl.txt — not captured"; fi
done

sec "WORKSPACE HYGIENE (R14) — loose files in the nest root?"
STRAY=$(find "$WS" -maxdepth 1 -type f ! -name "*.md" ! -name ".gitignore" ! -name "*.json" ! -name "*.deb" 2>/dev/null)
if [[ -n "$STRAY" ]]; then
  echo "⚠  Loose files in the workspace ROOT — these belong in your engagement folder:"
  echo "$STRAY" | sed 's#.*/#    #'
  echo "  Exploit scripts/payloads go to reports/$SLUG/exploits/ — move them:"
  echo "    mkdir -p reports/$SLUG/exploits && mv $(echo "$STRAY" | tr '\n' ' ') reports/$SLUG/exploits/"
  echo "  Write new exploit code straight there: reports/$SLUG/exploits/<name>  (NOT bare names in cwd)."
else
  echo "✓ root clean"
fi

echo
echo "═══ END DIGEST — continue from the top-ranked open hypothesis. ═══"
echo "Reminder: write new findings to loot/ + target-model.md AS YOU GO, then"
echo "they survive compaction and a box re-spawn (R2/R16)."
