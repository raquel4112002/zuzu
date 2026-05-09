#!/usr/bin/env bash
# recon-poc.sh — Find and CACHE a PoC for a CVE. Never auto-runs.
#
# Pulls candidates from:
#   1. Local searchsploit (if mirrored).
#   2. GitHub code search for "<CVE-ID>".
#   3. nuclei-templates GitHub repo (if relevant).
#
# Drops candidates into /tmp/zuzu-pocs/<CVE>/ for the LLM to read with
# 'cat' before deciding whether to use them. Per AGENTS.md R6, the LLM
# must summarise and ask Raquel before executing any downloaded PoC.
#
# Usage:
#   bash scripts/recon-poc.sh CVE-2025-47812
#   bash scripts/recon-poc.sh CVE-2024-12345 --top 3

set -uo pipefail

CVE="${1:-}"
if [[ -z "$CVE" ]]; then
  cat <<'EOF'
recon-poc.sh — PoC discovery for a specific CVE

Usage:
  bash scripts/recon-poc.sh <CVE-ID> [--top N]

Caches PoC files in /tmp/zuzu-pocs/<CVE>/. Never auto-executes anything.
The LLM must read each PoC and summarise before asking Raquel to run it.
EOF
  exit 2
fi

if ! [[ "$CVE" =~ ^CVE-[0-9]{4}-[0-9]{3,7}$ ]]; then
  echo "❌ Not a CVE ID: $CVE  (expected like CVE-2025-47812)"
  exit 2
fi

TOP=5
if [[ "${2:-}" == "--top" && -n "${3:-}" ]]; then TOP="$3"; fi

CACHE="/tmp/zuzu-pocs/$CVE"
mkdir -p "$CACHE"

echo ""
echo "## PoC discovery for $CVE"
echo ""
echo "_Cache: $CACHE/_"
echo ""

# 1. searchsploit
echo "### Local ExploitDB"
echo ""
if command -v searchsploit >/dev/null 2>&1; then
  RES=$(searchsploit --color=never --cve "$CVE" 2>/dev/null || true)
  if [[ -n "$RES" ]]; then
    echo '```'
    echo "$RES"
    echo '```'
    # Mirror local files into the cache
    while read -r path; do
      [[ -f "$path" ]] && cp -n "$path" "$CACHE/" || true
    done < <(echo "$RES" | grep -oE '/usr/share/exploitdb/[^ ]+' || true)
  else
    echo "_No local match._"
  fi
else
  echo "_searchsploit not installed._"
fi
echo ""

# 2. GitHub search
echo "### GitHub PoC repos"
echo ""
GH=$(curl -s --max-time 12 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/search/repositories?q=$CVE&sort=stars&per_page=$TOP" 2>/dev/null)

if [[ -n "$GH" ]]; then
  python3 - "$GH" "$CACHE" "$TOP" <<'PY'
import json, sys, os, urllib.request, urllib.error
raw, cache_dir, top = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    data = json.loads(raw)
except Exception:
    print("_GitHub response not parseable._"); sys.exit(0)
items = data.get('items', [])
if not items:
    print("_No GitHub repos found for this CVE._"); sys.exit(0)
print("| Repo | ⭐ | URL |")
print("|---|---|---|")
for r in items[:top]:
    name = r.get('full_name','?')
    stars = r.get('stargazers_count', 0)
    url = r.get('html_url','')
    print(f"| {name} | {stars} | {url} |")

# Try to grab the main file (README + any .py/.sh/.rb at the repo root)
import re
for r in items[:top]:
    name = r.get('full_name','')
    branch = r.get('default_branch','main')
    safe = re.sub(r'[^A-Za-z0-9._-]','_', name)
    target = os.path.join(cache_dir, safe)
    os.makedirs(target, exist_ok=True)
    for fname in ('README.md','readme.md','exploit.py','poc.py','exploit.sh','poc.sh','main.py','main.go'):
        url = f"https://raw.githubusercontent.com/{name}/{branch}/{fname}"
        try:
            req = urllib.request.Request(url, headers={'User-Agent':'zuzu-recon'})
            with urllib.request.urlopen(req, timeout=8) as resp:
                if resp.status == 200:
                    body = resp.read()
                    if body and len(body) < 200_000:
                        with open(os.path.join(target, fname), 'wb') as f:
                            f.write(body)
        except Exception:
            pass
PY
else
  echo "_GitHub unreachable._"
fi
echo ""

# 3. Nuclei templates (lightweight signal)
echo "### Nuclei templates"
echo ""
NU=$(curl -s --max-time 8 \
  "https://api.github.com/search/code?q=$CVE+repo:projectdiscovery/nuclei-templates" 2>/dev/null)
if [[ -n "$NU" ]]; then
  python3 - "$NU" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("_Nuclei search failed._"); sys.exit(0)
items = data.get('items', [])
if not items:
    print("_No nuclei template found._"); sys.exit(0)
print("| Template | URL |")
print("|---|---|")
for it in items[:5]:
    print(f"| {it.get('path','?')} | {it.get('html_url','')} |")
PY
fi
echo ""

cat <<EOF
---
**Next step (LLM):**
1. \`ls $CACHE/\` to see what was fetched.
2. \`cat\` the most starred PoC; summarise what it does in 3-5 lines.
3. **Ask Raquel** before running any downloaded code (AGENTS.md R6).
4. Append a short note to reports/<target>/external-refs.md with the
   chosen PoC URL + your summary.
EOF
