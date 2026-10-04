#!/usr/bin/env bash
# swarm.sh — Coordinator helper for parallel, multi-front box attacks.
#
# MODEL: one COORDINATOR owns target-model.md + the hypothesis bank and connects
# the dots. It fans out INDEPENDENT hypotheses to WORKER subagents (same model),
# each probing a different front in a SMALL fresh context, and serializes
# anything that mutates shared box state through scripts/lease.sh.
#
# Read-only on the bank (the coordinator stays the single writer — workers
# REPORT findings back, they don't edit hypotheses.json). It:
#   plan         — classify open hypotheses parallel-safe vs exclusive, and
#                  print the fan-out set + the serialize set.
#   worker-brief — emit the standard worker prompt for one hypothesis id.
#   lanes        — show per-lane evidence dirs.
#
# PARALLEL-SAFE vs EXCLUSIVE is a heuristic on the falsifier (the coordinator
# can override): anything that uploads, brute-forces, binds a listener, or
# otherwise mutates shared state is EXCLUSIVE and needs a lease. Read-only
# probes (GET, enum, fingerprint) are parallel-safe.
#
# Usage:
#   bash scripts/swarm.sh plan [--workers N]
#   bash scripts/swarm.sh worker-brief <hypothesis-id>
#   bash scripts/swarm.sh lanes

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"

slug() {
  [[ -f "$STATE" ]] || { echo ""; return; }
  python3 -c "import json;print(json.load(open('$STATE')).get('target') or '')" 2>/dev/null \
    | tr '/' '-' | tr -cd 'a-zA-Z0-9._-'
}
SLUG="$(slug)"
[[ -n "$SLUG" ]] || { echo "No active engagement (state/orchestrator.json has no target)."; exit 1; }
BANK="$WS/reports/$SLUG/hypotheses.json"
TARGET="$(python3 -c "import json;print(json.load(open('$STATE'))['target'])" 2>/dev/null)"

# Heuristic classifier (shared by plan + worker-brief).
classify_py() {
cat <<'PY'
import json, re, sys
bank = sys.argv[1]
want = sys.argv[2] if len(sys.argv) > 2 else ""
try:
    items = json.load(open(bank)).get("items", [])
except Exception:
    print("_no bank_"); sys.exit(0)

# Exclusive = mutates shared box state -> must be serialized via a lease.
EXCL = {
    "upload-queue": r"(curl[^\n]*-F |multipart|upload|/upload|form-data|\.pickle|watcher)",
    "ssh-brute":    r"(hydra|medusa|ncrack|patator|crackmapexec|netexec|ssh.*(rockyou|passwords\.txt)|brute)",
    "callback":     r"(nc +-l|nc .*-lvnp|ncat +-l|/dev/tcp|reverse shell|msf|exploit/|LHOST|set payload|socat .*LISTEN)",
    "write-sink":   r"(authorized_keys|>>?\s*/|mkfifo|crontab|put |smbclient.*put|tftp.*put)",
}
def exclusive_of(f):
    f = (f or "")
    for res, pat in EXCL.items():
        if re.search(pat, f, re.I):
            return res
    return None

rows = []
for it in items:
    if it.get("status") != "open":
        continue
    res = exclusive_of(it.get("falsifier", ""))
    rows.append((it, res))

if want == "exclusive":
    rows = [r for r in rows if r[1]]
elif want == "parallel":
    rows = [r for r in rows if not r[1]]

cw = {"LOW": 1, "MED": 2, "HIGH": 3}
iw = {"LOW": 1, "MED": 2, "HIGH": 3}
def ev(it):
    return iw.get(it.get("impact","MED").upper(),2) / cw.get(it.get("cost","MED").upper(),2)
rows.sort(key=lambda r: -ev(r[0]))
for it, res in rows:
    tag = f"EXCLUSIVE:{res}" if res else "parallel-safe"
    print(f"{it['id']}\t{tag}\t{it.get('phase','?')}\t{it.get('cost','?')}/{it.get('impact','?')}\t{it['h'][:72]}")
PY
}

ACTION="${1:-}"; shift 2>/dev/null || true
case "$ACTION" in
  plan)
    WORKERS=3
    while [[ $# -gt 0 ]]; do case "$1" in --workers) WORKERS="$2"; shift 2;; *) shift;; esac; done
    echo "═══ SWARM PLAN — $TARGET ═══"
    echo ""
    echo "▶ FAN OUT (parallel-safe, top $WORKERS) — one worker each, concurrently:"
    python3 -c "$(classify_py)" "$BANK" parallel | head -n "$WORKERS" \
      | awk -F'\t' '{printf "   %-4s [%s] %s/%s  %s\n",$1,$2,$3,$4,$5}'
    echo ""
    echo "⛓ SERIALIZE (exclusive — one at a time, acquire the lease first):"
    python3 -c "$(classify_py)" "$BANK" exclusive \
      | awk -F'\t' '{printf "   %-4s %-20s %s  %s\n",$1,$2,$4,$5}'
    echo ""
    echo "▶ Spawn each fan-out worker (same model) with sessions_spawn, task ="
    echo "    bash scripts/swarm.sh worker-brief <id>"
    echo "  (coordinator stays the single writer of the bank — workers report back)"
    ;;
  worker-brief)
    HID="${1:-}"; [[ -n "$HID" ]] || { echo "Usage: swarm.sh worker-brief <id>"; exit 2; }
    LINE=$(python3 -c "$(classify_py)" "$BANK" | awk -F'\t' -v id="$HID" '$1==id')
    [[ -n "$LINE" ]] || { echo "No OPEN hypothesis $HID in the bank."; exit 1; }
    TAG=$(echo "$LINE" | cut -f2); HTXT=$(echo "$LINE" | cut -f5-)
    FALS=$(python3 -c "import json,sys;print(next((i.get('falsifier','') for i in json.load(open('$BANK'))['items'] if i['id']=='$HID'),''))" 2>/dev/null)
    LANE="reports/$SLUG/lanes/$HID"
    cat <<EOF
Read AGENTS.md, THINK.md, PILOT.md before anything. You are bound by the same
operating contract. You are a SWARM WORKER on target $TARGET — one front only.

YOUR HYPOTHESIS ($HID): $HTXT
FALSIFIER: $FALS
CLASSIFICATION: $TAG

RULES FOR WORKERS:
- Test ONLY this hypothesis. Do not wander to other vectors — the coordinator
  owns the overall plan and will chain your result.
- Do NOT edit hypotheses.json. Write evidence to $LANE/ and REPORT BACK a
  compact result: CONFIRMED | FALSIFIED | INCONCLUSIVE, the evidence path, and
  any NEW LEADS you noticed (so the coordinator can connect the dots).
$(if [[ "$TAG" == EXCLUSIVE:* ]]; then
  res="${TAG#EXCLUSIVE:}"
  echo "- This is EXCLUSIVE (mutates shared box state). ACQUIRE THE LEASE FIRST:"
  echo "    bash scripts/lease.sh acquire ${res} --owner $HID --ttl 300 --wait 120"
  echo "  If BUSY, do not force it — report back 'blocked on lease ${res}' so the"
  echo "  coordinator sequences you. RELEASE when done: lease.sh release ${res}"
  echo "- If you need a reverse-shell port, acquire callback:<port> too."
else
  echo "- This is PARALLEL-SAFE (read-only / independent). No lease needed."
  echo "- Stay read-only: do not upload, brute-force, or bind listeners here."
fi)
- Time-box every scan/fuzz (scripts/timebox.sh). If you repeat a dead move,
  loop-guard.sh will tell you to pivot — obey it (R17).
- If you get a foothold: STOP, capture it (flag.sh), report immediately. Finding
  user.txt is objective #1; do not start a root hunt (coordinator serializes privesc).
EOF
    ;;
  lanes)
    D="$WS/reports/$SLUG/lanes"
    [[ -d "$D" ]] && ls -la "$D" || echo "(no lanes yet — reports/$SLUG/lanes/)"
    ;;
  *)
    echo "swarm.sh — coordinator helper for parallel multi-front attacks"
    echo "Usage: swarm.sh plan [--workers N] | worker-brief <id> | lanes"
    exit 2;;
esac
