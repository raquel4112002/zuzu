#!/usr/bin/env bash
# request-human.sh — Hand off to Raquel when an Out-of-Band human gate
# blocks progress (CAPTCHA, email/SMS verification, MFA, KYC, OAuth on
# an external real IdP). Emits a structured handoff message AND records
# the artefact at reports/<target>/HUMAN-HELP-REQUESTED.md so stop-gate.sh
# recognises the engagement as `awaiting_human` (a pause, not "done").
#
# See AGENTS.md R15 + PILOT.md stop condition #4. The R15 contract is:
# you must have falsified ≥ 3 independent technical bypasses BEFORE
# calling this script. CTF CAPTCHAs are frequently solvable; bailing
# without trying is a quitter's shortcut and stop-gate.sh will reject it.
#
# Usage:
#   bash scripts/request-human.sh \
#     --target  10.129.51.119 \
#     --gate    captcha|email|sms|mfa|oauth|kyc|payment|other \
#     --tried   "OCR (tesseract+preprocess); audio variant n/a; token replay rotates per request; source-dive simple_captcha2 image-only; alt /api/login 404"
#     --need    "Valid account on http://facts.htb/admin/login. Register at /register (or whichever route) and paste creds."
#     --resume-with "Fire H6 (CVE-2025-2304 mass assignment) at /admin/users/<id>/updated_ajax with password[role]=admin, then read CVE-2024-46987 to grab MinIO config."
#
# --tried MUST contain ≥ 3 attempts separated by ';'. Anything fewer
# fails the script (you haven't earned the handoff yet).
#
# Exit codes:
#   0 — handoff recorded; engagement is now `awaiting_human`.
#   1 — usage error or R15 contract not satisfied.
#   2 — target folder doesn't exist.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"

TARGET=""
GATE=""
TRIED=""
NEED=""
RESUME=""
FORCE="no"

usage() {
  cat <<EOF
Usage: bash scripts/request-human.sh \\
  --target <target> --gate <kind> \\
  --tried "<bypass1>; <bypass2>; <bypass3>[; ...]" \\
  --need "<one-line description of what you need from Raquel>" \\
  --resume-with "<one-line description of what you'll do once she responds>"

Gate kinds: captcha | email | sms | mfa | oauth | kyc | payment | other

R15 contract: --tried must list ≥ 3 *falsified* technical bypasses.
Use --force only if you genuinely cannot enumerate 3 (e.g. legally
forbidden to attack the gate); the artefact will record the override.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)        TARGET="${2:-}"; shift 2 ;;
    --gate)          GATE="${2:-}"; shift 2 ;;
    --tried)         TRIED="${2:-}"; shift 2 ;;
    --need)          NEED="${2:-}"; shift 2 ;;
    --resume-with)   RESUME="${2:-}"; shift 2 ;;
    --force)         FORCE="yes"; shift ;;
    -h|--help)       usage ;;
    *)               echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -z "$TARGET" || -z "$GATE" || -z "$TRIED" || -z "$NEED" || -z "$RESUME" ]] && usage

VALID_GATES="captcha email sms mfa oauth kyc payment other"
if ! grep -qw "$GATE" <<<"$VALID_GATES"; then
  echo "❌ Invalid --gate '$GATE'. Valid: $VALID_GATES"
  exit 1
fi

SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"
if [[ ! -d "$DIR" ]]; then
  echo "❌ No engagement folder for '$TARGET'. Run: bash scripts/pentest.sh $TARGET"
  exit 2
fi

# Split --tried on ';' and count non-empty entries.
IFS=';' read -ra TRIED_ARR <<<"$TRIED"
TRIED_CLEAN=()
for t in "${TRIED_ARR[@]}"; do
  trimmed="$(echo "$t" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -n "$trimmed" ]] && TRIED_CLEAN+=("$trimmed")
done

if (( ${#TRIED_CLEAN[@]} < 3 )) && [[ "$FORCE" != "yes" ]]; then
  cat <<EOF
❌ R15 contract not satisfied: --tried lists ${#TRIED_CLEAN[@]} bypasses, need ≥ 3.

A CAPTCHA / verification wall is NOT an automatic handoff trigger. You
must falsify ≥ 3 independent technical bypasses with evidence first.

Suggested checklist (pick the ones that fit your gate):

  CAPTCHA:
    - OCR with preprocessing (grayscale, threshold, deskew) → tesseract
    - Audio variant or accessibility endpoint
    - Token replay (does the same token solve again?)
    - Weak generator (predictable seed / reused image hash / MD5 collision)
    - Source-dive the gem/library (recon-tech.sh + source-dive.sh)
    - Alternate endpoint that skips the CAPTCHA (mobile API, /v2/, /admin)
    - Parameter pollution / case-fuzzing the CAPTCHA field

  Email / SMS verification:
    - Catch-all on a domain you control
    - Header injection in the verify request
    - Predictable token (timestamp / sequential / weak random)
    - Race condition on the verify endpoint
    - Alternate signup flow without verification

  OAuth (external):
    - Open-redirect → code theft
    - Local-account fallback login
    - Dev / staging copy without OAuth
    - Misconfigured redirect_uri / state

After 3 falsified attempts (recorded in hypotheses.sh as 'falsified'),
re-run this script. To override (rare; e.g. legally out of scope),
add --force; the artefact will note the override.
EOF
  exit 1
fi

NOW_ISO="$(date -Iseconds)"
NOW_EPOCH="$(date +%s)"
HHR="$DIR/HUMAN-HELP-REQUESTED.md"

{
  echo "# Human help requested — $TARGET"
  echo ""
  echo "Status: awaiting_human"
  echo "Gate: $GATE"
  echo "Requested: $NOW_ISO"
  if [[ "$FORCE" == "yes" ]] && (( ${#TRIED_CLEAN[@]} < 3 )); then
    echo "R15 override: --force (only ${#TRIED_CLEAN[@]} bypasses tried)"
  fi
  echo ""
  echo "## Need (what Raquel must provide)"
  echo ""
  echo "$NEED"
  echo ""
  echo "## Tried (falsified)"
  echo ""
  for t in "${TRIED_CLEAN[@]}"; do
    echo "- $t"
  done
  echo ""
  echo "## Resume plan (what runs the moment she responds)"
  echo ""
  echo "$RESUME"
  echo ""
  echo "## How Raquel responds"
  echo ""
  echo "Paste the artefact (creds / token / file) into chat, OR drop it"
  echo "at \`$DIR/creds/human-handoff.txt\` and reply 'go'. Then this LLM"
  echo "(or its successor) reads HUMAN-HELP-REQUESTED.md, flips Status to"
  echo "\`resumed\`, and continues with the resume plan above."
} > "$HHR"

# Update orchestrator state if it exists.
ORCH="$WS/state/orchestrator.json"
if [[ -f "$ORCH" ]]; then
  python3 - "$ORCH" "$SLUG" "$GATE" "$NOW_EPOCH" <<'PY' 2>/dev/null || true
import json, sys
path, slug, gate, ts = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
try:
    d = json.load(open(path))
except Exception:
    d = {}
d.setdefault("targets", {}).setdefault(slug, {})
d["targets"][slug]["status"] = "awaiting_human"
d["targets"][slug]["awaiting_human"] = {"gate": gate, "since": ts}
json.dump(d, open(path, "w"), indent=2)
PY
fi

# Emit the chat-ready handoff message.
cat <<EOF

═══════════════════════════════════════════════════════════════════════
🛑 HUMAN HELP REQUESTED — $TARGET
═══════════════════════════════════════════════════════════════════════

Gate:   $GATE  (Out-of-Band human-only barrier)
Tried:  ${#TRIED_CLEAN[@]} technical bypasses — all falsified

What I need from you:
  → $NEED

What I'll do the moment you respond:
  → $RESUME

Falsified bypasses (full list in $HHR):
EOF
for t in "${TRIED_CLEAN[@]}"; do
  echo "  • $t"
done
cat <<EOF

Engagement is now in 'awaiting_human' state. stop-gate.sh treats this
as a legitimate pause. Reply with the artefact or 'go' to resume.
═══════════════════════════════════════════════════════════════════════
EOF

exit 0
