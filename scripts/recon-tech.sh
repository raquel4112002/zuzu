#!/usr/bin/env bash
# recon-tech.sh — Broad live-knowledge probe for any keyword or technology.
#
# Wraps web search + targeted fetch. Use when you don't recognise a stack
# or need writeups / blog posts / documentation. Output is markdown.
#
# Usage:
#   bash scripts/recon-tech.sh "modbus exploitation"
#   bash scripts/recon-tech.sh "JWT alg none bypass"
#   bash scripts/recon-tech.sh "supabase storage misconfiguration"
#
# Implementation notes:
#   - Prefers DuckDuckGo HTML (no API key needed) for breadth.
#   - Parses out top result URLs, fetches the first 3 with a short timeout,
#     and condenses each into 6 lines via simple HTML→text.
#   - Falls back to a hint pointing the LLM to the OpenClaw web_search /
#     web_fetch / tavily-search-pro tools if the script can't reach the net.

set -uo pipefail

QUERY="${*:-}"
if [[ -z "$QUERY" ]]; then
  cat <<'EOF'
recon-tech.sh — open-ended tech / writeup / docs lookup

Usage:
  bash scripts/recon-tech.sh "<keywords>"

Returns a markdown block with the top web hits + short summaries. For
deeper / agentic browsing (Cloudflare, login walls), use the
stealth-browser or tavily-search-pro skills directly.
EOF
  exit 2
fi

echo ""
echo "## Tech recon for: $QUERY"
echo ""

ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")
DDG_URL="https://duckduckgo.com/html/?q=$ENC"

HTML=$(curl -s --max-time 10 -A 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0' \
  "$DDG_URL" 2>/dev/null || true)

if [[ -z "$HTML" ]]; then
  cat <<EOF
_No network response from DuckDuckGo. Use the OpenClaw tools directly:_
  • \`web_search\` (provider-routed)
  • \`web_fetch <url>\` (single-page extract)
  • \`tavily-search-pro\` skill (research mode for citations + depth)
EOF
  exit 0
fi

# Parse top URLs (DDG html result links)
URLS=$(echo "$HTML" | grep -oE 'uddg=[^"&]+' | head -5 \
  | python3 -c "import sys, urllib.parse
for line in sys.stdin:
    v = line.strip().replace('uddg=','')
    print(urllib.parse.unquote(v))" 2>/dev/null | sort -u | head -5)

if [[ -z "$URLS" ]]; then
  echo "_DDG returned no parseable links. Try a different query, or use the OpenClaw web_search tool._"
  exit 0
fi

echo "### Top hits"
echo ""
i=0
while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  i=$((i+1))
  echo ""
  echo "**[$i] $url**"
  echo ""
  TXT=$(curl -s --max-time 8 -A 'Mozilla/5.0' "$url" 2>/dev/null \
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
