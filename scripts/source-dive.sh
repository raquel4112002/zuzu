#!/bin/bash
# source-dive.sh — Source-code reconnaissance for open-source web apps.
#
# When a target runs an identifiable open-source app (Flowise, Jenkins,
# WordPress plugin, custom Express app, etc.), this script clones or
# downloads the source and grep-mines for things that bypass auth or
# leak attack surface that the running app's docs won't tell you about.
#
# This is the fix for the silentium.htb (Flowise 3.0.5) failure mode:
# the model declared "needs auth" and gave up because it never read the
# actual source to find unauthenticated routes.
#
# Usage:
#   source-dive.sh <github-repo-or-url> [version-tag] [output-dir]
#   source-dive.sh FlowiseAI/Flowise v3.0.5
#   source-dive.sh https://github.com/jenkinsci/jenkins
#   source-dive.sh /path/to/already-cloned-repo  (skips clone)
#
# Output: a markdown report at <output-dir>/source-dive.md

set -uo pipefail

REPO="${1:-}"
TAG="${2:-}"
OUT="${3:-/tmp/source-dive-$$}"

if [[ -z "$REPO" ]]; then
  cat <<EOF
source-dive.sh — grep open-source code for auth bypasses & unauth surface

Usage:
  source-dive.sh <github-repo-or-path> [version-tag] [output-dir]

Examples:
  source-dive.sh FlowiseAI/Flowise v3.0.5
  source-dive.sh https://github.com/jenkinsci/jenkins
  source-dive.sh /tmp/already-cloned

Looks for:
  - Routes/endpoints that skip auth middleware
  - Hard-coded creds, tokens, default secrets
  - Debug/dev/admin endpoints not documented
  - Recent CVE patches (clue to current CVEs)
  - Insecure file upload, deserialization, eval, exec patterns
  - .env.example or config defaults
EOF
  exit 2
fi

mkdir -p "$OUT"
SRC_DIR=""

# Resolve REPO -> SRC_DIR
if [[ -d "$REPO" ]]; then
  SRC_DIR="$REPO"
  echo "[*] Using local repo: $SRC_DIR" >&2
else
  # Normalize to https URL
  if [[ "$REPO" =~ ^https?:// ]]; then
    URL="$REPO"
  elif [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    URL="https://github.com/$REPO"
  else
    URL="https://github.com/$REPO"
  fi
  CLONE_DIR="$OUT/repo"
  rm -rf "$CLONE_DIR"
  echo "[*] Cloning $URL (depth=1)..." >&2
  if [[ -n "$TAG" ]]; then
    git clone --depth=1 --branch "$TAG" "$URL" "$CLONE_DIR" 2>&1 | tail -3 >&2 || \
      git clone --depth=1 "$URL" "$CLONE_DIR" 2>&1 | tail -3 >&2
  else
    git clone --depth=1 "$URL" "$CLONE_DIR" 2>&1 | tail -3 >&2
  fi
  if [[ ! -d "$CLONE_DIR" ]]; then
    echo "[!] Clone failed." >&2
    exit 1
  fi
  SRC_DIR="$CLONE_DIR"
fi

REPORT="$OUT/source-dive.md"
{
  echo "# Source Dive Report"
  echo ""
  echo "- **Repo:** $REPO"
  echo "- **Tag:** ${TAG:-(default branch)}"
  echo "- **Local:** $SRC_DIR"
  echo "- **Date:** $(date -Iseconds)"
  echo ""
  echo "---"
  echo ""
} > "$REPORT"

# Helper: grep with context, cap to first 40 hits
grepc() {
  local label="$1" pattern="$2"
  shift 2
  local exts=("$@")
  echo "" >> "$REPORT"
  echo "## $label" >> "$REPORT"
  echo '```' >> "$REPORT"
  local include_args=()
  for e in "${exts[@]}"; do include_args+=(--include="*.${e}"); done
  grep -RInE "${include_args[@]}" \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
    --exclude-dir=build --exclude-dir=test --exclude-dir=tests \
    --exclude-dir=__tests__ --exclude-dir=spec --exclude-dir=docs \
    "$pattern" "$SRC_DIR" 2>/dev/null | head -40 >> "$REPORT" || echo "(no matches)" >> "$REPORT"
  echo '```' >> "$REPORT"
}

CODE_EXTS=(js ts jsx tsx py rb php java go cs lua kt scala)

# ---- A. Routes/endpoints that look unauthenticated ----------------
grepc "Unauth-looking routes (whitelisted/skipAuth/public)" \
  "(skipAuth|noAuth|requireAuth\s*[:=]\s*false|isPublic\s*[:=]\s*true|public\s*:\s*true|allow_anonymous|whitelist|@PermitAll|AnonymousAllowed|publicEndpoints|unauthenticatedPaths)" \
  "${CODE_EXTS[@]}"

# ---- B. Route handlers (Express, Fastify, Flask, FastAPI, Spring) -
grepc "All HTTP route definitions" \
  "(\\.(get|post|put|delete|patch)\\s*\\(\\s*['\"]/|@(Get|Post|Put|Delete|Patch|RequestMapping|GetMapping|PostMapping)|@app\\.(route|get|post|put|delete)|router\\.(get|post|put|delete|patch)\\()" \
  "${CODE_EXTS[@]}"

# ---- C. Auth middleware that may have bypasses --------------------
grepc "Auth middleware & bypass headers" \
  "(x-request-from|x-forwarded-for|x-real-ip|trust\\s*proxy|bypassAuth|checkAuth|verifyToken|requireAuth|authMiddleware|authenticateRequest|jwt\\.verify|isAuthenticated)" \
  "${CODE_EXTS[@]}"

# ---- D. Hardcoded creds & default secrets -------------------------
grepc "Hard-coded creds / default secrets" \
  "(password\\s*[:=]\\s*['\"][^'\"]{3,}|secret\\s*[:=]\\s*['\"][^'\"]{3,}|api[_-]?key\\s*[:=]\\s*['\"][^'\"]{3,}|token\\s*[:=]\\s*['\"][^'\"]{3,}|admin[:=]['\"]admin)" \
  "${CODE_EXTS[@]}"

# ---- E. Default config files -------------------------------------
echo "" >> "$REPORT"
echo "## Default config files (.env.example, config/default.*)" >> "$REPORT"
echo '```' >> "$REPORT"
find "$SRC_DIR" \( -name ".env*" -o -name "default.json" -o -name "default.yml" \
                 -o -name "default.yaml" -o -name "config.example.*" \
                 -o -name "secrets.example.*" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -20 >> "$REPORT"
echo '```' >> "$REPORT"

# ---- F. Dangerous sinks (eval / exec / spawn / unserialize) ------
grepc "Dangerous sinks (eval/exec/spawn/unserialize)" \
  "(\\beval\\s*\\(|\\bexec\\s*\\(|\\bspawn\\s*\\(|child_process|Runtime\\.getRuntime|unserialize\\s*\\(|pickle\\.loads|yaml\\.load[^_]|new\\s+Function\\()" \
  "${CODE_EXTS[@]}"

# ---- G. File upload & path handling -------------------------------
grepc "File upload / path handling" \
  "(multer|formidable|busboy|upload\\s*\\(|saveAs|path\\.join.*req\\.|req\\.params.*readFile|sendFile\\s*\\(|res\\.download)" \
  "${CODE_EXTS[@]}"

# ---- H. SQL/NoSQL string interpolation ----------------------------
grepc "Possible SQL/NoSQL injection sinks" \
  "(query\\s*\\(\\s*['\"\`].*\\$\\{|\\.raw\\s*\\(|find\\(\\s*\\{[^}]*req\\.|where\\(.*\\\$\\{)" \
  "${CODE_EXTS[@]}"

# ---- I. Recent security-related commits/patches ------------------
echo "" >> "$REPORT"
echo "## Recent security-related commits (last 50)" >> "$REPORT"
echo '```' >> "$REPORT"
( cd "$SRC_DIR" && git log --oneline --all -n 50 2>/dev/null \
  | grep -iE "(cve|security|auth|bypass|sanitize|escape|inject|fix.*vuln|patch.*sec)" ) >> "$REPORT" 2>/dev/null || \
  echo "(no security-related commits found in shallow clone)" >> "$REPORT"
echo '```' >> "$REPORT"

# ---- J. Routes file inventory (helps spot custom endpoints) ------
echo "" >> "$REPORT"
echo "## Files that define routes" >> "$REPORT"
echo '```' >> "$REPORT"
grep -rIlE --include="*.js" --include="*.ts" --include="*.py" --include="*.rb" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  --exclude-dir=test --exclude-dir=tests \
  -E "(router\\.(get|post|put|delete|patch)|app\\.(get|post|put|delete|patch)|@(Get|Post|Put|Delete|Patch)Mapping|@app\\.route)" \
  "$SRC_DIR" 2>/dev/null | head -20 >> "$REPORT"
echo '```' >> "$REPORT"

# ---- K. README & SECURITY.md hints --------------------------------
echo "" >> "$REPORT"
echo "## README / SECURITY excerpts" >> "$REPORT"
echo '```' >> "$REPORT"
for f in README.md README SECURITY.md SECURITY docs/security.md; do
  if [[ -f "$SRC_DIR/$f" ]]; then
    echo "--- $f ---" >> "$REPORT"
    head -80 "$SRC_DIR/$f" >> "$REPORT"
  fi
done
echo '```' >> "$REPORT"

# ---- Summary -----------------------------------------------------
{
  echo ""
  echo "---"
  echo ""
  echo "## How to use this report"
  echo ""
  echo "1. **Look at section A first.** Anything that toggles auth off is a candidate for an unauth attack vector."
  echo "2. **Cross-check section B (all routes) against what you've already enumerated on the live target.** Routes here that you didn't see when probing the target are *interesting* — they might be hidden behind something."
  echo "3. **Section C (auth middleware)** — read the actual implementation. Many auth checks fail open on missing headers, malformed tokens, or specific values like \`x-request-from: 127.0.0.1\`."
  echo "4. **Section I (recent security commits)** tells you what bugs are KNOWN. The bug you want to exploit is often one commit *before* the fix."
  echo "5. **Section J (route files)** — if there are only 2-3 files, read them all. If there are many, prioritize ones with names like 'public', 'api', 'webhook', 'callback'."
  echo ""
  echo "If you read sections A and C and find nothing obviously unauth, the target probably wants you to **find a leaked credential elsewhere** (e.g., in the team page, a public S3 bucket, GitHub leak), not bypass auth."
} >> "$REPORT"

echo ""
echo "✅ Source dive complete: $REPORT" >&2
echo ""
echo "Quick view:" >&2
wc -l "$REPORT" >&2
echo ""
echo "Open with: less $REPORT" >&2

echo "$REPORT"
