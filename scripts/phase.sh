#!/usr/bin/env bash
# phase.sh — Stamp phase transitions so we can SEE where time goes.
#
# You cannot make an engagement faster if you don't know which phase is slow.
# This records a timestamp each time you enter a new phase; durations are the
# diffs. score.py folds them into the benchmark row, so the matrix shows
# "recon 42m, foothold 8m, privesc 19m" instead of just t->flag.
#
# Usage:
#   bash scripts/phase.sh <name>     # entering <name> now (recon|foothold|privesc|root|lateral|...)
#   bash scripts/phase.sh timeline   # print phases + durations
#   bash scripts/phase.sh done       # close the current phase
#
# Storage: reports/<slug>/.phases.json  {"marks":[{"phase":..,"at":epoch}]}
# Active target comes from state/orchestrator.json (like hypotheses.sh).

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"

[[ -f "$STATE" ]] || { echo "❌ No active engagement. Run: bash scripts/pentest.sh <target>"; exit 1; }
TARGET=$(python3 -c "import json;print(json.load(open('$STATE'))['target'])" 2>/dev/null) || { echo "❌ cannot read target"; exit 1; }
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
PHASES="$WS/reports/$SLUG/.phases.json"
mkdir -p "$(dirname "$PHASES")"

ACTION="${1:-timeline}"

case "$ACTION" in
  timeline)
    python3 - "$PHASES" <<'PY'
import json, sys, os, time
p = sys.argv[1]
if not os.path.exists(p):
    print("(no phases recorded yet — run: bash scripts/phase.sh recon)"); sys.exit(0)
marks = json.load(open(p)).get("marks", [])
if not marks:
    print("(no phases recorded)"); sys.exit(0)
def hm(s):
    m, sec = divmod(int(s), 60); h, m = divmod(m, 60)
    return f"{h}h{m:02d}m" if h else f"{m}m{sec:02d}s"
now = int(time.time())
print("\n── Phase timeline ──")
total = 0
for i, mk in enumerate(marks):
    end = marks[i+1]["at"] if i+1 < len(marks) else now
    dur = end - mk["at"]
    total += dur
    live = "" if i+1 < len(marks) else "  (ongoing)"
    print(f"  {mk['phase']:<12} {hm(dur)}{live}")
print(f"  {'TOTAL':<12} {hm(total)}\n")
PY
    ;;
  done)
    python3 - "$PHASES" <<'PY'
import json, sys, os, time
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {"marks": []}
d["marks"].append({"phase": "_done", "at": int(time.time())})
json.dump(d, open(p, "w"), indent=2)
print("[+] phase timeline closed.")
PY
    ;;
  *)
    NAME="$ACTION"
    python3 - "$PHASES" "$NAME" <<'PY'
import json, sys, os, time
p, name = sys.argv[1], sys.argv[2]
d = json.load(open(p)) if os.path.exists(p) else {"marks": []}
# ignore a no-op re-entry of the same phase
if d["marks"] and d["marks"][-1].get("phase") == name:
    print(f"[=] already in phase '{name}'."); sys.exit(0)
d["marks"].append({"phase": name, "at": int(time.time())})
json.dump(d, open(p, "w"), indent=2)
print(f"[+] phase → {name}")
PY
    ;;
esac
