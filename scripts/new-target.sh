#!/bin/bash
# new-target.sh — Initialize a per-target reports folder with the right
# structure. ALWAYS run this before starting work on any new target.
#
# Usage:
#   bash scripts/new-target.sh <target-or-ip> [hostname]
#
# Examples:
#   bash scripts/new-target.sh 10.10.10.50
#   bash scripts/new-target.sh 10.129.244.98 airtouch.htb
#   bash scripts/new-target.sh airtouch.htb
#
# Creates:
#   reports/<target>/
#     ├── notes.md          (running notes, free-form)
#     ├── nmap/             (all nmap output goes here)
#     ├── web/              (curl, gobuster, ffuf output)
#     ├── creds/            (any creds discovered)
#     ├── loot/             (downloaded files, dumps)
#     └── README.md         (target metadata + index)

set -euo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"

TARGET="${1:-}"
HOSTNAME="${2:-}"

if [[ -z "$TARGET" ]]; then
  cat <<EOF
new-target.sh — initialize reports/<target>/ for a new engagement

Usage:
  bash scripts/new-target.sh <target-or-ip> [hostname]

Example:
  bash scripts/new-target.sh 10.10.10.50
  bash scripts/new-target.sh 10.129.244.98 airtouch.htb

This creates the per-target folder structure and a README with the date.
ALL findings for this target should go inside reports/<target>/, never
in the root reports/ directory.
EOF
  exit 2
fi

# Sanitize: replace / with -, collapse weird chars
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"

if [[ -d "$DIR" ]]; then
  echo "ℹ️  Folder already exists: $DIR"
  echo "   Continuing — won't overwrite existing files."
else
  echo "[*] Creating: $DIR"
fi

mkdir -p "$DIR"/{nmap,web,creds,loot}

# Only create README if it doesn't exist (don't overwrite)
if [[ ! -f "$DIR/README.md" ]]; then
  cat > "$DIR/README.md" <<EOF
# Target: $TARGET${HOSTNAME:+ ($HOSTNAME)}

**Created:** $(date -Iseconds)
**Operator:** Zuzu 🐱‍💻

## Quick Facts

- **IP / Target:** $TARGET
${HOSTNAME:+- **Hostname:** $HOSTNAME}
- **Engagement type:** _(HTB / bug bounty / lab / authorized pentest)_
- **Status:** active

## Folder Layout

\`\`\`
reports/$SLUG/
├── README.md       ← this file (target metadata + status)
├── notes.md        ← running notes
├── nmap/           ← all nmap scan output
├── web/            ← curl, gobuster, ffuf, nikto output
├── creds/          ← any credentials discovered
└── loot/           ← downloaded files, dumps, screenshots
\`\`\`

## Index

_(Update this as you progress.)_

- [ ] Recon — port scan, service detection
- [ ] Recon — UDP, vhosts, subdomains
- [ ] Web enumeration
- [ ] Vulnerability assessment
- [ ] Initial access
- [ ] Privilege escalation
- [ ] User flag captured
- [ ] Root flag captured
- [ ] Final report written

## Commands log

_(Append meaningful commands and outcomes here. Useful for the report.)_

EOF
  echo "[+] Created: $DIR/README.md"
fi

if [[ ! -f "$DIR/notes.md" ]]; then
  cat > "$DIR/notes.md" <<EOF
# Notes — $TARGET

_Free-form running notes. Refine into the report when the engagement ends._

## $(date '+%Y-%m-%d %H:%M')

EOF
  echo "[+] Created: $DIR/notes.md"
fi

# Print the next-step hints
cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  🎯 Target folder ready: reports/$SLUG/
╚══════════════════════════════════════════════════════════════╝

Suggested first commands:

  # 1) Update /etc/hosts if there's a hostname
  ${HOSTNAME:+echo '$TARGET $HOSTNAME' | sudo tee -a /etc/hosts}

  # 2) Initial port scan (results into the folder)
  nmap -sC -sV -p- --min-rate 3000 -oA $DIR/nmap/full $TARGET

  # 3) Then start the orchestrator on this target
  bash scripts/orchestrator.sh init $TARGET

  # 4) Match the target to an archetype
  bash scripts/context-broker.sh <type>     # web, ad, ftp, snmp, ai, etc.

⚠️  RULE: All output for this target goes inside reports/$SLUG/
    Do NOT write loose .nmap / .txt files in reports/ root.

EOF
