#!/usr/bin/env bash
# Zuzu Bootstrap Script — Recreates the hacking environment on a fresh Kali machine
# Usage: bash scripts/bootstrap.sh

set -e

echo "🐱‍💻 Zuzu Bootstrap — Setting up the perfect hacking nest..."
echo ""

# ─── 1. System update ─────────────────────────────────────────
echo "[1/6] Updating system..."
sudo apt update -qq

# ─── 2. Essential Kali tools ──────────────────────────────────
echo "[2/6] Installing essential tools..."
sudo apt install -y \
  nmap masscan rustscan \
  subfinder amass gobuster feroxbuster ffuf dirsearch \
  nikto nuclei whatweb wafw00f \
  sqlmap wpscan \
  hydra john hashcat medusa \
  enum4linux smbclient crackmapexec evil-winrm \
  bloodhound \
  seclists wordlists \
  responder bettercap \
  sslscan testssl.sh \
  dnsrecon dnsenum fierce \
  netdiscover \
  wireshark tshark tcpdump \
  proxychains4 chisel \
  python3 python3-pip \
  git curl wget jq \
  rlwrap socat

# ─── 3. Python packages ──────────────────────────────────────
echo "[3/6] Installing Python packages..."
pip install --break-system-packages tavily-python impacket

# ─── 4. Wordlists ────────────────────────────────────────────
echo "[4/6] Checking wordlists..."
if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
  echo "  Decompressing rockyou.txt..."
  sudo gunzip /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
fi

# ─── 5. ClawHub skills ───────────────────────────────────────
echo "[5/6] Installing ClawHub skills..."
if command -v clawhub &>/dev/null; then
  cd "$(dirname "$0")/.."
  clawhub install cybersec-helper 2>/dev/null || true
  clawhub install upstream-recon 2>/dev/null || true
  clawhub install network-device-scanner --force 2>/dev/null || true
  clawhub install git-secrets-scanner --force 2>/dev/null || true
  clawhub install docker-essentials 2>/dev/null || true
  clawhub install system-info 2>/dev/null || true
  clawhub install web-browsing 2>/dev/null || true
  clawhub install stealth-browser --force 2>/dev/null || true
  clawhub install tavily-search-pro 2>/dev/null || true
else
  echo "  ⚠️  clawhub not installed. Run: npm i -g clawhub"
fi

# ─── 6. Directory structure ───────────────────────────────────
echo "[6/6] Ensuring directory structure..."
mkdir -p reports memory knowledge-base playbooks templates scripts

echo ""
echo "✅ Bootstrap complete! Zuzu's nest is ready."
echo ""
echo "⚠️  Remember to set these environment variables:"
echo "  export TAVILY_API_KEY='your-tavily-key'"
echo ""
echo "🐱‍💻 Let's hack."
