#!/usr/bin/env bash
# hypotheses.sh — First-class hypothesis bank for the current engagement.
#
# A hypothesis is the unit of reasoning: a specific, falsifiable claim
# with a single command that decides it. The bank is per-target, lives
# at reports/<target>/hypotheses.json, and survives session turns.
#
# Usage:
#   bash scripts/hypotheses.sh add "<H>" --falsifier "<cmd>" \
#        [--phase recon|enum|exploit|privesc|lateral|persist] \
#        [--cost LOW|MED|HIGH] [--impact LOW|MED|HIGH] \
#        [--source assumption|recon|cve|catalog|chain|guess]
#   bash scripts/hypotheses.sh list [--rank] [--phase X] [--status open|tested|...]
#   bash scripts/hypotheses.sh show <id>
#   bash scripts/hypotheses.sh test <id>     # runs the falsifier (timeboxed 60s by default)
#   bash scripts/hypotheses.sh result <id> confirmed|falsified|inconclusive "<note>"
#   bash scripts/hypotheses.sh chain <id> "<new hypothesis at next stage>"
#   bash scripts/hypotheses.sh stats
#
# Storage: reports/<target>/hypotheses.json
# Active target is whichever is in state/orchestrator.json.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$WS/state/orchestrator.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ No active engagement. Run: bash scripts/pentest.sh <target>"
  exit 1
fi

TARGET=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['target'])" 2>/dev/null || echo "")
if [[ -z "$TARGET" ]]; then
  echo "❌ Could not read target from $STATE_FILE"
  exit 1
fi
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
BANK="$WS/reports/$SLUG/hypotheses.json"
mkdir -p "$(dirname "$BANK")"

# Ensure file exists with a valid empty bank
if [[ ! -f "$BANK" ]]; then
  echo '{"target":"'"$TARGET"'","items":[]}' > "$BANK"
fi

ACTION="${1:-list}"
shift 2>/dev/null || true

py() { python3 "$@"; }

# Common header for the python helpers
PYHEADER='
import json, sys, subprocess, time, os, shlex, re
BANK = sys.argv[1]
def load():
    return json.load(open(BANK))
def save(d):
    with open(BANK,"w") as f:
        json.dump(d, f, indent=2)
def next_id(d):
    used = {it["id"] for it in d["items"]}
    n = 1
    while f"H{n}" in used: n += 1
    return f"H{n}"
def score(it):
    cost_w = {"LOW":1,"MED":3,"HIGH":9}.get(it.get("cost","MED"),3)
    imp_w  = {"LOW":1,"MED":3,"HIGH":9}.get(it.get("impact","MED"),3)
    return imp_w / cost_w
'

case "$ACTION" in

  add)
    H="${1:-}"
    shift 2>/dev/null || true
    if [[ -z "$H" ]]; then
      echo 'Usage: hypotheses.sh add "<H>" --falsifier "<cmd>" [--cost LOW|MED|HIGH] [--impact LOW|MED|HIGH] [--phase X] [--source X]'
      exit 2
    fi
    FALSIFIER=""
    PHASE=""
    COST="MED"
    IMPACT="MED"
    SOURCE="guess"
    WAIVE_CHAIN="no"
    WAIVE_PIVOT="no"
    WAIVE_REASON=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --falsifier)    FALSIFIER="$2"; shift 2;;
        --phase)        PHASE="$2"; shift 2;;
        --cost)         COST="$2"; shift 2;;
        --impact)       IMPACT="$2"; shift 2;;
        --source)       SOURCE="$2"; shift 2;;
        --waive-chain)  WAIVE_CHAIN="yes"; WAIVE_REASON="$2"; shift 2;;
        --waive-pivot)  WAIVE_PIVOT="yes"; WAIVE_REASON="$2"; shift 2;;
        *) shift;;
      esac
    done
    py - "$BANK" "$H" "$FALSIFIER" "$PHASE" "$COST" "$IMPACT" "$SOURCE" "$WAIVE_CHAIN" "$WAIVE_PIVOT" "$WAIVE_REASON" "$WS" <<PY
$PYHEADER
H, FALS, PHASE, COST, IMPACT, SRC = sys.argv[2:8]
WAIVE_CHAIN, WAIVE_PIVOT, WAIVE_REASON, WS = sys.argv[8:12]
d = load()

# ===== HARD ENFORCEMENT: CHAIN RULE =====
# Refuse to add a new hypothesis if there's a confirmed one without
# a chain link — the chain must be created first. Prevents drift.
unchained = [i for i in d["items"]
             if i.get("result") == "confirmed" and not i.get("chains_to")]
if unchained and WAIVE_CHAIN != "yes":
    print("❌ CHAIN RULE BLOCK — cannot add new H while a confirmed H is unchained.")
    print("")
    print("   The following confirmed hypotheses have NO next-stage chain:")
    for it in unchained[:5]:
        print(f"     {it['id']}  ({it.get('phase','?')}): {it['h'][:80]}")
    print("")
    print("   Fix one of:")
    print("     1) Chain it (preferred):")
    print(f"          bash scripts/hypotheses.sh chain {unchained[0]['id']} \"<next-stage H>\"")
    print("     2) Waive (rare — e.g. dead-end finding, no further phase applies):")
    print(f"          bash scripts/hypotheses.sh add ... --waive-chain \"<reason>\"")
    sys.exit(1)

# ===== HARD ENFORCEMENT: PIVOT RULE =====
# If 3+ hypotheses were falsified in the last hour, refuse to add new
# hypotheses until target-model.md has been touched (mtime > newest
# falsification). Forces the LLM to rewrite the model first.
import os
now = time.time()
recent_fals = [i for i in d["items"]
               if i.get("result") == "falsified"
               and i.get("tested_at") and now - i["tested_at"] < 3600]
if len(recent_fals) >= 3 and WAIVE_PIVOT != "yes":
    target = d.get("target","")
    slug = ''.join(c for c in target.replace('/','-')
                   if c.isalnum() or c in '._-')
    tm_path = os.path.join(WS, "reports", slug, "target-model.md")
    newest_fals = max(i.get("tested_at",0) for i in recent_fals)
    tm_mtime = os.path.getmtime(tm_path) if os.path.exists(tm_path) else 0
    if tm_mtime <= newest_fals:
        print("❌ PIVOT RULE BLOCK — 3 hypotheses falsified in last hour")
        print("   AND target-model.md has not been updated since.")
        print("")
        print("   Your target model is probably wrong. Rewrite it before")
        print("   adding more hypotheses, otherwise you're guessing in")
        print("   the wrong space.")
        print("")
        print(f"   Edit: {tm_path}")
        print("")
        print("   To override (rare — e.g. probing a totally new vector):")
        print("     bash scripts/hypotheses.sh add ... --waive-pivot \"<reason>\"")
        sys.exit(1)

hid = next_id(d)
item = {
    "id": hid, "h": H, "falsifier": FALS, "phase": PHASE or "?",
    "cost": COST, "impact": IMPACT, "source": SRC,
    "status": "open", "result": None, "note": "",
    "created": int(time.time()), "tested_at": None, "chains_to": []
}
if WAIVE_CHAIN == "yes" or WAIVE_PIVOT == "yes":
    item["waiver"] = {
        "chain": WAIVE_CHAIN == "yes",
        "pivot": WAIVE_PIVOT == "yes",
        "reason": WAIVE_REASON,
        "at": int(time.time())
    }
d["items"].append(item)
save(d)
print(f"✅ {hid} added.")
print(f"   {H}")
print(f"   falsifier: {FALS or '(none — add one before testing)'}")
print(f"   cost={COST} impact={IMPACT} source={SRC} phase={PHASE or '?'}")
if WAIVE_CHAIN == "yes":
    print(f"   ⚠  chain rule WAIVED: {WAIVE_REASON}")
if WAIVE_PIVOT == "yes":
    print(f"   ⚠  pivot rule WAIVED: {WAIVE_REASON}")
PY
    ;;

  list)
    RANK="no"; PHASE_F=""; STATUS_F=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --rank)   RANK="yes"; shift;;
        --phase)  PHASE_F="$2"; shift 2;;
        --status) STATUS_F="$2"; shift 2;;
        *) shift;;
      esac
    done
    py - "$BANK" "$RANK" "$PHASE_F" "$STATUS_F" <<PY
$PYHEADER
RANK, PHASE_F, STATUS_F = sys.argv[2], sys.argv[3], sys.argv[4]
d = load()
items = d["items"]
if PHASE_F:  items = [i for i in items if i.get("phase") == PHASE_F]
if STATUS_F: items = [i for i in items if i.get("status") == STATUS_F]
if RANK == "yes":
    items = [i for i in items if i.get("status") == "open"]
    items.sort(key=lambda i: -score(i))
if not items:
    print("_No hypotheses match._"); sys.exit(0)
print(f"\n# Hypothesis bank — {d['target']}\n")
print("| ID | Phase | Status | Cost | Impact | Score | Hypothesis |")
print("|---|---|---|---|---|---|---|")
for it in items:
    s = "{:.1f}".format(score(it))
    h = it["h"][:80] + ("…" if len(it["h"])>80 else "")
    print(f"| {it['id']} | {it.get('phase','?')} | {it.get('status','?')} | {it.get('cost','?')} | {it.get('impact','?')} | {s} | {h} |")
print()
PY
    ;;

  show)
    HID="${1:-}"
    if [[ -z "$HID" ]]; then echo "Usage: hypotheses.sh show <id>"; exit 2; fi
    py - "$BANK" "$HID" <<PY
$PYHEADER
HID = sys.argv[2]
d = load()
it = next((i for i in d["items"] if i["id"]==HID), None)
if not it: print(f"❌ {HID} not found."); sys.exit(1)
print(f"\n## {it['id']}  [{it.get('status','?')}]\n")
print(f"**Hypothesis:** {it['h']}\n")
print(f"**Falsifier:**  \`{it.get('falsifier','(none)')}\`")
print(f"**Phase:** {it.get('phase','?')}   **Cost:** {it.get('cost','?')}   **Impact:** {it.get('impact','?')}")
print(f"**Source:** {it.get('source','?')}   **Score:** {score(it):.2f}")
if it.get('result'):
    print(f"\n**Result:** {it['result']}")
if it.get('note'):
    print(f"**Note:** {it['note']}")
if it.get('chains_to'):
    print(f"\n**Chains to:** {', '.join(it['chains_to'])}")
PY
    ;;

  test)
    HID="${1:-}"
    BUDGET="${2:-60}"
    if [[ -z "$HID" ]]; then echo "Usage: hypotheses.sh test <id> [budget-secs]"; exit 2; fi
    FALS=$(python3 -c "import json; b=json.load(open('$BANK')); it=next((i for i in b['items'] if i['id']=='$HID'),None); print(it.get('falsifier','') if it else '')")
    if [[ -z "$FALS" ]]; then
      echo "❌ $HID has no falsifier. Add one with:"
      echo "   hypotheses.sh edit $HID --falsifier '<cmd>'"
      exit 1
    fi
    echo "─── testing $HID (budget ${BUDGET}s) ───"
    echo "\$ $FALS"
    bash "$WS/scripts/timebox.sh" "$BUDGET" bash -c "$FALS"
    EC=$?
    echo "─── exit=$EC ───"
    echo ""
    echo "Now record the verdict:"
    echo "  bash scripts/hypotheses.sh result $HID confirmed|falsified|inconclusive \"<one-line note>\""
    ;;

  result)
    HID="${1:-}"
    VERDICT="${2:-}"
    NOTE="${3:-}"
    shift 3 2>/dev/null || true
    EVIDENCE=""
    WAIVE_EVIDENCE="no"
    WAIVE_EVIDENCE_REASON=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --evidence)         EVIDENCE="$2"; shift 2;;
        --waive-evidence)   WAIVE_EVIDENCE="yes"; WAIVE_EVIDENCE_REASON="$2"; shift 2;;
        *) shift;;
      esac
    done
    if [[ -z "$HID" || -z "$VERDICT" ]]; then
      echo "Usage: hypotheses.sh result <id> confirmed|falsified|inconclusive \"<note>\" [--evidence <path>]"
      exit 2
    fi
    py - "$BANK" "$HID" "$VERDICT" "$NOTE" "$EVIDENCE" "$WAIVE_EVIDENCE" "$WAIVE_EVIDENCE_REASON" "$WS" <<PY
$PYHEADER
HID, V, NOTE, EVIDENCE, WAIVE_EV, WAIVE_REASON, WS_DIR = sys.argv[2:9]
d = load()
it = next((i for i in d["items"] if i["id"]==HID), None)
if not it: print(f"❌ {HID} not found."); sys.exit(1)
if V not in ("confirmed","falsified","inconclusive"):
    print("❌ verdict must be: confirmed | falsified | inconclusive"); sys.exit(2)

# ===== HARD ENFORCEMENT: EVIDENCE RULE for confirmed =====
# A 'confirmed' verdict must point at a real artefact under the
# engagement folder (loot, creds, exploits, web, nmap, etc.).
# An empty loot dir plus confirmed rows is the R2 violation that bit
# us on facts.htb. Falsified / inconclusive don't require evidence
# (the negative result IS the evidence).
if V == "confirmed" and WAIVE_EV != "yes":
    if not EVIDENCE:
        print("❌ EVIDENCE RULE BLOCK — 'confirmed' requires --evidence <path>.")
        print("")
        print("   A confirmed hypothesis without an artefact on disk is just")
        print("   narration. Save the proof first:")
        target = d.get("target","")
        slug = ''.join(c for c in target.replace('/','-')
                       if c.isalnum() or c in '._-')
        print(f"     reports/{slug}/loot/<file>     # flags, dumps, screenshots")
        print(f"     reports/{slug}/creds/<file>    # credentials, hashes, keys")
        print(f"     reports/{slug}/exploits/<file> # PoC payloads, transcripts")
        print("")
        print("   Then re-run with: --evidence <path>")
        print("   Genuine no-artefact case (rare): --waive-evidence \"<reason>\"")
        sys.exit(1)
    # Resolve --evidence path: accept absolute, or relative to WS, or to engagement folder.
    target = d.get("target","")
    slug = ''.join(c for c in target.replace('/','-')
                   if c.isalnum() or c in '._-')
    eng_dir = os.path.join(WS_DIR, "reports", slug)
    candidates = [
        EVIDENCE,
        os.path.join(eng_dir, EVIDENCE),
        os.path.join(WS_DIR, EVIDENCE),
    ]
    found = next((p for p in candidates
                  if os.path.exists(p) and os.path.getsize(p) > 0), None)
    if not found:
        print(f"❌ EVIDENCE RULE BLOCK — '{EVIDENCE}' does not exist or is empty.")
        print("")
        print("   Looked in:")
        for p in candidates:
            print(f"     {p}")
        print("")
        print("   Save the artefact, then retry. To override (rare):")
        print("     --waive-evidence \"<reason>\"")
        sys.exit(1)
    it["evidence"] = os.path.relpath(found, WS_DIR)

it["status"] = "tested"
it["result"] = V
it["note"] = NOTE
it["tested_at"] = int(time.time())
if WAIVE_EV == "yes":
    it["evidence_waiver"] = {"reason": WAIVE_REASON, "at": int(time.time())}
save(d)
print(f"✅ {HID} → {V}")
if V == "confirmed" and it.get("evidence"):
    print(f"   evidence: {it['evidence']}")
if V == "confirmed":
    print()
    print("⚠  CHAIN RULE: a confirmed hypothesis MUST generate a new")
    print("    hypothesis at the next kill-chain stage. Do it now:")
    print(f"      bash scripts/hypotheses.sh chain {HID} \"<new H at next stage>\"")
elif V == "falsified":
    falsified_recent = [i for i in d["items"] if i.get("result")=="falsified"]
    falsified_recent.sort(key=lambda i: i.get("tested_at",0), reverse=True)
    if len(falsified_recent) >= 3 and all(
        falsified_recent[k]["tested_at"] and falsified_recent[k]["tested_at"] > time.time()-3600
        for k in range(min(3,len(falsified_recent)))):
        print()
        print("🚨 PIVOT RULE: 3 hypotheses falsified in the last hour.")
        print("   Your TARGET MODEL is probably wrong. Reread surface.md")
        print("   and rewrite target-model.md before adding more hypotheses.")
    # ===== OOB HUMAN-GATE DETECTOR =====
    # If ≥3 of the most recent falsifications all reference the same
    # human-gate keyword in their hypothesis text or note, suggest R15.
    GATE_KEYWORDS = {
        "captcha":  ["captcha", "recaptcha", "hcaptcha"],
        "email":    ["email verif", "verify email", "confirmation email", "verification link"],
        "sms":      ["sms verif", "phone verif", "otp sms"],
        "mfa":      [" mfa", "2fa", "totp", "authenticator app"],
        "oauth":    ["oauth", "google login", "github login", "sso"],
        "kyc":      ["kyc", "id verification", "identity check"],
    }
    recent3 = falsified_recent[:5]
    for gate, kws in GATE_KEYWORDS.items():
        hits = [i for i in recent3
                if any(kw in (i.get("h","") + " " + i.get("note","")).lower()
                       for kw in kws)]
        if len(hits) >= 3:
            print()
            print(f"🚨 OOB HUMAN-GATE DETECTED ({gate.upper()})")
            print("   3+ recent falsifications all target the same human-only barrier.")
            print("   Per AGENTS.md R15, the gate is now a fact, not a hypothesis.")
            print("   Hand off to the human:")
            print("")
            tried_summary = "; ".join(
                (i.get("note") or i.get("h",""))[:80] for i in hits[:3]
            ).replace('"',"'")
            target = d.get("target","")
            BSL = chr(92)  # avoid backslash-at-end-of-fstring quirks
            print("     bash scripts/request-human.sh " + BSL)
            print(f"       --target {target} --gate {gate} " + BSL)
            print(f'       --tried "{tried_summary}" ' + BSL)
            print('       --need "<one line: what artefact you need from the human>" ' + BSL)
            print('       --resume-with "<one line: the next H you will fire on response>"')
            break
PY
    ;;

  chain)
    HID="${1:-}"
    NEW_H="${2:-}"
    if [[ -z "$HID" || -z "$NEW_H" ]]; then
      echo "Usage: hypotheses.sh chain <parent-id> \"<new H at next stage>\""
      exit 2
    fi
    py - "$BANK" "$HID" "$NEW_H" <<PY
$PYHEADER
HID, NEW_H = sys.argv[2], sys.argv[3]
d = load()
parent = next((i for i in d["items"] if i["id"]==HID), None)
if not parent: print(f"❌ {HID} not found."); sys.exit(1)
phases = ["recon","enum","exploit","privesc","lateral","persist"]
pp = parent.get("phase","?")
new_phase = phases[min(phases.index(pp)+1, len(phases)-1)] if pp in phases else "?"
hid = next_id(d)
d["items"].append({
    "id": hid, "h": NEW_H, "falsifier": "",
    "phase": new_phase, "cost":"MED", "impact":"MED",
    "source":"chain", "status":"open", "result":None, "note":"",
    "created": int(time.time()), "tested_at": None, "chains_to": []
})
parent.setdefault("chains_to", []).append(hid)
save(d)
print(f"✅ Chained {HID} → {hid} (phase={new_phase})")
print(f"   {NEW_H}")
print(f"   ⚠  Add a falsifier before testing: hypotheses.sh edit {hid} --falsifier '<cmd>'")
PY
    ;;

  edit)
    HID="${1:-}"
    shift 2>/dev/null || true
    if [[ -z "$HID" ]]; then echo "Usage: hypotheses.sh edit <id> --falsifier <cmd> | --cost X | --impact X | --phase X"; exit 2; fi
    FALS=""; COST=""; IMPACT=""; PHASE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --falsifier) FALS="$2"; shift 2;;
        --cost)      COST="$2"; shift 2;;
        --impact)    IMPACT="$2"; shift 2;;
        --phase)     PHASE="$2"; shift 2;;
        *) shift;;
      esac
    done
    py - "$BANK" "$HID" "$FALS" "$COST" "$IMPACT" "$PHASE" <<PY
$PYHEADER
HID, FALS, COST, IMPACT, PHASE = sys.argv[2:7]
d = load()
it = next((i for i in d["items"] if i["id"]==HID), None)
if not it: print(f"❌ {HID} not found."); sys.exit(1)
if FALS:   it["falsifier"] = FALS
if COST:   it["cost"] = COST
if IMPACT: it["impact"] = IMPACT
if PHASE:  it["phase"] = PHASE
save(d)
print(f"✅ {HID} updated.")
PY
    ;;

  stats)
    py - "$BANK" <<PY
$PYHEADER
d = load()
n = len(d["items"])
by_status = {}
by_phase = {}
for it in d["items"]:
    by_status[it.get("status","?")] = by_status.get(it.get("status","?"),0)+1
    by_phase[it.get("phase","?")] = by_phase.get(it.get("phase","?"),0)+1
confirmed = sum(1 for i in d["items"] if i.get("result")=="confirmed")
falsified = sum(1 for i in d["items"] if i.get("result")=="falsified")
chained = sum(1 for i in d["items"] if i.get("chains_to"))
print(f"\n# Hypothesis bank stats — {d['target']}\n")
print(f"Total: {n}")
print(f"  by status: {by_status}")
print(f"  by phase:  {by_phase}")
print(f"  confirmed: {confirmed}")
print(f"  falsified: {falsified}")
print(f"  chained:   {chained}")
print()
if n - by_status.get('tested',0) - by_status.get('discarded',0) < 5:
    print("⚠  Fewer than 5 OPEN hypotheses. THINK.md Layer 4 says you should")
    print("   always have ≥ 5 untested. Go re-read assumptions.md and add more.")
PY
    ;;

  *)
    cat <<EOF
hypotheses.sh — first-class hypothesis bank

Commands:
  add "<H>" --falsifier "<cmd>" [--phase X] [--cost LOW|MED|HIGH] [--impact LOW|MED|HIGH] [--source X]
  list [--rank] [--phase X] [--status open|tested]
  show <id>
  edit <id> --falsifier "<cmd>" | --cost X | --impact X | --phase X
  test <id> [budget-secs]                 # runs falsifier, timeboxed
  result <id> confirmed|falsified|inconclusive "<note>"
  chain <parent-id> "<new H at next stage>"
  stats

Active target: $TARGET
Bank file:     $BANK
EOF
    ;;
esac
