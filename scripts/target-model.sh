#!/usr/bin/env bash
# target-model.sh — Scaffold the first-principles target model file.
#
# THINK.md Layer 2 demands a written model: nodes, edges, trust labels,
# data flows, identity model. This helper drops a structured skeleton
# at reports/<target>/target-model.md so weak LLMs are forced to fill it
# in rather than skip the step.
#
# Usage:
#   bash scripts/target-model.sh        # uses active engagement
#   bash scripts/target-model.sh <target>

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$WS/state/orchestrator.json"

TARGET="${1:-}"
if [[ -z "$TARGET" && -f "$STATE_FILE" ]]; then
  TARGET=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['target'])" 2>/dev/null || echo "")
fi
if [[ -z "$TARGET" ]]; then
  echo "Usage: bash scripts/target-model.sh [<target>]"
  echo "(or run pentest.sh first so an active engagement exists)"
  exit 2
fi

SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"
mkdir -p "$DIR"
FILE="$DIR/target-model.md"

if [[ -f "$FILE" ]]; then
  echo "ℹ️  $FILE already exists — opening for review (not overwriting)."
  echo ""
  head -40 "$FILE"
  exit 0
fi

cat > "$FILE" <<EOF
# Target model — $TARGET

> THINK.md Layer 2. **A graph of components and trust relationships.**
> Update after every new finding. The act of writing this surfaces the
> assumptions you can attack.

## Nodes (services / processes / containers / users)

_What is running? Who exists? Be concrete; mark inferred items with (inf)._

- **node-1**: _e.g. nginx 1.22 on :80, terminates TLS, proxies to app_
- **node-2**: _e.g. node.js Express on 127.0.0.1:3000 (inf — only proxy reachable)_
- **node-3**: _e.g. Postgres on internal 5432 (inf — schema strings in JS bundle)_
- **node-4**: _e.g. cron job running as root every 5 min — see /etc/cron.d/_
- **users / roles**: _admin, member, anonymous; service accounts: postgres, www-data_

## Edges (who talks to whom, with what trust)

\`\`\`
browser  ──[TLS, session cookie]──►  nginx
  nginx  ──[plain HTTP, no auth header forwarding]──►  express:3000
  express ──[psql, hardcoded creds (inf)]──►  postgres
  cron   ──[shell, runs as root, reads /var/uploads]──►  filesystem
\`\`\`

Trust labels to use: \`anonymous\`, \`session-authed\`, \`api-key\`,
\`mTLS\`, \`internal-only\`, \`implicit-same-host\`, \`signed-token\`,
\`shared-secret\`, \`unverified\`.

## Data flows (where does input enter / get reflected / executed)

- **Entry points:** _e.g. POST /api/upload, GET /search?q=, websocket /ws_
- **Reflection points:** _e.g. error pages echo URL, admin panel renders user input as HTML_
- **Execution points:** _e.g. cron runs scripts from /var/uploads, server-side template render of profile.bio_
- **Sink for secrets:** _e.g. JWT cookies, env vars in /proc/self/environ, .env in /opt/app_

## Identity model

- **Who can authenticate?** _e.g. local DB users, LDAP via /admin only_
- **What does each role get?** _e.g. member: read self, write self; admin: read all, exec ops_
- **How is identity propagated downstream?** _e.g. session cookie → upstream X-User header (trusted blindly)_

## Known unknowns (mark them — don't pretend you know)

- [ ] Does the app trust the X-Forwarded-* headers from nginx? **PROBE THIS.**
- [ ] Is there an admin port other than 80/443?
- [ ] Where does the upload pipeline finally execute?
- [ ] What's the secret-management story? .env, vault, env vars, files?
- [ ] _(add more — every unknown is a hypothesis seed)_

## Assumption check (THINK.md Layer 3 input)

After this model, immediately go to:
\`bash scripts/target-model.sh assumptions\`
or write \`reports/$SLUG/assumptions.md\` directly. **Each unknown above
becomes at least one assumption.**

EOF

echo "✅ Created $FILE"
echo ""
echo "→ Edit it with concrete observations from surface.md / nmap / curl."
echo "→ Then proceed to assumptions.md (Layer 3) and the hypothesis bank."
