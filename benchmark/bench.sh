#!/usr/bin/env bash
# bench.sh — Reproducible benchmark harness for the Nest.
#
# Turns the anecdotal "a weak model did well once" (papers/the-nest.md 7.1)
# into a measured model x box matrix. One engagement = one scored run.
#
# Subcommands:
#   start  <box> --ip <ip> --model <name> [--hostname <h>]
#                              [--difficulty <d>] [--os <o>]
#        Registers benchmark metadata, wires /etc/hosts if a hostname is
#        given, and primes the engagement via scripts/pentest.sh. The model
#        under test is whatever OpenClaw is configured to use for this agent;
#        --model is the label you record for it.
#
#   score [<box> | --slug <slug>]
#        Freezes end-time, runs stop-gate.sh, extracts metrics, and writes
#        a result row to benchmark/results/. No arg => scores the active
#        engagement (from state/orchestrator.json).
#
#   report [--csv | --md]     Aggregate all result rows into a matrix.
#   list                      Show the box registry and recorded results.
#   status                    Show the active engagement's benchmark meta.
#
# Results (benchmark/results/) are gitignored: they can contain flags/IPs.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$WS/benchmark"
REGISTRY="$BENCH/boxes.json"
RESULTS="$BENCH/results"
STATE="$WS/state/orchestrator.json"
mkdir -p "$RESULTS"

die() { echo "❌ $*" >&2; exit 1; }

slugify() { echo "$1" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-'; }

nest_commit() { git -C "$WS" rev-parse --short HEAD 2>/dev/null || echo "nogit"; }

resolve_slug_for_box() {
  # Find the most recent reports/*/.bench.json whose box == $1
  local box="$1" newest="" newest_mtime=0
  for bf in "$WS"/reports/*/.bench.json; do
    [[ -f "$bf" ]] || continue
    local b; b=$(python3 -c "import json,sys; print(json.load(open('$bf')).get('box',''))" 2>/dev/null)
    if [[ "$b" == "$box" ]]; then
      local m; m=$(stat -c %Y "$bf" 2>/dev/null || echo 0)
      if (( m >= newest_mtime )); then newest_mtime=$m; newest="$(basename "$(dirname "$bf")")"; fi
    fi
  done
  echo "$newest"
}

cmd_start() {
  local box="${1:-}"; shift 2>/dev/null || true
  [[ -n "$box" ]] || die "Usage: bench.sh start <box> --ip <ip> --model <name> [--hostname <h>] [--difficulty <d>] [--os <o>]"
  local ip="" model="" hostname="" difficulty="" os=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ip) ip="$2"; shift 2;;
      --model) model="$2"; shift 2;;
      --hostname) hostname="$2"; shift 2;;
      --difficulty) difficulty="$2"; shift 2;;
      --os) os="$2"; shift 2;;
      *) die "Unknown flag: $1";;
    esac
  done
  [[ -n "$ip" ]] || die "--ip is required (HTB IPs rotate per spawn)."
  [[ -n "$model" ]] || die "--model is required (the label for the model under test)."

  # Pull registry defaults (CLI flags win).
  local reg_diff reg_os reg_arch reg_host
  reg_diff=$(python3 -c "import json; b=json.load(open('$REGISTRY'))['boxes'].get('$box',{}); print(b.get('difficulty',''))" 2>/dev/null || echo "")
  reg_os=$(python3 -c "import json; b=json.load(open('$REGISTRY'))['boxes'].get('$box',{}); print(b.get('os',''))" 2>/dev/null || echo "")
  reg_arch=$(python3 -c "import json; b=json.load(open('$REGISTRY'))['boxes'].get('$box',{}); print(b.get('archetype',''))" 2>/dev/null || echo "")
  [[ -z "$difficulty" ]] && difficulty="$reg_diff"
  [[ -z "$os" ]] && os="$reg_os"
  if [[ -z "$reg_diff" ]]; then
    echo "ℹ️  '$box' not in registry — recording as ad-hoc. Add it to boxes.json for reproducibility."
  fi

  local slug; slug="$(slugify "$ip")"
  local dir="$WS/reports/$slug"

  # Wire /etc/hosts if hostname given and not present.
  if [[ -n "$hostname" ]]; then
    if ! grep -qE "\b$hostname\b" /etc/hosts 2>/dev/null; then
      echo "ℹ️  Add to /etc/hosts (needs sudo):  echo '$ip $hostname' | sudo tee -a /etc/hosts"
    fi
  fi

  echo "═══════════════════════════════════════════════════════════════"
  echo " 🧪 BENCH START — box=$box  model=$model  ip=$ip  [$difficulty/$os]"
  echo "═══════════════════════════════════════════════════════════════"

  # Prime the engagement (creates reports/<slug>, state, artefacts).
  bash "$WS/scripts/pentest.sh" "$ip" "$hostname" || true

  # Record benchmark metadata AFTER pentest.sh so the dir exists.
  mkdir -p "$dir"
  python3 - "$dir/.bench.json" <<PY
import json, sys, time
p = sys.argv[1]
json.dump({
    "box": "$box", "model": "$model", "ip": "$ip",
    "difficulty": "$difficulty" or None, "os": "$os" or None,
    "archetype": "$reg_arch" or None,
    "nest_commit": "$(nest_commit)",
    "started_at": int(time.time()), "ended_at": None,
}, open(p, "w"), indent=2)
print("[+] Benchmark metadata:", p)
PY
  echo ""
  echo "▶ Run the loop as usual (think.sh / hypotheses.sh / ...)."
  echo "▶ When the engagement ends, read usage from session_status, then:"
  echo "    bash benchmark/bench.sh finish $box --tokens <N> --cost <USD> --notes \"<chain>\""
}

cmd_score() {
  local box="" slug="" cin="" cout="" cost="" reqs="" rate="" billed="" notes=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --slug) slug="$2"; shift 2;;
      # Peak context snapshot (from OpenClaw session_status). Not billed usage.
      --context-in|--tokens-in) cin="$2"; shift 2;;
      --context-out|--tokens-out) cout="$2"; shift 2;;
      # Real cumulative usage (from the provider dashboard, e.g. ollama.com/settings).
      --cost) cost="$2"; shift 2;;
      --requests) reqs="$2"; shift 2;;
      --rate) rate="$2"; shift 2;;           # blended $/1M tokens; billed = cost/rate
      --tokens-billed) billed="$2"; shift 2;;
      --notes) notes="$2"; shift 2;;
      *) box="$1"; shift;;
    esac
  done
  if [[ -z "$slug" ]]; then
    if [[ -n "$box" ]]; then
      slug="$(resolve_slug_for_box "$box")"
      [[ -n "$slug" ]] || die "No engagement found for box '$box'. Did you run 'bench start $box ...'?"
    else
      [[ -f "$STATE" ]] || die "No active engagement and no box given."
      local t; t=$(python3 -c "import json; print(json.load(open('$STATE'))['target'])" 2>/dev/null)
      slug="$(slugify "$t")"
    fi
  fi
  local dir="$WS/reports/$slug"
  [[ -d "$dir" ]] || die "No engagement folder: $dir"
  [[ -f "$dir/.bench.json" ]] || die "No .bench.json in $dir — this engagement wasn't started via bench.sh."

  # Freeze end time (only once) and merge finish-time metrics.
  python3 - "$dir/.bench.json" "$cin" "$cout" "$cost" "$reqs" "$rate" "$billed" "$notes" <<'PY'
import json, sys, time
p, cin, cout, cost, reqs, rate, billed, notes = sys.argv[1:9]
d = json.load(open(p))
if not d.get("ended_at"):
    d["ended_at"] = int(time.time())
def num(x):
    try: return int(x)
    except (ValueError, TypeError):
        try: return float(x)
        except (ValueError, TypeError): return None
if cin:    d["context_tokens_in"]  = num(cin)
if cout:   d["context_tokens_out"] = num(cout)
if cost:   d["cost_usd"]           = num(cost)
if reqs:   d["requests"]           = num(reqs)
if rate:   d["rate_per_1m"]        = num(rate)
if billed: d["tokens_billed"]      = num(billed)
if notes:  d["notes"]              = notes
json.dump(d, open(p, "w"), indent=2)
PY

  echo "─── stop-gate check ───"
  bash "$WS/scripts/stop-gate.sh" "$(python3 -c "import json;print(json.load(open('$dir/.bench.json'))['ip'])")" --why || true
  echo ""

  local row; row="$(python3 "$BENCH/score.py" "$slug" --json)"
  local box_name model ts
  box_name=$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin)['box'])")
  model=$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin).get('model') or 'unknown')")
  ts=$(date +%Y%m%d-%H%M%S)
  local model_slug; model_slug="$(slugify "$model")"
  local out="$RESULTS/${box_name}__${model_slug}__${ts}.json"
  echo "$row" > "$out"
  echo "═══════════════════════════════════════════════════════════════"
  python3 "$BENCH/score.py" "$slug" --human
  echo "═══════════════════════════════════════════════════════════════"
  echo "[+] Result row saved: benchmark/results/$(basename "$out")"
  # Append the sanitized, thesis-facing row to RESULTS-LOG.md.
  python3 "$BENCH/log_row.py" "$out"
  if [[ -z "$cost" ]]; then
    echo "ℹ️  No --cost given. The real cost/requests live in the provider"
    echo "   dashboard (ollama.com/settings), not OpenClaw. Re-run with them:"
    echo "   bash benchmark/bench.sh finish $box --cost 4.20 --requests 129 --rate 1.40 --notes \"...\""
    echo "   (--rate = blended \$/1M; billed tokens are derived as cost/rate.)"
  fi
}

cmd_report() {
  local fmt="--md"
  [[ "${1:-}" == "--csv" ]] && fmt="--csv"
  python3 "$BENCH/report.py" "$fmt"
}

cmd_list() {
  echo "── Box registry (benchmark/boxes.json) ──"
  python3 - "$REGISTRY" <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))["boxes"]
for k, v in b.items():
    if k.startswith("_"):
        continue
    print(f"  {k:<16} {v.get('difficulty','?'):<8} {v.get('os','?'):<8} {v.get('archetype','')}")
PY
  echo ""
  echo "── Recorded results (benchmark/results/) ──"
  local n; n=$(find "$RESULTS" -name '*.json' 2>/dev/null | wc -l)
  if (( n == 0 )); then echo "  (none yet)"; else
    for r in "$RESULTS"/*.json; do
      python3 -c "import json;d=json.load(open('$r'));print(f\"  {d['box']:<16}{(d.get('model') or '?'):<20}{d['outcome']}\")" 2>/dev/null
    done
  fi
}

cmd_status() {
  [[ -f "$STATE" ]] || { echo "No active engagement."; return; }
  local t; t=$(python3 -c "import json; print(json.load(open('$STATE'))['target'])" 2>/dev/null)
  local slug; slug="$(slugify "$t")"
  local bf="$WS/reports/$slug/.bench.json"
  if [[ -f "$bf" ]]; then
    echo "── Active benchmark engagement ──"
    python3 -c "import json;d=json.load(open('$bf'));[print(f'  {k}: {v}') for k,v in d.items()]"
  else
    echo "Active engagement '$t' was not started via bench.sh (no .bench.json)."
  fi
}

ACTION="${1:-}"; shift 2>/dev/null || true
case "$ACTION" in
  start)  cmd_start "$@";;
  score|finish)  cmd_score "$@";;
  report) cmd_report "$@";;
  list)   cmd_list "$@";;
  status) cmd_status "$@";;
  *)
    cat <<EOF
bench.sh — reproducible Nest benchmark harness

  bash benchmark/bench.sh start  <box> --ip <ip> --model <name> [--hostname <h>] [--difficulty <d>] [--os <o>]
  bash benchmark/bench.sh finish <box> [--cost USD] [--requests N] [--rate \$/1M] [--tokens-billed N]
                                       [--context-in N] [--context-out N] [--notes "..."]
  bash benchmark/bench.sh score  [<box> | --slug <slug>]      # same as finish (alias)
  bash benchmark/bench.sh report [--md | --csv]
  bash benchmark/bench.sh list
  bash benchmark/bench.sh status

Typical run:
  bash benchmark/bench.sh start blackfield --ip 10.10.10.192 --model "qwen2.5-72b" --hostname blackfield.htb
  # ... drive the loop until stop-gate passes ...
  # read cost + request count from the provider dashboard (ollama.com/settings), then:
  bash benchmark/bench.sh finish blackfield --cost 4.20 --requests 129 --rate 1.40 --notes "AS-REP -> SeBackup -> NTDS"
  bash benchmark/bench.sh report --md > benchmark/RESULTS.md   # matrix
  # per-run human log accumulates in benchmark/RESULTS-LOG.md
EOF
    exit 2;;
esac
