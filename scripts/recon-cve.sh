#!/usr/bin/env bash
# recon-cve.sh — Live CVE lookup for "<product> [version]".
#
# Pulls from three sources, deterministic order:
#   1. searchsploit (local Kali ExploitDB) — instant, offline.
#   2. NVD 2.0 API — official, structured JSON, no auth needed for low rate.
#   3. GitHub code search — finds public PoC repos.
#
# Output: a single markdown block, with a header line per source. Each CVE
# row shows ID, severity (if known), one-line description, and clickable
# URL. Designed to be appended to reports/<target>/external-refs.md.
#
# Usage:
#   bash scripts/recon-cve.sh "wing ftp 7.4.3"
#   bash scripts/recon-cve.sh flowise 3.0.5
#   bash scripts/recon-cve.sh "$PRODUCT" "$VERSION"
#
# Notes:
#   - Never auto-runs any exploit. PoC fetching is in scripts/recon-poc.sh.
#   - Caches NVD responses in /tmp/zuzu-cve-cache/ for 1 hour.

set -uo pipefail

QUERY="${*:-}"
if [[ -z "$QUERY" ]]; then
  cat <<'EOF'
recon-cve.sh — live CVE lookup

Usage:
  bash scripts/recon-cve.sh "<product> [version]"

Sources: searchsploit (local) → NVD 2.0 API → GitHub code search.
Output is markdown. Append it to reports/<target>/external-refs.md.
EOF
  exit 2
fi

PRODUCT_VERSION="$QUERY"
CACHE="/tmp/zuzu-cve-cache"
mkdir -p "$CACHE"

echo ""
echo "## CVE recon for: $PRODUCT_VERSION"
echo ""

# 1. searchsploit (offline, fast)
echo "### Local ExploitDB (searchsploit)"
echo ""
if command -v searchsploit >/dev/null 2>&1; then
  RESULT=$(searchsploit --color=never "$PRODUCT_VERSION" 2>/dev/null | sed -n '/--------/,$p' | head -40 || true)
  if [[ -n "$RESULT" ]]; then
    echo '```'
    echo "$RESULT"
    echo '```'
  else
    echo "_No local matches._"
  fi
else
  echo "_searchsploit not installed (apt install exploitdb)._"
fi
echo ""

# 2. NVD 2.0 API (structured, current)
echo "### NVD (current public CVEs)"
echo ""
NVD_KEY=$(echo "$PRODUCT_VERSION" | tr '/ ' '__' | tr -cd 'a-zA-Z0-9._-')
NVD_FILE="$CACHE/nvd-$NVD_KEY.json"

# Cache for 1h
if [[ ! -f "$NVD_FILE" ]] || [[ $(find "$NVD_FILE" -mmin +60 2>/dev/null) ]]; then
  KEYWORD=$(echo "$PRODUCT_VERSION" | sed 's/ /%20/g')
  curl -s --max-time 12 \
    "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=$KEYWORD&resultsPerPage=15" \
    -o "$NVD_FILE" 2>/dev/null || true
fi

if [[ -s "$NVD_FILE" ]]; then
  python3 - "$NVD_FILE" <<'PY' 2>/dev/null || echo "_NVD parse failed._"
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"_Invalid NVD response: {e}_")
    sys.exit(0)
items = data.get('vulnerabilities', [])
if not items:
    print("_No NVD matches._")
    sys.exit(0)
print("| CVE | CVSS | Published | Summary |")
print("|---|---|---|---|")
for v in items[:15]:
    c = v.get('cve', {})
    cid = c.get('id', '?')
    pub = (c.get('published','') or '')[:10]
    desc = ''
    for d in c.get('descriptions', []):
        if d.get('lang') == 'en':
            desc = d.get('value','').replace('\n',' ').replace('|','\\|')
            break
    desc = (desc[:140] + '…') if len(desc) > 140 else desc
    cvss = '?'
    metrics = c.get('metrics', {})
    for k in ('cvssMetricV31','cvssMetricV30','cvssMetricV2'):
        if metrics.get(k):
            cvss = metrics[k][0].get('cvssData',{}).get('baseScore','?')
            break
    print(f"| [{cid}](https://nvd.nist.gov/vuln/detail/{cid}) | {cvss} | {pub} | {desc} |")
PY
else
  echo "_NVD unreachable (network?). Try again later._"
fi
echo ""

# 3. GitHub code search (PoC repos)
echo "### GitHub PoC search"
echo ""
GH_QUERY=$(echo "$PRODUCT_VERSION" | sed 's/ /+/g')
GH_URL="https://api.github.com/search/repositories?q=$GH_QUERY+poc+OR+exploit&sort=updated&per_page=10"
GH_FILE="$CACHE/gh-$NVD_KEY.json"

if [[ ! -f "$GH_FILE" ]] || [[ $(find "$GH_FILE" -mmin +60 2>/dev/null) ]]; then
  curl -s --max-time 10 -H "Accept: application/vnd.github+json" \
    "$GH_URL" -o "$GH_FILE" 2>/dev/null || true
fi

if [[ -s "$GH_FILE" ]]; then
  python3 - "$GH_FILE" <<'PY' 2>/dev/null || echo "_GitHub parse failed._"
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("_Invalid GitHub response._"); sys.exit(0)
items = data.get('items', [])
if not items:
    print("_No GitHub PoC repos found._"); sys.exit(0)
print("| Repo | ⭐ | Updated | Description |")
print("|---|---|---|---|")
for r in items[:10]:
    name = r.get('full_name','?')
    stars = r.get('stargazers_count', 0)
    upd = (r.get('updated_at','') or '')[:10]
    desc = (r.get('description') or '').replace('\n',' ').replace('|','\\|')
    desc = (desc[:100] + '…') if len(desc) > 100 else desc
    print(f"| [{name}](https://github.com/{name}) | {stars} | {upd} | {desc} |")
PY
else
  echo "_GitHub unreachable (or rate-limited)._"
fi
echo ""

echo "---"
echo "_Sourced by recon-cve.sh — append this block to reports/<target>/external-refs.md._"
