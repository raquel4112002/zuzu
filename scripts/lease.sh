#!/usr/bin/env bash
# lease.sh — Exclusive-resource serialization for the swarm.
#
# WHY: parallel workers on the SAME live box collide on shared state and
# degrade each other — measured on real boxes:
#   * upload-queue : a pdfminer/converter watcher reprocesses every queued
#     file each pass; two uploaders stack the queue into a self-DoS (bedside).
#   * ssh-brute    : parallel guessing trips fail2ban/rate-limit → connection
#     resets for everyone (ReactorWatch).
#   * callback:<p> : two reverse shells can't bind the same listener port.
#   * target-rate  : some boxes throttle aggressively; cap concurrent noise.
#
# A worker that needs an exclusive resource acquires a lease FIRST. Others do
# parallel-safe work meanwhile, or wait. Read-only probes never need a lease.
#
# Atomic via `mkdir` (POSIX-atomic create-or-fail). Leases auto-expire so a
# crashed worker can't deadlock the swarm.
#
# Usage:
#   bash scripts/lease.sh acquire <resource> [--owner <id>] [--ttl <s>] [--wait <s>]
#   bash scripts/lease.sh release <resource> [--owner <id>]
#   bash scripts/lease.sh list
#   bash scripts/lease.sh gc            # drop expired leases
#
# Exit: acquire -> 0 got it / 1 busy (after --wait). release/list/gc -> 0.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
LDIR="$WS/state/leases"
mkdir -p "$LDIR"

now() { date +%s; }

gc() {
  local f res exp
  for f in "$LDIR"/*.lock; do
    [[ -d "$f" ]] || continue
    exp=$(cat "$f/expires" 2>/dev/null || echo 0)
    if [[ "$exp" =~ ^[0-9]+$ ]] && (( exp > 0 )) && (( $(now) > exp )); then
      res=$(basename "$f" .lock)
      rm -rf "$f" && echo "[lease] gc expired: $res" >&2
    fi
  done
}

reskey() { echo "$1" | tr -cd 'a-zA-Z0-9._:-' | tr ':' '_'; }

ACTION="${1:-}"; shift 2>/dev/null || true
case "$ACTION" in
  acquire)
    RES="${1:-}"; shift 2>/dev/null || true
    [[ -n "$RES" ]] || { echo "Usage: lease.sh acquire <resource> [--owner id] [--ttl s] [--wait s]"; exit 2; }
    OWNER="${HOSTNAME:-worker}-$$"; TTL=300; WAIT=0
    while [[ $# -gt 0 ]]; do case "$1" in
      --owner) OWNER="$2"; shift 2;; --ttl) TTL="$2"; shift 2;; --wait) WAIT="$2"; shift 2;;
      *) shift;; esac; done
    LOCK="$LDIR/$(reskey "$RES").lock"
    local_deadline=$(( $(now) + WAIT ))
    while :; do
      gc
      if mkdir "$LOCK" 2>/dev/null; then
        echo "$OWNER" > "$LOCK/owner"
        echo "$(( $(now) + TTL ))" > "$LOCK/expires"
        echo "$RES" > "$LOCK/resource"
        echo "🔒 lease ACQUIRED: $RES (owner=$OWNER ttl=${TTL}s)"
        exit 0
      fi
      (( $(now) >= local_deadline )) && break
      sleep 2
    done
    echo "⏳ lease BUSY: $RES held by $(cat "$LOCK/owner" 2>/dev/null) — do parallel-safe work instead." >&2
    exit 1
    ;;
  release)
    RES="${1:-}"; shift 2>/dev/null || true
    [[ -n "$RES" ]] || { echo "Usage: lease.sh release <resource> [--owner id]"; exit 2; }
    LOCK="$LDIR/$(reskey "$RES").lock"
    rm -rf "$LOCK" && echo "🔓 lease RELEASED: $RES"
    exit 0
    ;;
  list)
    gc
    shopt -s nullglob
    found=0
    for f in "$LDIR"/*.lock; do
      found=1
      printf "  %-22s owner=%-18s expires_in=%ss\n" \
        "$(cat "$f/resource" 2>/dev/null)" "$(cat "$f/owner" 2>/dev/null)" \
        "$(( $(cat "$f/expires" 2>/dev/null || echo 0) - $(now) ))"
    done
    (( found == 0 )) && echo "  (no active leases)"
    exit 0
    ;;
  gc) gc; exit 0;;
  *)
    echo "lease.sh — exclusive-resource serialization for the swarm"
    echo "Usage: lease.sh acquire <resource> [--owner id] [--ttl s] [--wait s] | release <resource> | list | gc"
    echo "Common resources: upload-queue  ssh-brute  callback:4444  target-rate"
    exit 2;;
esac
