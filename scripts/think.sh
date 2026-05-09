#!/usr/bin/env bash
# think.sh — Force structured reasoning, not scripted next-actions.
#
# This is the alternative to orchestrator.sh think for novel targets.
# orchestrator.sh think gives canned suggestions from hard-coded patterns,
# which is great when those patterns apply. think.sh instead PROMPTS the
# LLM with the THINK.md framework: it shows what's known, what's missing,
# what hypotheses are open, and forces the LLM to do the reasoning.
#
# Usage:
#   bash scripts/think.sh                # full reasoning prompt
#   bash scripts/think.sh --brief        # short status only
#   bash scripts/think.sh --pivot        # forces a target-model rewrite
#
# Output is markdown / structured prose designed to be read by the LLM
# itself (i.e., this is a *prompt* the script generates, not a
# decision). The LLM then writes its reasoning into the appropriate
# files and acts.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$WS/state/orchestrator.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ No active engagement. Run: bash scripts/pentest.sh <target>"
  exit 1
fi

TARGET=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['target'])" 2>/dev/null)
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"
PHASE=$(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(s.get('phase','?')+'/'+s.get('sub_phase','?'))" 2>/dev/null)

MODE="${1:-full}"

# Helper: file existence + word-count for the reasoning artefacts
artefact_status() {
  local f="$1" label="$2"
  if [[ -s "$f" ]]; then
    local wc; wc=$(wc -w <"$f" | tr -d ' ')
    echo "  ✅ $label  ($wc words)"
  else
    echo "  ❌ $label  (missing or empty)"
  fi
}

cat <<EOF

═══════════════════════════════════════════════════════════════════
 🧠 THINK — reasoning prompt for $TARGET
═══════════════════════════════════════════════════════════════════
 Phase: $PHASE
 Folder: $DIR/

EOF

# 1) Reasoning artefact audit
echo "## 1. Reasoning artefacts (THINK.md says you should have these)"
echo ""
artefact_status "$DIR/surface.md"        "surface.md       (Layer 1 — what's there)"
artefact_status "$DIR/target-model.md"   "target-model.md  (Layer 2 — how it's wired)"
artefact_status "$DIR/assumptions.md"    "assumptions.md   (Layer 3 — what defender assumes)"
artefact_status "$DIR/hypotheses.json"   "hypotheses.json  (Layer 4 — bank, ranked)"
artefact_status "$DIR/external-refs.md"  "external-refs.md (live knowledge fetched)"
echo ""

# 2) Hypothesis bank summary
echo "## 2. Hypothesis bank"
echo ""
if [[ -f "$DIR/hypotheses.json" ]]; then
  python3 - "$DIR/hypotheses.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
items = d.get('items', [])
if not items:
    print("_Empty bank. Layer 4 demands ≥ 5 open hypotheses. Generate them now._")
    sys.exit(0)
opens = [i for i in items if i.get('status') == 'open']
tested = [i for i in items if i.get('status') == 'tested']
confirmed = [i for i in tested if i.get('result') == 'confirmed']
falsified = [i for i in tested if i.get('result') == 'falsified']
def score(i):
    cw = {"LOW":1,"MED":3,"HIGH":9}.get(i.get('cost','MED'),3)
    iw = {"LOW":1,"MED":3,"HIGH":9}.get(i.get('impact','MED'),3)
    return iw / cw
print(f"- {len(items)} total, {len(opens)} open, {len(confirmed)} confirmed, {len(falsified)} falsified")
print()
if opens:
    opens.sort(key=lambda i: -score(i))
    print("**Top 5 open by score (impact/cost):**")
    print()
    print("| ID | Phase | Cost | Impact | Score | Hypothesis |")
    print("|---|---|---|---|---|---|")
    for it in opens[:5]:
        h = it['h'][:90] + ('…' if len(it['h']) > 90 else '')
        print(f"| {it['id']} | {it.get('phase','?')} | {it.get('cost','?')} | {it.get('impact','?')} | {score(it):.1f} | {h} |")
if confirmed:
    print()
    print("**Confirmed (chain candidates):**")
    for it in confirmed[-5:]:
        chained = '→ ' + ','.join(it.get('chains_to',[])) if it.get('chains_to') else '⚠ NOT yet chained'
        print(f"  - {it['id']} ({it.get('phase','?')}): {it['h'][:80]}  {chained}")
PY
else
  echo "_No bank yet. Add hypotheses with:_"
  echo "  \`bash scripts/hypotheses.sh add \"<H>\" --falsifier \"<cmd>\" --cost LOW --impact HIGH\`"
fi
echo ""

# 3) The reasoning prompt itself — directives to the LLM
cat <<'EOF'
## 3. Your turn — answer these IN WRITING before any next command

Reasoning is not optional on novel targets. Write your answers into the
appropriate files (target-model.md, assumptions.md, etc.) and append the
key bullets to notes.md. Do not skip to running tools.

### A. Target model (Layer 2)
Look at surface.md. Then write/update target-model.md:
- Nodes: every component you see or can infer.
- Edges: who calls whom, with what trust label.
- Data flows: where input enters, gets reflected, gets executed.
- Identity model: who can authenticate, what each role can do.
- Known unknowns: list at least 3.

### B. Assumptions the defender is making (Layer 3)
For each component / edge / data flow, write the assumption that, if
WRONG, opens an attack. Examples:
- "Every API route checks the session." → if wrong: route enumeration.
- "JSON body is schema-validated." → if wrong: type confusion / extra fields.
- "Uploads can't execute as code." → if wrong: extension / parser tricks.

Aim for ≥ 8 assumptions. Use `knowledge-base/creativity-catalog.md` as
a checklist of assumption *classes* — apply each class to your model.

### C. Hypotheses (Layer 4)
For each promising assumption, write a hypothesis:

  bash scripts/hypotheses.sh add \
       "GET /api/v1/users with no session returns user list" \
       --falsifier "curl -s -o /dev/null -w '%{http_code}' http://$T/api/v1/users" \
       --cost LOW --impact HIGH --phase enum --source assumption

You should have ≥ 5 OPEN hypotheses at all times during enumeration and
exploitation phases.

### D. Live knowledge (when you don't recognise something)
Use the recon-* scripts. Don't stop because you don't know a stack:

  bash scripts/recon-cve.sh   "<product> <version>"
  bash scripts/recon-mitre.sh "<technique-or-keyword>"
  bash scripts/recon-poc.sh   "<CVE-ID>"
  bash scripts/recon-tech.sh  "<keyword>"

Append findings + URLs to external-refs.md. Each finding may seed new
hypotheses — add them.

### E. Test, cheapest first
Run the highest-score open hypothesis:

  bash scripts/hypotheses.sh test <ID>
  bash scripts/hypotheses.sh result <ID> confirmed|falsified|inconclusive "<note>"

After every CONFIRMED hypothesis, you MUST chain to the next stage:

  bash scripts/hypotheses.sh chain <ID> "<new H at next stage>"

After 3 falsified in an hour, your model is wrong — rewrite
target-model.md before adding more hypotheses.

### F. The five questions (THINK.md § 6)
Before any command, silently answer:
  1. What am I trying to learn / achieve?
  2. Which hypothesis does this test? (no answer = explore, then add it as H first)
  3. Cheapest way to get the same evidence?
  4. What do I do on each branch (confirm / falsify)?
  5. Is there a chain I'm missing from earlier confirmed hypotheses?

EOF

if [[ "$MODE" == "--pivot" ]]; then
  cat <<EOF
═══ PIVOT MODE ══════════════════════════════════════════════════════
 You triggered --pivot. That means we suspect the target model is wrong.
 Tasks:
   1. Re-read surface.md TOP to BOTTOM. What did we miss the first time?
   2. Rewrite target-model.md from scratch (mv old to target-model.v1.md).
   3. Re-derive assumptions.md from the new model.
   4. Discard hypotheses whose premises are gone:
        bash scripts/hypotheses.sh edit <id> --cost HIGH (deprioritise)
   5. Add fresh hypotheses against the new model.
═══════════════════════════════════════════════════════════════════
EOF
fi

if [[ "$MODE" == "--brief" ]]; then
  exit 0
fi

# 4) Sanity nudges
cat <<EOF

## 4. Common drift to self-correct

- Running variants of the same command → STOP, write hypotheses instead.
- Saying "needs auth" → source-dive.sh + creativity catalog § C first.
- "Doesn't match a known archetype" → THIS IS the time to use THINK.md, not give up.
- No notes since last command → you're acting without thinking. Stop.

EOF
