#!/usr/bin/env bash
# recon-tech.sh — Broad live-knowledge probe for any keyword or technology.
#
# Tier order (best first; falls through if a tier fails):
#   1. Tavily Search API (if TAVILY_API_KEY in env) — best signal, with
#      AI summary + citations.
#   2. DuckDuckGo HTML scrape — no key needed, brittle.
#   3. Hint to use the OpenClaw `web_search` / `web_fetch` / `tavily-search-pro`
#      / `stealth-browser` tools directly when this script can't reach.
#
# Usage:
#   bash scripts/recon-tech.sh "<keywords>"
#   bash scripts/recon-tech.sh "modbus exploitation"
#   bash scripts/recon-tech.sh "JWT alg none bypass"

set -uo pipefail

QUERY="${*:-}"
if [[ -z "$QUERY" ]]; then
  cat <<'EOF'
recon-tech.sh — open-ended tech / writeup / docs lookup

Usage:
  bash scripts/recon-tech.sh "<keywords>"

Tries Tavily (if TAVILY_API_KEY set), then DuckDuckGo, then points at
OpenClaw web tools. Output is markdown, append to external-refs.md.
EOF
  exit 2
fi

echo ""
echo "## Tech recon for: $QUERY"
echo ""

# ─── Tier 1: Tavily ─────────────────────────────────────────────────────
TAVILY_KEY="${TAVILY_API_KEY:-}"
if [[ -z "$TAVILY_KEY" ]] && [[ -f ~/.openclaw/openclaw.json ]]; then
  TAVILY_KEY=$(python3 -c "
import json, os
try:
    d = json.load(open(os.path.expanduser('~/.openclaw/openclaw.json')))
    print(d.get('env',{}).get('TAVILY_API_KEY',''))
except Exception:
    print('')
" 2>/dev/null)
fi

if [[ -n "$TAVILY_KEY" ]]; then
  echo "### Tavily (AI search with citations)"
  echo ""
  RESPONSE=$(curl -s --max-time 20 -X POST 'https://api.tavily.com/search' \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json, sys
print(json.dumps({
    'api_key': sys.argv[1],
    'query': sys.argv[2],
    'search_depth': 'advanced',
    'max_results': 5,
    'include_answer': True
}))" "$TAVILY_KEY" "$QUERY")" 2>/dev/null || true)

  if [[ -n "$RESPONSE" ]] && echo "$RESPONSE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    python3 - "$RESPONSE" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
ans = data.get('answer')
if ans:
    print("**AI summary:**", ans[:1200])
    print()
results = data.get('results', [])
if results:
    print("**Top citations:**\n")
    for r in results[:5]:
        title = (r.get('title','') or '?')[:90]
        url   = r.get('url','')
        score = r.get('score', 0)
        snippet = (r.get('content','') or '')[:300].replace('\n',' ')
        print(f"- **[{title}]({url})** (score={score:.2f})")
        print(f"  > {snippet}…")
        print()
PY
    echo ""
    echo "_Tavily answered. Skipping DDG fallback._"
    echo ""
    cat <<'EOF'
---
**Next step:** append URL + 2-line summary to `reports/<target>/external-refs.md`.
For deeper extraction (Cloudflare, login walls), use the `stealth-browser` skill.
EOF
    exit 0
  else
    echo "_Tavily request failed (network or invalid key). Falling back to DuckDuckGo._"
    echo ""
  fi
fi

# ─── Tier 2: DuckDuckGo HTML ────────────────────────────────────────────
echo "### DuckDuckGo (fallback)"
echo ""

ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")
DDG_URL="https://duckduckgo.com/html/?q=$ENC"
UA='Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'

HTML=$(curl -s --max-time 10 -A "$UA" "$DDG_URL" 2>/dev/null || true)

if [[ -z "$HTML" ]]; then
  cat <<'EOF'
_No network response from DuckDuckGo. Use the OpenClaw tools directly:_
  • `web_search`        (provider-routed)
  • `web_fetch <url>`   (single-page extract)
  • `tavily-search-pro` skill (research mode for citations + depth)
  • `stealth-browser`   skill (Cloudflare / JS-heavy / login-walled)
EOF
  exit 0
fi

URLS=$(echo "$HTML" | grep -oE 'uddg=[^"&]+' | head -5 \
  | python3 -c "import sys, urllib.parse
for line in sys.stdin:
    v = line.strip().replace('uddg=','')
    print(urllib.parse.unquote(v))" 2>/dev/null | sort -u | head -5)

if [[ -z "$URLS" ]]; then
  echo "_DDG returned no parseable links. Try the OpenClaw \`web_search\` tool._"
  exit 0
fi

echo "**Top hits:**"
echo ""
i=0
while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  i=$((i+1))
  echo ""
  echo "**[$i] $url**"
  echo ""
  TXT=$(curl -s --max-time 8 -A "$UA" "$url" 2>/dev/null \
    | python3 -c "import sys, html, re
raw = sys.stdin.read()
raw = re.sub(r'<script[^>]*>.*?</script>', '', raw, flags=re.S|re.I)
raw = re.sub(r'<style[^>]*>.*?</style>', '', raw, flags=re.S|re.I)
text = re.sub(r'<[^>]+>', ' ', raw)
text = html.unescape(text)
text = re.sub(r'\s+', ' ', text).strip()
print(text[:1200])" 2>/dev/null || echo "")
  if [[ -z "$TXT" ]]; then
    echo "_(unreadable)_"
  else
    echo "> ${TXT:0:1000}…"
  fi
  if (( i >= 3 )); then break; fi
done <<<"$URLS"

echo ""
echo "---"
echo "_For deeper extraction or login-walled sources, use \`tavily-search-pro\` or \`stealth-browser\`._"
