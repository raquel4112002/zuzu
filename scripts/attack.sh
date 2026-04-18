#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# ZUZU ATTACK LAUNCHER
# ═══════════════════════════════════════════════════════════════
# This script automates the first steps of any engagement.
# Even a dumb model just needs to run this and follow the output.
#
# Usage:
#   bash scripts/attack.sh <target> [type]
#
# Types: web, network, ad, api, cloud, wireless, full
# Default: full (runs recon + suggests next steps)
#
# Examples:
#   bash scripts/attack.sh 10.10.10.1
#   bash scripts/attack.sh example.com web
#   bash scripts/attack.sh 192.168.1.0/24 network
# ═══════════════════════════════════════════════════════════════

set -e

TARGET="${1}"
TYPE="${2:-full}"
REPORT_DIR="$(cd "$(dirname "$0")/.." && pwd)/reports"
RECON_DIR="$REPORT_DIR/${TARGET//\//-}-recon"

if [ -z "$TARGET" ]; then
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║  ZUZU ATTACK LAUNCHER 🐱‍💻                          ║"
  echo "╠══════════════════════════════════════════════════════╣"
  echo "║  Usage: bash scripts/attack.sh <target> [type]      ║"
  echo "║                                                      ║"
  echo "║  Types:                                              ║"
  echo "║    web      - Web application pentest                ║"
  echo "║    network  - Network/infrastructure pentest         ║"
  echo "║    ad       - Active Directory attack                ║"
  echo "║    api      - API security testing                   ║"
  echo "║    cloud    - Cloud environment attack               ║"
  echo "║    wireless - Wireless network attack                ║"
  echo "║    full     - Full recon + auto-detect (default)     ║"
  echo "║                                                      ║"
  echo "║  Examples:                                           ║"
  echo "║    bash scripts/attack.sh 10.10.10.1                 ║"
  echo "║    bash scripts/attack.sh example.com web            ║"
  echo "║    bash scripts/attack.sh 192.168.1.0/24 network     ║"
  echo "╚══════════════════════════════════════════════════════╝"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  🐱‍💻 ZUZU ATTACK LAUNCHER                          ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Target: $TARGET"
echo "║  Type:   $TYPE"
echo "║  Output: $RECON_DIR"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Create output directory
mkdir -p "$RECON_DIR"

# ─── PHASE 1: Initial Recon ──────────────────────────────────
echo "═══ PHASE 1: INITIAL RECON ═══"
echo ""

# Check if target is IP or domain
if echo "$TARGET" | grep -qP '^\d+\.\d+\.\d+\.\d+'; then
  IS_IP=true
  echo "[*] Target is an IP address"
else
  IS_IP=false
  echo "[*] Target is a domain"

  # DNS lookup
  echo "[*] Resolving DNS..."
  dig +short "$TARGET" > "$RECON_DIR/dns-resolve.txt" 2>/dev/null || true
  cat "$RECON_DIR/dns-resolve.txt"
  echo ""

  # Subdomain enumeration (if domain)
  if command -v subfinder &>/dev/null; then
    echo "[*] Enumerating subdomains with subfinder..."
    subfinder -d "$TARGET" -silent -o "$RECON_DIR/subdomains.txt" 2>/dev/null || true
    SUB_COUNT=$(wc -l < "$RECON_DIR/subdomains.txt" 2>/dev/null || echo 0)
    echo "[+] Found $SUB_COUNT subdomains"
    echo ""
  fi
fi

# ─── PHASE 2: Port Scan ──────────────────────────────────────
echo "═══ PHASE 2: PORT SCAN ═══"
echo ""

if echo "$TARGET" | grep -q '/'; then
  # Subnet — ping sweep first
  echo "[*] Subnet detected — running ping sweep..."
  nmap -sn "$TARGET" -oG "$RECON_DIR/ping-sweep.txt" 2>/dev/null || true
  HOSTS=$(grep "Up" "$RECON_DIR/ping-sweep.txt" 2>/dev/null | wc -l)
  echo "[+] Found $HOSTS live hosts"
  grep "Up" "$RECON_DIR/ping-sweep.txt" 2>/dev/null | awk '{print $2}' > "$RECON_DIR/live-hosts.txt"
  cat "$RECON_DIR/live-hosts.txt"
  echo ""
  echo "[*] Running service scan on live hosts..."
  nmap -sV -sC -iL "$RECON_DIR/live-hosts.txt" -oA "$RECON_DIR/nmap-services" 2>/dev/null || true
else
  # Single target — full scan
  echo "[*] Quick port scan (top 1000)..."
  nmap -sV -sC -oA "$RECON_DIR/nmap-quick" "$TARGET" 2>/dev/null || true

  echo "[*] Full port scan (all 65535)..."
  nmap -sS -p- --min-rate 3000 -oA "$RECON_DIR/nmap-full" "$TARGET" 2>/dev/null || true

  # Extract open ports
  grep "^[0-9]" "$RECON_DIR/nmap-quick.nmap" 2>/dev/null | grep "open" > "$RECON_DIR/open-ports.txt" || true
fi

echo ""
echo "[+] Open ports found:"
cat "$RECON_DIR/open-ports.txt" 2>/dev/null || echo "(check nmap output files)"
echo ""

# ─── PHASE 3: Service Detection & Suggestions ────────────────
echo "═══ PHASE 3: ANALYSIS & NEXT STEPS ═══"
echo ""

# Detect what services are running and suggest next steps
PORTS=$(cat "$RECON_DIR/open-ports.txt" 2>/dev/null || true)

echo "╔══════════════════════════════════════════════════════╗"
echo "║  📋 RECOMMENDED NEXT STEPS                          ║"
echo "╠══════════════════════════════════════════════════════╣"

if echo "$PORTS" | grep -q "80\|443\|8080\|8443"; then
  echo "║  🌐 WEB DETECTED — Read these files:                ║"
  echo "║    → playbooks/web-app-pentest.md                    ║"
  echo "║    → knowledge-base/mitre-attack/techniques/         ║"
  echo "║      web-exploitation.md                             ║"
  echo "║    → knowledge-base/checklists/owasp-top10.md        ║"
  echo "║                                                      ║"
  echo "║  Quick commands to run next:                         ║"
  echo "║    whatweb http://$TARGET"
  echo "║    nikto -h http://$TARGET"
  echo "║    ffuf -u http://$TARGET/FUZZ -w /usr/share/        ║"
  echo "║      seclists/Discovery/Web-Content/common.txt       ║"
  echo "║    nuclei -u http://$TARGET -severity critical,high  ║"
  echo "║                                                      ║"

  # Auto-run whatweb
  echo "[*] Running whatweb..."
  whatweb -a 3 "http://$TARGET" > "$RECON_DIR/whatweb.txt" 2>/dev/null || true
  cat "$RECON_DIR/whatweb.txt"
  echo ""
fi

if echo "$PORTS" | grep -q "445\|139"; then
  echo "║  📁 SMB DETECTED — Read these files:                ║"
  echo "║    → knowledge-base/checklists/                      ║"
  echo "║      enumeration-checklist.md (SMB section)          ║"
  echo "║    → knowledge-base/mitre-attack/techniques/         ║"
  echo "║      credential-access-ad.md                         ║"
  echo "║                                                      ║"
  echo "║  Quick commands:                                     ║"
  echo "║    enum4linux -a $TARGET"
  echo "║    smbclient -L //$TARGET -N"
  echo "║    crackmapexec smb $TARGET"
  echo "║                                                      ║"

  # Auto-run enum4linux
  echo "[*] Running enum4linux..."
  enum4linux -a "$TARGET" > "$RECON_DIR/enum4linux.txt" 2>/dev/null || true
fi

if echo "$PORTS" | grep -q "^22/"; then
  echo "║  🔑 SSH DETECTED                                    ║"
  echo "║    → Try default creds / brute force                 ║"
  echo "║    hydra -l root -P /usr/share/wordlists/            ║"
  echo "║      rockyou.txt ssh://$TARGET"
  echo "║                                                      ║"
fi

if echo "$PORTS" | grep -q "^21/"; then
  echo "║  📂 FTP DETECTED                                    ║"
  echo "║    → Try anonymous login: ftp $TARGET"
  echo "║    → Brute force: hydra -l anonymous -P wordlist     ║"
  echo "║      ftp://$TARGET"
  echo "║                                                      ║"
fi

if echo "$PORTS" | grep -q "3389"; then
  echo "║  🖥️ RDP DETECTED                                    ║"
  echo "║    → xfreerdp /v:$TARGET /u:admin /p:pass"
  echo "║    → Brute force: hydra -l admin -P rockyou.txt      ║"
  echo "║      rdp://$TARGET"
  echo "║                                                      ║"
fi

if echo "$PORTS" | grep -q "88\|389\|636\|5985"; then
  echo "║  🏰 ACTIVE DIRECTORY DETECTED — Read these files:   ║"
  echo "║    → knowledge-base/checklists/                      ║"
  echo "║      ad-attack-checklist.md                          ║"
  echo "║    → knowledge-base/mitre-attack/techniques/         ║"
  echo "║      credential-access-ad.md                         ║"
  echo "║                                                      ║"
fi

if echo "$PORTS" | grep -q "3306\|5432\|1433\|1521\|27017"; then
  echo "║  🗄️ DATABASE DETECTED                               ║"
  echo "║    → Try default creds                               ║"
  echo "║    → If web app found, try SQLi:                     ║"
  echo "║      sqlmap -u 'http://$TARGET/page?id=1' --batch    ║"
  echo "║                                                      ║"
fi

echo "║                                                      ║"
echo "║  📝 ALWAYS: Write findings to reports/ using          ║"
echo "║     templates/attack-report-template.md               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "═══ RECON COMPLETE ═══"
echo "Results saved to: $RECON_DIR/"
echo ""
ls -la "$RECON_DIR/"
