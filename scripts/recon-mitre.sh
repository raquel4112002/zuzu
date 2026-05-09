#!/usr/bin/env bash
# recon-mitre.sh — Lookup MITRE ATT&CK techniques by keyword or technique ID.
#
# Pulls the official MITRE ATT&CK STIX bundle (cached 24h) and greps it for
# matching techniques. Returns ID, name, tactics, short description, and
# direct URL to the technique page.
#
# Usage:
#   bash scripts/recon-mitre.sh "lateral movement"
#   bash scripts/recon-mitre.sh T1078
#   bash scripts/recon-mitre.sh "kerberoast"
#
# Output: markdown block, drop into reports/<target>/external-refs.md.

set -uo pipefail

QUERY="${*:-}"
if [[ -z "$QUERY" ]]; then
  cat <<'EOF'
recon-mitre.sh — MITRE ATT&CK technique lookup

Usage:
  bash scripts/recon-mitre.sh "<keyword|technique-id>"

Examples:
  bash scripts/recon-mitre.sh "kerberoast"
  bash scripts/recon-mitre.sh T1078
  bash scripts/recon-mitre.sh "command and scripting"
EOF
  exit 2
fi

CACHE="/tmp/zuzu-mitre-cache"
mkdir -p "$CACHE"
BUNDLE="$CACHE/enterprise-attack.json"
URL="https://raw.githubusercontent.com/mitre/cti/master/enterprise-attack/enterprise-attack.json"

# refresh cache once a day
if [[ ! -f "$BUNDLE" ]] || [[ $(find "$BUNDLE" -mmin +1440 2>/dev/null) ]]; then
  echo "_Refreshing MITRE ATT&CK bundle (cached 24h)..._" >&2
  curl -s --max-time 30 "$URL" -o "$BUNDLE" 2>/dev/null || true
fi

if [[ ! -s "$BUNDLE" ]]; then
  echo "## MITRE recon for: $QUERY"
  echo ""
  echo "_MITRE bundle unavailable. Falling back to the local mirror at:"
  echo "knowledge-base/mitre-attack/enterprise-tactics.md_"
  exit 0
fi

python3 - "$BUNDLE" "$QUERY" <<'PY'
import json, sys, re
bundle_path, query = sys.argv[1], sys.argv[2]
q = query.lower()
data = json.load(open(bundle_path))
techs = [o for o in data.get('objects',[])
         if o.get('type') == 'attack-pattern' and not o.get('revoked')]

# Build {id, name, tactics, desc, url} list
def ext_id(o):
    for r in o.get('external_references',[]):
        if r.get('source_name') == 'mitre-attack':
            return r.get('external_id'), r.get('url')
    return None, None

rows = []
for t in techs:
    tid, url = ext_id(t)
    if not tid:
        continue
    name = t.get('name','')
    desc = (t.get('description','') or '').replace('\n',' ')
    tactics = ','.join(p.get('phase_name','') for p in t.get('kill_chain_phases',[]))
    hay = f"{tid} {name} {desc}".lower()
    if q in hay or re.search(re.escape(q), hay):
        rows.append((tid, name, tactics, desc, url))

if not rows:
    print(f"## MITRE recon for: {query}\n\n_No matches._")
    sys.exit(0)

# rank: ID exact-match first, then name match, then desc match
def rank(r):
    tid, name, _, desc, _ = r
    if q == tid.lower(): return 0
    if q in name.lower(): return 1
    return 2
rows.sort(key=rank)

print(f"## MITRE recon for: {query}\n")
print("| ID | Name | Tactic(s) | Summary |")
print("|---|---|---|---|")
for tid, name, tac, desc, url in rows[:12]:
    short = (desc[:140] + '…') if len(desc) > 140 else desc
    short = short.replace('|','\\|')
    print(f"| [{tid}]({url}) | {name} | {tac} | {short} |")

# If exactly one strong hit, print its full description for deeper context
if rank(rows[0]) <= 1 and len(rows) <= 3:
    tid, name, tac, desc, url = rows[0]
    print(f"\n### {tid} — {name} (full)\n")
    full = desc[:1200] + ('…' if len(desc) > 1200 else '')
    print(full)
    print(f"\n→ Full page: {url}")
PY
