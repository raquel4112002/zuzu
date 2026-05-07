#!/bin/bash
# zero.sh — The single first command for any new target.
#
# Designed for weak / open-source LLMs. One command, deterministic output:
#   1. Verifies network reachability
#   2. Quick port scan (top-1000 + version, timeboxed)
#   3. Fingerprints the service stack
#   4. Tells you EXACTLY which runbook or archetype to use next
#
# Usage:
#   bash scripts/zero.sh <target> [hostname]
#
# Example:
#   bash scripts/zero.sh 10.129.49.228
#   bash scripts/zero.sh 10.10.10.50 backdoor.htb
#
# This script never fails — it always tells you what to do next, even if
# nothing matches. Every output line is a directive, not prose.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"
HOSTNAME_HINT="${2:-}"

if [[ -z "$TARGET" ]]; then
  cat <<EOF
zero.sh — first-command handler for a new target

Usage:
  bash scripts/zero.sh <target-ip-or-host> [hostname]

What it does:
  1. Creates reports/<target>/ via new-target.sh
  2. Confirms network reachability
  3. Quick top-1000 nmap with service detection (timeboxed 60s)
  4. Fingerprints the service stack (Wing FTP? WordPress? Jenkins? AD?)
  5. Tells you exactly which runbook/archetype to follow next

Output is concise, deterministic, ready for an LLM to act on.
EOF
  exit 2
fi

# Sanitize target slug
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"

# Step 1 — folder structure
bash "$WS/scripts/new-target.sh" "$TARGET" "$HOSTNAME_HINT" >/dev/null

# Step 2 — reachability
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " 🎯 ZERO — initializing engagement on $TARGET"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "[1/4] Reachability check..."
if ping -c 1 -W 2 "$TARGET" >/dev/null 2>&1; then
  echo "      ✅ $TARGET is up (ICMP)"
else
  # ICMP may be filtered; try TCP probe to common ports
  if timeout 5 bash -c "</dev/tcp/$TARGET/80" 2>/dev/null \
     || timeout 5 bash -c "</dev/tcp/$TARGET/22" 2>/dev/null \
     || timeout 5 bash -c "</dev/tcp/$TARGET/443" 2>/dev/null; then
    echo "      ⚠️  ICMP blocked, but TCP responding"
  else
    echo "      ❌ Target unreachable. Check VPN / network. Aborting."
    exit 1
  fi
fi

# Step 3 — quick scan
echo ""
echo "[2/4] Quick port scan (top-1000, ≤ 90s)..."
mkdir -p "$DIR/nmap"
bash "$WS/scripts/timebox.sh" 90 \
  nmap -sC -sV --top-ports 1000 --min-rate 2000 \
  -oA "$DIR/nmap/zero-quick" "$TARGET" >/dev/null 2>&1
SCAN_FILE="$DIR/nmap/zero-quick.nmap"
if [[ ! -s "$SCAN_FILE" ]]; then
  echo "      ⚠️  Scan empty — target may need slower scan."
  echo "      Try manually: nmap -sS -sV -p- --min-rate 500 $TARGET"
  exit 1
fi

# Show open ports
OPEN_LINE=$(grep -E "^[0-9]+/tcp\s+open" "$SCAN_FILE" || true)
if [[ -z "$OPEN_LINE" ]]; then
  echo "      ⚠️  No open TCP ports in top-1000. Run -p- (full)."
  echo ""
  echo "    Suggested next:"
  echo "      bash $WS/scripts/timebox.sh 600 nmap -sS -p- --min-rate 1000 -oA $DIR/nmap/full $TARGET"
  exit 0
fi
echo "$OPEN_LINE" | sed 's/^/      /'

# Step 4 — Fingerprint
echo ""
echo "[3/4] Fingerprinting service stack..."

# Capture all banners + redirect targets
BANNERS=$(grep -E "(open|http-title|http-server|service)" "$SCAN_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')

# Hostname detection: try in order:
# 1. user-provided hint
# 2. HTTP redirect line ("Did not follow redirect to http://...")
# 3. Reverse DNS in nmap header ("Nmap scan report for hostname (ip)")
# 4. http-title that ends in .htb / .local / .lan
# 5. SSL cert common name
HTTP_REDIRECT=$(grep -oE "redirect to https?://[^[:space:]/]+" "$SCAN_FILE" | head -1 | sed 's|.*//||')
NMAP_RDNS=$(head -5 "$SCAN_FILE" | grep -oE "Nmap scan report for [a-z0-9.-]+\.([a-z]{2,})" | sed 's/Nmap scan report for //' | head -1)
SSL_CN=$(grep -oE "commonName=[a-zA-Z0-9.-]+" "$SCAN_FILE" | sed 's/commonName=//' | head -1)

if [[ -z "$HOSTNAME_HINT" ]]; then
  if [[ -n "$HTTP_REDIRECT" ]]; then
    HOSTNAME_HINT="$HTTP_REDIRECT"
    echo "      📌 Hostname detected from HTTP redirect: $HOSTNAME_HINT"
  elif [[ -n "$NMAP_RDNS" && "$NMAP_RDNS" != "$TARGET" ]]; then
    HOSTNAME_HINT="$NMAP_RDNS"
    echo "      📌 Hostname detected from rDNS: $HOSTNAME_HINT"
  elif [[ -n "$SSL_CN" ]]; then
    HOSTNAME_HINT="$SSL_CN"
    echo "      📌 Hostname detected from SSL CN: $HOSTNAME_HINT"
  fi
fi

# Probe HTTP for product strings on common ports + paths if port 80/443 open
HTTP_PRODUCT=""

probe_one() {
  # $1 = host header (or empty), $2 = path. Echoes any matched product string.
  local host_hdr="$1"
  local path="$2"
  local body
  if [[ -n "$host_hdr" ]]; then
    body=$(curl -s --max-time 4 -H "Host: $host_hdr" "http://$TARGET/$path" 2>/dev/null)
  else
    body=$(curl -s --max-time 4 "http://$TARGET/$path" 2>/dev/null)
  fi
  [[ -z "$body" ]] && return
  echo "$body" | grep -ioE "wing ftp server v[0-9.]+|wordpress|joomla|drupal|jenkins|gitlab|gitea|jira|confluence|teamcity|flowise|n8n|anythingllm|dify|nextcloud|owncloud|grafana|prometheus|kibana|elasticsearch|tomcat|argocd|drone|jellyfin|plex|nginx|apache" | head -1
}

if echo "$BANNERS" | grep -qE "80/tcp\s+open"; then
  # Build list of (host, path) probe candidates, most specific first
  CANDIDATES=()
  if [[ -n "$HOSTNAME_HINT" ]]; then
    for prefix in "" "ftp." "api." "admin." "portal." "app."; do
      for path in "" "login.html" "login" "signin" "administrator/"; do
        CANDIDATES+=("${prefix}${HOSTNAME_HINT}|${path}")
      done
    done
  fi
  # Always also try without host header
  for path in "" "login.html" "login" "signin" "wp-login.php" "administrator/" "index.php"; do
    CANDIDATES+=("|${path}")
  done

  GENERIC_HIT=""
  for combo in "${CANDIDATES[@]}"; do
    H="${combo%%|*}"
    P="${combo#*|}"
    HIT=$(probe_one "$H" "$P")
    [[ -z "$HIT" ]] && continue
    HIT_LOWER=$(echo "$HIT" | tr '[:upper:]' '[:lower:]')
    if [[ "$HIT_LOWER" != "nginx" && "$HIT_LOWER" != "apache" ]]; then
      HTTP_PRODUCT="$HIT"
      if [[ -n "$H" && "$H" != "$HOSTNAME_HINT" ]]; then
        echo "      📌 Found '$HIT' on $H"
        HOSTNAME_HINT="$H"
      fi
      break
    fi
    [[ -z "$GENERIC_HIT" ]] && GENERIC_HIT="$HIT"
  done
  [[ -z "$HTTP_PRODUCT" && -n "$GENERIC_HIT" ]] && HTTP_PRODUCT="$GENERIC_HIT"
fi

# Match-table — most specific first
MATCH=""
RUNBOOK=""
ARCHETYPE=""

if echo "$HTTP_PRODUCT" | grep -qiE "wing ftp server v7\.4\.[0-3]"; then
  MATCH="🎯 Wing FTP Server 7.4.3 (≤7.4.3 = vulnerable)"
  RUNBOOK="playbooks/runbooks/wing-ftp-rooted.md"
  ARCHETYPE="playbooks/archetypes/custom-ftp-or-file-server.md"
elif echo "$HTTP_PRODUCT" | grep -qiE "wing ftp"; then
  MATCH="🎯 Wing FTP Server (check version manually)"
  ARCHETYPE="playbooks/archetypes/custom-ftp-or-file-server.md"
elif echo "$HTTP_PRODUCT" | grep -qiE "(wordpress|joomla|drupal)"; then
  MATCH="🎯 CMS detected: $HTTP_PRODUCT"
  ARCHETYPE="playbooks/archetypes/cms-and-plugins.md"
elif echo "$HTTP_PRODUCT" | grep -qiE "(jenkins|gitlab|gitea|jira|confluence|teamcity|argocd|drone)"; then
  MATCH="🎯 DevOps tool: $HTTP_PRODUCT"
  ARCHETYPE="playbooks/archetypes/devops-tools.md"
elif echo "$HTTP_PRODUCT" | grep -qiE "(flowise|n8n|anythingllm|dify)"; then
  MATCH="🎯 AI orchestration platform: $HTTP_PRODUCT"
  ARCHETYPE="playbooks/archetypes/ai-orchestration.md"
elif echo "$BANNERS" | grep -qE "(88/tcp.*open|389/tcp.*open|445/tcp.*open|3268/tcp.*open|5985/tcp.*open)"; then
  MATCH="🎯 Active Directory / Windows target (Kerberos/LDAP/SMB visible)"
  ARCHETYPE="playbooks/archetypes/ad-windows-target.md"
elif echo "$BANNERS" | grep -qE "(21/tcp.*open|990/tcp.*open)"; then
  MATCH="🎯 FTP service detected"
  ARCHETYPE="playbooks/archetypes/custom-ftp-or-file-server.md"
elif echo "$BANNERS" | grep -qE "80/tcp.*open" && [[ -n "$HTTP_PRODUCT" ]]; then
  MATCH="🎯 Web server: $HTTP_PRODUCT"
  ARCHETYPE="playbooks/archetypes/webapp-with-login.md"
elif echo "$BANNERS" | grep -qE "80/tcp.*open"; then
  MATCH="🌐 Web service (no product fingerprint yet — investigate)"
  ARCHETYPE="playbooks/archetypes/webapp-with-login.md"
fi

# UDP/SNMP hint
SNMP_HINT=""
if echo "$BANNERS" | grep -qE "161/(udp|tcp)"; then
  SNMP_HINT="playbooks/archetypes/linux-snmp-host.md"
fi

if [[ -n "$MATCH" ]]; then
  echo "      $MATCH"
else
  echo "      ⚠️  No archetype match — fall back to generic recon."
fi

# Step 5 — Output the action plan
echo ""
echo "[4/4] Action plan"
echo "─────────────────────────────────────────────────────────────"
echo ""
if [[ -n "$RUNBOOK" ]]; then
  echo "  ✨ RUNBOOK MATCH (copy-paste, end-to-end):"
  echo "     ✅ $RUNBOOK"
  echo ""
  echo "  → Open this runbook NOW. It has every command + expected output."
  echo "  → Set TARGET=\"$TARGET\"${HOSTNAME_HINT:+ HOSTNAME=\"$HOSTNAME_HINT\"} at the top."
elif [[ -n "$ARCHETYPE" ]]; then
  echo "  📚 ARCHETYPE MATCH:"
  echo "     ✅ $ARCHETYPE"
  echo ""
  echo "  → Read this archetype. It lists fast checks, deep checks, and CVEs."
else
  echo "  📋 No archetype match — start generic recon."
  echo ""
  echo "  → Read: knowledge-base/llm-hacking-context.md"
  echo "  → Run:  bash scripts/source-dive.sh <repo> if app is open-source"
fi

if [[ -n "$SNMP_HINT" ]]; then
  echo ""
  echo "  📡 SNMP detected (UDP 161). Also check:"
  echo "     ✅ $SNMP_HINT"
fi

# Always-applicable hints
echo ""
echo "  🛠  Helpers always available:"
echo "     scripts/timebox.sh         (wrap brute-force commands)"
echo "     scripts/source-dive.sh     (grep open-source repos for unauth surface)"
echo "     scripts/walkthrough-search.sh   (HINTS for retired HTB boxes, no spoilers)"
echo ""
echo "  📂 Working folder: $DIR/"
echo "     └── nmap/zero-quick.{nmap,gnmap,xml}    (this scan, saved)"
echo "     └── notes.md                             (your running notes)"
echo "     └── README.md                            (target metadata)"
echo ""

# Special hints for known patterns
if [[ -n "$HOSTNAME_HINT" ]]; then
  echo "  📌 Add hostname to /etc/hosts:"
  echo "     echo '$TARGET $HOSTNAME_HINT' | sudo tee -a /etc/hosts"
  echo ""
fi

# Save the action plan to notes.md
{
  echo ""
  echo "## $(date '+%Y-%m-%d %H:%M') — zero.sh ran"
  echo ""
  echo "**Open ports:**"
  echo "$OPEN_LINE" | sed 's/^/    /'
  [[ -n "$HTTP_PRODUCT" ]] && echo "**HTTP product:** $HTTP_PRODUCT"
  [[ -n "$HOSTNAME_HINT" ]] && echo "**Hostname:** $HOSTNAME_HINT"
  [[ -n "$MATCH" ]] && echo "**Match:** $MATCH"
  [[ -n "$RUNBOOK" ]] && echo "**Runbook:** $RUNBOOK"
  [[ -n "$ARCHETYPE" ]] && echo "**Archetype:** $ARCHETYPE"
  echo ""
} >> "$DIR/notes.md"

echo "═══════════════════════════════════════════════════════════════"
echo " ✅ zero.sh complete — follow the action plan above."
echo "═══════════════════════════════════════════════════════════════"
