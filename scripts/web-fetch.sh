#!/usr/bin/env bash
# web-fetch.sh — Trivial "fetch a URL, give me readable markdown" helper.
#
# Mostly a convenience for the LLM: when recon-* produces a URL, this
# turns it into something readable in one step. Falls through to a hint
# about the OpenClaw `web_fetch` tool if direct curl fails (e.g.
# Cloudflare / JS-heavy SPA).
#
# Usage:
#   bash scripts/web-fetch.sh <url> [--raw]
#   bash scripts/web-fetch.sh https://book.hacktricks.wiki/...
#
# --raw skips HTML→text conversion and dumps the body as-is.

set -uo pipefail

URL="${1:-}"
RAW="${2:-}"

if [[ -z "$URL" ]]; then
  cat <<'EOF'
web-fetch.sh — fetch a URL into readable markdown

Usage:
  bash scripts/web-fetch.sh <url> [--raw]
EOF
  exit 2
fi

UA='Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'

BODY=$(curl -sSL --max-time 15 -A "$UA" "$URL" 2>/dev/null || true)

if [[ -z "$BODY" ]]; then
  cat <<EOF
_Fetch failed for: $URL_

Likely causes: Cloudflare, JS-heavy SPA, login wall, network down.

Try one of:
  • OpenClaw \`web_fetch\` tool (LLM-callable, may handle redirects better)
  • \`stealth-browser\` skill (handles Cloudflare + JS rendering)
  • \`tavily-search-pro\` skill (Tavily extract / research mode)
EOF
  exit 1
fi

if [[ "$RAW" == "--raw" ]]; then
  echo "$BODY"
  exit 0
fi

echo "$BODY" | python3 -c "
import sys, html, re
raw = sys.stdin.read()
# Strip script and style first
raw = re.sub(r'<script[^>]*>.*?</script>', '', raw, flags=re.S|re.I)
raw = re.sub(r'<style[^>]*>.*?</style>', '', raw, flags=re.S|re.I)
# Try to keep markdown-ish line breaks for headings / paragraphs / code
raw = re.sub(r'<h(\d)[^>]*>', lambda m: '\n\n' + '#'*int(m.group(1)) + ' ', raw, flags=re.I)
raw = re.sub(r'</h\d>', '\n', raw, flags=re.I)
raw = re.sub(r'<(p|div|li|tr)[^>]*>', '\n', raw, flags=re.I)
raw = re.sub(r'<br\s*/?>', '\n', raw, flags=re.I)
raw = re.sub(r'<pre[^>]*>', '\n\`\`\`\n', raw, flags=re.I)
raw = re.sub(r'</pre>', '\n\`\`\`\n', raw, flags=re.I)
raw = re.sub(r'<code[^>]*>', '\`', raw, flags=re.I)
raw = re.sub(r'</code>', '\`', raw, flags=re.I)
# Remove all remaining tags
text = re.sub(r'<[^>]+>', ' ', raw)
text = html.unescape(text)
# Collapse excessive whitespace but keep paragraph breaks
text = re.sub(r'[ \t]+', ' ', text)
text = re.sub(r'\n[ \t]+', '\n', text)
text = re.sub(r'\n{3,}', '\n\n', text)
text = text.strip()
# Cap at 8000 chars so we don't dump megabytes
if len(text) > 8000:
    text = text[:8000] + '\n\n…[truncated; use --raw for the full body]'
print(text)
"
