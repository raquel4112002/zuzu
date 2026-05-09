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

mkdir -p "$DIR"/{nmap,web,creds,loot,exploits,tunnels}

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

# ENGAGEMENT.md — the working-state contract any LLM can read at any
# point to know exactly where things stand. Updated after every phase.
if [[ ! -f "$DIR/ENGAGEMENT.md" ]]; then
  cat > "$DIR/ENGAGEMENT.md" <<EOF
# ENGAGEMENT — $TARGET${HOSTNAME:+ ($HOSTNAME)}

> Working-state contract. **Update this after every phase.** A new
> operator (or LLM) should be able to read this file and resume work
> in seconds. Keep it short, factual, current.

**Started:** $(date -Iseconds)
**Status:** 🟡 active — recon
**Stop condition:** user.txt + root.txt (or documented blocker w/ H1/H2/H3)

---

## 1. Target

- **IP / host:** $TARGET
${HOSTNAME:+- **Hostname / vhost:** $HOSTNAME}
- **Engagement type:** _(HTB / lab / bug bounty / authorized pentest)_
- **Scope:** _(what's in / out)_
- **Time budget:** _(if any)_

## 2. Open ports & services

_Updated by zero.sh and your follow-up scans. Keep it as a flat list._

| Port | Proto | Service | Version | Notes |
|------|-------|---------|---------|-------|
| | | | | |

## 3. Identified attack surface

_What's reachable, what's interesting, what's been ruled out._

- [ ] Web app(s): _(URLs)_
- [ ] Auth wall(s): _(login form, basic auth, JWT, etc.)_
- [ ] File services: _(SMB shares, FTP, NFS)_
- [ ] AD / Kerberos: _(domain, controller, users harvested)_
- [ ] Open-source app identified: _(name, version → source-dive done? y/n)_
- [ ] Known CVE candidates: _(CVE-id → status)_

## 4. Credentials & artefacts collected

| Type | Value (last 4 / hash prefix only) | Source | Tested where | Status |
|------|----------------------------------|--------|--------------|--------|
| | | | | |

_Full creds live in \`creds/\` (not in this file, not in git)._

## 5. Foothold(s)

- [ ] Initial access: _(user, host, method)_
- [ ] Privesc to root/SYSTEM: _(method)_
- [ ] Lateral targets: _(host list)_

## 6. Flags / proof

- [ ] **user.txt** — _(path + hash)_
- [ ] **root.txt** — _(path + hash)_
- [ ] Other proof: _(screenshot path, command transcript path)_

## 7. Stuck-gate / hypotheses

_Only fill this in if you've stalled ≥ 2 attempts in a phase. Each
hypothesis must have a single command that confirms or falsifies it._

- **H1** — 
  - Falsifier: \`...\`
  - Result: _pending_
- **H2** — 
  - Falsifier: \`...\`
  - Result: _pending_
- **H3** — 
  - Falsifier: \`...\`
  - Result: _pending_

## 8. Next move

_The single, concrete next command — never empty during an active engagement._

\`\`\`bash
# example:
# bash scripts/timebox.sh 90 nmap -sU --top-ports 50 -oA $DIR/nmap/udp $TARGET
\`\`\`

## 9. Resume hint (for the next operator / LLM)

_If you have to hand off, write 2-3 lines here describing the current
state, the most promising path, and the single command to run next._

EOF
  echo "[+] Created: $DIR/ENGAGEMENT.md"
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
