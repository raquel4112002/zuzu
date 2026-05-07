#!/bin/bash
# timebox.sh — Hard time cap for any command.
# Forces models to abandon long-running brute-force / scan tools when they
# stop making progress. Prevents the "hydra for 5 minutes" failure mode
# observed in silentium.htb (2026-05-03) and WingData.htb (2026-05-07).
#
# Usage:
#   timebox.sh <seconds> <command...>
#
# Example:
#   timebox.sh 90 hydra -L users.txt -P rockyou.txt ssh://10.10.10.1
#   timebox.sh 60 gobuster dir -u http://target -w wordlist.txt
#   timebox.sh 30 nmap -sV target
#
# Returns:
#   - 0 if command succeeded inside the budget
#   - 124 if the budget was exhausted (timeout signaled)
#   - other: command's own exit code
#
# Default budgets if no time given (when called via known wrappers):
#   hydra/medusa/ncrack:    90s
#   gobuster/feroxbuster:   60s
#   ffuf/wfuzz:             60s
#   nmap (no -p-):          120s
#   nmap (-p-):             300s
#   nikto/nuclei:           180s
#   anything else:          120s

set -uo pipefail

DEFAULT_BUDGETS=(
  "hydra:90"
  "medusa:90"
  "ncrack:90"
  "patator:90"
  "crackmapexec:60"
  "netexec:60"
  "gobuster:60"
  "feroxbuster:60"
  "dirb:60"
  "dirbuster:60"
  "ffuf:60"
  "wfuzz:60"
  "nikto:180"
  "nuclei:180"
  "wpscan:180"
  "sqlmap:300"
)

usage() {
  cat <<EOF
timebox.sh — hard time cap wrapper

Usage:
  timebox.sh <seconds> <command> [args...]
  timebox.sh <command> [args...]   # auto-pick budget by command name

Reads default budgets from a built-in table; falls back to 120s.

Examples:
  timebox.sh 90 hydra -L u.txt -P p.txt ssh://10.10.10.1
  timebox.sh hydra -L u.txt -P p.txt ssh://10.10.10.1   # uses 90s default
  timebox.sh 30 nmap -sV 10.10.10.1
EOF
  exit 2
}

[[ $# -lt 1 ]] && usage

# First arg numeric? treat as explicit budget. Otherwise look up by cmd.
if [[ "$1" =~ ^[0-9]+$ ]]; then
  BUDGET="$1"
  shift
else
  CMD_NAME="$(basename "$1")"
  BUDGET=120
  for entry in "${DEFAULT_BUDGETS[@]}"; do
    name="${entry%%:*}"
    secs="${entry##*:}"
    if [[ "$CMD_NAME" == "$name" ]]; then
      BUDGET="$secs"
      break
    fi
  done
fi

[[ $# -lt 1 ]] && usage

START=$(date +%s)
echo "⏱  timebox: ${BUDGET}s budget for: $*" >&2

# Use SIGTERM after BUDGET, SIGKILL 5s later if needed
timeout --kill-after=5s --signal=TERM "${BUDGET}s" "$@"
RC=$?
END=$(date +%s)
ELAPSED=$((END - START))

if [[ $RC -eq 124 || $RC -eq 137 ]]; then
  echo "" >&2
  echo "⏱  timebox: BUDGET EXHAUSTED (${ELAPSED}s) — command was killed." >&2
  echo "⏱  timebox: $*" >&2
  echo "⏱  timebox: Move on. Try a different vector. Do NOT just rerun with a bigger wordlist." >&2
  echo "⏱  timebox: See knowledge-base/checklists/when-to-stop-enumerating.md" >&2
  exit 124
fi

if [[ $ELAPSED -gt $((BUDGET * 75 / 100)) ]]; then
  echo "⏱  timebox: completed in ${ELAPSED}s (>75% of budget) — consider this slow." >&2
fi

exit $RC
