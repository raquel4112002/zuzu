#!/usr/bin/env bash
# shell-batch.sh — Stop paying one request per command.
#
# The cohort.htb foothold was a one-shot primitive (a new marimo WS per
# command). Running enumeration one command at a time turned a 10-minute job
# into 193 requests and ~13 USD. Two fixes, both here:
#
#   --wrap   : fold MANY commands into ONE payload you send in a single exec.
#              Read commands from stdin (one per line). Blank lines and
#              lines starting with # are ignored. Each command's output is
#              fenced with a marker so you can parse it back apart.
#
#   --persist: emit a target-side bootstrap that turns ANY one-shot exec
#              primitive into a PERSISTENT shell (a FIFO + a backgrounded
#              interactive sh). cwd, env and shell variables survive between
#              commands, and each command is one write, not one new process.
#
# Usage:
#   printf '%s\n' 'id' 'sudo -n -l' 'ls -la /opt' | bash scripts/shell-batch.sh --wrap
#   bash scripts/shell-batch.sh --persist            # prints bootstrap + how to drive it
#
# Golden rule: recon and enumeration are ALWAYS batched. You only need an
# interactive shell for things that genuinely require state (a sudo prompt,
# an editor, an exploit that reads stdin). For everything else: --wrap.

set -uo pipefail

MODE="${1:---wrap}"

case "$MODE" in
  --wrap|"")
    # Read commands from stdin, emit a single sh -c payload.
    cmds=()
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      cmds+=("$line")
    done
    if [[ ${#cmds[@]} -eq 0 ]]; then
      echo "No commands on stdin. Example:" >&2
      echo "  printf '%s\\n' 'id' 'sudo -n -l' | bash scripts/shell-batch.sh --wrap" >&2
      exit 2
    fi
    # Build: sh -c 'cmd1; echo <MARK 1>; cmd2; echo <MARK 2>; ...'
    payload="sh -c '"
    i=0
    for c in "${cmds[@]}"; do
      i=$((i+1))
      # escape single quotes for embedding inside the single-quoted sh -c
      esc=${c//\'/\'\\\'\'}
      payload+="echo \"===[ $i ] \$ ${esc//\"/\\\"} ===\"; ${esc}; "
    done
    payload+="echo ===[ END ]==='"
    printf '%s\n' "$payload"
    echo "" >&2
    echo "▶ Send the line above to the target in ONE exec call. ${#cmds[@]} commands, 1 request." >&2
    ;;

  --persist)
    FIFO="${2:-/tmp/.zsh_$$}"
    OUT="${FIFO}.o"
    cat <<EOF
# ── Persistent-shell bootstrap (run ONCE on the target, in one exec) ──
rm -f $FIFO $OUT; mkfifo $FIFO
( setsid sh -i <$FIFO >$OUT 2>&1 & ) 2>/dev/null
sleep 1; echo "[persist] shell up: write cmds to $FIFO, read output from $OUT"

# ── Then, per command (each is ONE cheap write + read, state persists) ──
#   printf '%s\n' 'cd /opt && ls -la'   > $FIFO ; sleep 1; tail -c 4000 $OUT
#   printf '%s\n' 'export X=1; echo \$X' > $FIFO ; sleep 1; tail -c 4000 $OUT
#
# cwd, env and variables survive between writes because it is ONE shell.
# Batch where you can (see: bash scripts/shell-batch.sh --wrap); use this
# only when you need real interactive state.
# Tear down when done:  rm -f $FIFO $OUT
EOF
    ;;

  -h|--help)
    sed -n '2,30p' "$0"
    ;;
  *)
    echo "Unknown mode: $MODE (use --wrap | --persist)"; exit 2;;
esac
