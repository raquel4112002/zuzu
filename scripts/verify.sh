#!/usr/bin/env bash
# verify.sh — Ground a claim against reality before it becomes "confirmed".
#
# Weak / open-source models hallucinate: they report creds that don't work,
# shells they don't have, hosts they can't reach. This script makes a claim
# CHEAP to check, so the evidence rule (hypotheses.sh result confirmed
# --evidence) points at a real, re-runnable test — not a vibe.
#
# Usage:
#   bash scripts/verify.sh cred <proto> <target> <user> <pass-or-hash>
#        proto: smb | winrm | ssh | ldap | mssql | rdp | ftp
#        pass-or-hash: plaintext, or an NTLM hash for -H (auto-detected)
#   bash scripts/verify.sh host <ip>            # reachable? (works through tunnels)
#   bash scripts/verify.sh flag <path>          # non-empty and flag-shaped?
#
# Exit 0 = verified true. Exit 1 = verified false / unreachable. Exit 2 = usage.
# Output is terse and copy-pasteable into --evidence notes.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
TB="$WS/scripts/timebox.sh"
have() { command -v "$1" >/dev/null 2>&1; }
tb() { if [[ -x "$TB" ]]; then bash "$TB" "$@"; else timeout "${1}s" "${@:2}"; fi; }

ACTION="${1:-}"; shift 2>/dev/null || true

is_ntlm() { [[ "$1" =~ ^[a-fA-F0-9]{32}(:[a-fA-F0-9]{32})?$ ]]; }

case "$ACTION" in
  cred)
    PROTO="${1:-}"; TARGET="${2:-}"; USER="${3:-}"; SECRET="${4:-}"
    [[ -n "$PROTO" && -n "$TARGET" && -n "$USER" ]] || { echo "usage: verify.sh cred <proto> <target> <user> <pass-or-hash>"; exit 2; }
    NXC=""; have nxc && NXC=nxc; [[ -z "$NXC" ]] && have netexec && NXC=netexec
    # Choose credential flag: -H for NTLM hash, -p for password.
    if is_ntlm "$SECRET"; then CREDFLAG=(-u "$USER" -H "$SECRET"); LABEL="hash"; else CREDFLAG=(-u "$USER" -p "$SECRET"); LABEL="pass"; fi
    case "$PROTO" in
      smb|winrm|ldap|mssql|rdp|ftp)
        [[ -n "$NXC" ]] || { echo "SKIP: nxc/netexec not installed"; exit 2; }
        OUT="$(tb 30 "$NXC" "$PROTO" "$TARGET" "${CREDFLAG[@]}" 2>&1)"
        echo "$OUT" | grep -qE '\[\+\]' && { echo "✅ VALID ($PROTO $USER/$LABEL): $(echo "$OUT" | grep -m1 '\[\+\]')"; exit 0; }
        echo "❌ INVALID ($PROTO $USER/$LABEL)"; echo "$OUT" | tail -2; exit 1;;
      ssh)
        if have sshpass && [[ "$LABEL" == "pass" ]]; then
          tb 25 sshpass -p "$SECRET" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no "$USER@$TARGET" 'id' 2>/dev/null \
            && { echo "✅ VALID (ssh $USER)"; exit 0; }
          echo "❌ INVALID (ssh $USER)"; exit 1
        else
          echo "SKIP: install sshpass, or test the ssh login manually"; exit 2
        fi;;
      *) echo "unknown proto: $PROTO"; exit 2;;
    esac;;
  host)
    IP="${1:-}"; [[ -n "$IP" ]] || { echo "usage: verify.sh host <ip>"; exit 2; }
    # nmap works through proxychains tunnels (-sT); ping often doesn't.
    if have nmap; then
      tb 30 nmap -sn -PE -PS22,80,443,445 "$IP" 2>/dev/null | grep -q "Host is up" \
        && { echo "✅ REACHABLE: $IP"; exit 0; }
      # fallback: a single TCP connect
    fi
    (echo > "/dev/tcp/$IP/445" || echo > "/dev/tcp/$IP/80" || echo > "/dev/tcp/$IP/22") 2>/dev/null \
      && { echo "✅ REACHABLE (tcp): $IP"; exit 0; }
    echo "❌ UNREACHABLE: $IP"; exit 1;;
  flag)
    P="${1:-}"; [[ -n "$P" ]] || { echo "usage: verify.sh flag <path>"; exit 2; }
    [[ -s "$P" ]] || { echo "❌ missing/empty: $P"; exit 1; }
    CONTENT="$(tr -d '[:space:]' < "$P")"
    if [[ "$CONTENT" =~ ^[a-fA-F0-9]{32}$ ]] || [[ "$CONTENT" =~ HTB\{ ]] || [[ "$CONTENT" =~ flag\{ ]]; then
      echo "✅ flag-shaped: $P (${#CONTENT} chars)"; exit 0
    fi
    echo "⚠️  $P is non-empty but NOT flag-shaped (32-hex or HTB{...}/flag{...}). Double-check it's real."; exit 1;;
  *)
    cat <<EOF
verify.sh — ground a claim before marking it confirmed.

  bash scripts/verify.sh cred <smb|winrm|ssh|ldap|mssql|rdp|ftp> <target> <user> <pass-or-hash>
  bash scripts/verify.sh host <ip>
  bash scripts/verify.sh flag <path>

Use the output as --evidence when calling hypotheses.sh result <id> confirmed.
EOF
    exit 2;;
esac
