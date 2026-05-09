#!/usr/bin/env bash
# recon-hacktricks.sh — Dedicated probe for the three best technique-level
# offensive-security references on the public web:
#
#   1. HackTricks            — book.hacktricks.wiki  (technique recipes)
#   2. PayloadsAllTheThings  — github.com/swisskyrepo/PayloadsAllTheThings
#   3. GTFOBins              — gtfobins.github.io    (privesc binaries)
#
# These are the references a top researcher reflexively reaches for when
# they need a payload class, a syntax cheat, or a binary-abuse trick.
# Wrapping them as a named tool makes "I don't know how to <do X>" no
# longer a stop condition for any LLM.
#
# Usage:
#   bash scripts/recon-hacktricks.sh "<query>"
#   bash scripts/recon-hacktricks.sh "kerberoasting"
#   bash scripts/recon-hacktricks.sh "ssti jinja"
#   bash scripts/recon-hacktricks.sh "tar privesc"            # → GTFOBins hit
#   bash scripts/recon-hacktricks.sh --gtfobins "find"
#   bash scripts/recon-hacktricks.sh --hacktricks "active directory"
#   bash scripts/recon-hacktricks.sh --payloads "xxe"
#
# Output: markdown block, drop into reports/<target>/external-refs.md.
#
# Strategy:
#   - GTFOBins exposes a per-binary YAML at gtfobins.github.io/gtfobins/<name>/.
#     If the query looks like a single binary, fetch directly. Otherwise
#     search via DuckDuckGo with site: filters.
#   - HackTricks: site:book.hacktricks.wiki <query>
#   - Payloads: site:github.com/swisskyrepo/PayloadsAllTheThings <query>

set -uo pipefail

QUERY=""
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gtfobins)    ONLY="gtfobins";   QUERY="$2"; shift 2;;
    --hacktricks)  ONLY="hacktricks"; QUERY="$2"; shift 2;;
    --payloads)    ONLY="payloads";   QUERY="$2"; shift 2;;
    *)             QUERY="${QUERY:+$QUERY }$1"; shift;;
  esac
done

if [[ -z "$QUERY" ]]; then
  cat <<'EOF'
recon-hacktricks.sh — HackTricks + PayloadsAllTheThings + GTFOBins probe

Usage:
  bash scripts/recon-hacktricks.sh "<query>"
  bash scripts/recon-hacktricks.sh --gtfobins   "<binary>"
  bash scripts/recon-hacktricks.sh --hacktricks "<topic>"
  bash scripts/recon-hacktricks.sh --payloads   "<class>"

Examples:
  bash scripts/recon-hacktricks.sh "kerberoasting"
  bash scripts/recon-hacktricks.sh --gtfobins find
  bash scripts/recon-hacktricks.sh --hacktricks "ssti jinja"
  bash scripts/recon-hacktricks.sh --payloads "xxe"
EOF
  exit 2
fi

CACHE="/tmp/zuzu-hacktricks-cache"
mkdir -p "$CACHE"

echo ""
echo "## Technique recon for: $QUERY"
echo ""

UA='Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'

# ─── GTFOBins direct fetch when query looks like a single binary ───────
if [[ -z "$ONLY" || "$ONLY" == "gtfobins" ]]; then
  echo "### GTFOBins"
  echo ""
  # Direct lookup if single token
  if [[ "$QUERY" =~ ^[a-z0-9_-]+$ ]]; then
    URL="https://gtfobins.github.io/gtfobins/$QUERY/"
    HTML=$(curl -sL --max-time 8 -A "$UA" "$URL" 2>/dev/null || true)
    if [[ -n "$HTML" ]] && ! echo "$HTML" | grep -q "Page not found" && echo "$HTML" | grep -q "<h2"; then
      echo "**Direct hit:** [$QUERY]($URL)"
      echo ""
      # Extract the function tags (Shell, Sudo, SUID, Capabilities, etc.)
      FUNCS=$(echo "$HTML" | grep -oE 'data-functions="[^"]+"' | head -1 | sed 's/data-functions="//;s/"//')
      if [[ -n "$FUNCS" ]]; then
        echo "Available abuse functions: \`$FUNCS\`"
        echo ""
      fi
      # Snippet of the main code block
      echo "Quick summary (extracted):"
      echo '```'
      echo "$HTML" | python3 -c "
import sys, re, html
raw = sys.stdin.read()
# GTFOBins structure: each function is an <h2> with id, followed by
# a <p> description, then a <pre>. Be permissive on attribute order.
funcs = re.findall(r'<h2[^>]*id=[\"\\']?f-(\w+)[\"\\']?[^>]*>.*?(<pre[^>]*>.*?</pre>)', raw, re.S)
if not funcs:
    # Fallback: any h2 followed by a pre block
    funcs = re.findall(r'<h2[^>]*>([^<]+)</h2>.*?(<pre[^>]*>.*?</pre>)', raw, re.S)
for name, pre in funcs[:4]:
    code = re.sub(r'<[^>]+>', '', pre)
    code = html.unescape(code).strip()
    print(f'-- {name.upper().strip()} --')
    print(code[:400])
    print()
if not funcs:
    print('(no parseable function blocks \u2014 fetch the URL with web-fetch.sh)')
"
      echo '```'
    else
      echo "_No direct GTFOBins page for '$QUERY'. Use DDG below._"
    fi
  else
    # Multi-word query — DDG site search
    ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "site:gtfobins.github.io $QUERY")
    HTML=$(curl -s --max-time 8 -A "$UA" "https://duckduckgo.com/html/?q=$ENC" 2>/dev/null || true)
    if [[ -n "$HTML" ]]; then
      echo "$HTML" | grep -oE 'uddg=[^"&]+' | head -3 | python3 -c "
import sys, urllib.parse
for line in sys.stdin:
    v = line.strip().replace('uddg=','')
    print(f'  - {urllib.parse.unquote(v)}')
"
    fi
  fi
  echo ""
fi

# ─── Resolve Tavily key once (env or openclaw.json) ─────────────────────
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

tavily_search() {
  # $1 = query, $2 = include_domain (e.g. "hacktricks.wiki")
  local q="$1" dom="$2"
  [[ -z "$TAVILY_KEY" ]] && return 1
  curl -s --max-time 15 -X POST 'https://api.tavily.com/search' \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c "
import json, sys
body = {
  'api_key': sys.argv[1],
  'query':   sys.argv[2],
  'search_depth': 'basic',
  'max_results': 5
}
if sys.argv[3]:
    body['include_domains'] = [sys.argv[3]]
print(json.dumps(body))
" "$TAVILY_KEY" "$q" "$dom")" 2>/dev/null
}

# ─── HackTricks search ──────────────────────────────────────────────────
if [[ -z "$ONLY" || "$ONLY" == "hacktricks" ]]; then
  echo "### HackTricks"
  echo ""
  RESPONSE=$(tavily_search "$QUERY" "hacktricks.wiki")
  if [[ -n "$RESPONSE" ]] && echo "$RESPONSE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    HITS=$(echo "$RESPONSE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
results = d.get('results', [])
if not results:
    sys.exit(1)
for r in results[:4]:
    title = (r.get('title','?') or '?')[:90]
    url   = r.get('url','')
    snippet = (r.get('content','') or '')[:600].replace('\n',' ')
    print(f'**[{title}]({url})**')
    print()
    print(f'> {snippet}…')
    print()
" 2>/dev/null)
    if [[ -n "$HITS" ]]; then
      echo "$HITS"
    else
      echo "_Tavily returned no HackTricks hits. Try \`web_search \"site:hacktricks.wiki $QUERY\"\` directly._"
    fi
  else
    echo "_Tavily unavailable. Try \`web_search \"site:hacktricks.wiki $QUERY\"\` directly, or use \`stealth-browser\` skill._"
  fi
  echo ""
fi

# ─── PayloadsAllTheThings via GitHub code search ────────────────────────
if [[ -z "$ONLY" || "$ONLY" == "payloads" ]]; then
  echo "### PayloadsAllTheThings"
  echo ""
  ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")
  GH_URL="https://api.github.com/search/code?q=$ENC+repo:swisskyrepo/PayloadsAllTheThings&per_page=8"
  GH=$(curl -s --max-time 10 -A "$UA" -H "Accept: application/vnd.github+json" "$GH_URL" 2>/dev/null || true)
  if [[ -n "$GH" ]]; then
    python3 - "$GH" <<'PY' 2>/dev/null || echo "_GitHub parse failed._"
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("_GitHub returned non-JSON (rate-limited?)._"); sys.exit(0)
items = data.get('items', [])
if not items:
    msg = data.get('message','')
    if 'rate limit' in msg.lower():
        print("_GitHub rate-limited. Wait or set GITHUB_TOKEN env var._")
    else:
        print("_No PayloadsAllTheThings hits for this query._")
    sys.exit(0)
print("| File | URL |")
print("|---|---|")
for it in items[:8]:
    path = it.get('path','?')
    url  = it.get('html_url','')
    print(f"| {path} | {url} |")
PY
  else
    echo "_GitHub unreachable._"
  fi
  echo ""
fi

cat <<EOF
---
**Next step (LLM):**
- Read the most relevant hit with: \`bash scripts/web-fetch.sh <url>\` or the OpenClaw \`web_fetch\` tool.
- Append URL + 2-line summary + key payload to \`reports/<target>/external-refs.md\`.
- Convert the technique into a hypothesis:
    \`bash scripts/hypotheses.sh add "<H>" --falsifier "<one-cmd>" --cost LOW --impact HIGH --source catalog\`
EOF
