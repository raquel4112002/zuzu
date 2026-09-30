#!/usr/bin/env bash
# recon-fast.sh — Same coverage as deep-recon, a fraction of the wall-time.
#
# deep-recon.sh runs the surface SERIALLY (full -p- 900s, then UDP, then web
# per port...) — that back-to-back stack is the bulk of a 40-70min recon. The
# lanes are independent, so here they run IN PARALLEL: a fast quick-scan learns
# the common ports first, then full-port / UDP / web / CVE lanes fire at once,
# each timeboxed. Then ONE prioritized reports/<slug>/recon-summary.md.
#
# It does NOT replace deep-recon.sh — that stays as the exhaustive fallback
# ("recon-fast left a gap → run deep-recon --force"). This is the default,
# fast first pass.
#
# Usage:
#   bash scripts/recon-fast.sh [<target>] [<hostname>] [--force]
#
# Reads the active target from state/orchestrator.json if <target> omitted.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"
TB="$WS/scripts/timebox.sh"
RECON_CVE="$WS/scripts/recon-cve.sh"

FORCE="no"; ARGS=()
for a in "$@"; do [[ "$a" == "--force" ]] && FORCE="yes" || ARGS+=("$a"); done
TARGET="${ARGS[0]:-}"; HOSTNAME_ARG="${ARGS[1]:-}"

if [[ -z "$TARGET" ]]; then
  [[ -f "$STATE" ]] && TARGET=$(python3 -c "import json;print(json.load(open('$STATE'))['target'])" 2>/dev/null)
fi
[[ -n "$TARGET" ]] || { echo "❌ No target given and none active. Usage: recon-fast.sh <target> [hostname]"; exit 1; }
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"; mkdir -p "$DIR"/{nmap,web,cve}
have() { command -v "$1" >/dev/null 2>&1; }
tb() { if [[ -x "$TB" ]]; then bash "$TB" "$@"; else local s="$1"; shift; timeout "$s" "$@"; fi; }
log() { echo "[recon-fast] $*"; }

# best-effort phase stamp
bash "$WS/scripts/phase.sh" recon >/dev/null 2>&1 || true

have nmap || { echo "❌ nmap required."; exit 1; }
SUDO=""; if [[ $EUID -ne 0 ]] && sudo -n true 2>/dev/null; then SUDO="sudo -n"; fi

echo "═══════════════════════════════════════════════════════════════"
echo " ⚡ recon-fast — $TARGET ${HOSTNAME_ARG:+($HOSTNAME_ARG)}  [parallel]"
echo "═══════════════════════════════════════════════════════════════"

# ── STEP 0: quick scan so the web/CVE lanes don't wait for full -p- ──────────
QUICK="$DIR/nmap/quick"
if [[ "$FORCE" == "yes" || ! -s "$QUICK.gnmap" ]]; then
  log "quick top-1000 -sCV (120s)…"
  tb 120 nmap -sCV --top-ports 1000 --min-rate 2000 -oA "$QUICK" "$TARGET" >/dev/null 2>&1 || true
fi
parse_ports() { grep -oE '[0-9]+/open/tcp' "$1" 2>/dev/null | cut -d/ -f1 | sort -un | tr '\n' ',' | sed 's/,$//'; }
QPORTS="$(parse_ports "$QUICK.gnmap")"
log "quick open TCP: ${QPORTS:-none}"

# web ports = those whose -sCV line mentions http/ssl (plus 80/443 if open)
web_ports_from() {
  grep -iE '^[0-9]+/tcp +open' "$1" 2>/dev/null | grep -iE 'http|ssl' | grep -oE '^[0-9]+' | sort -un
}
WEB_PORTS="$(web_ports_from "$QUICK.nmap" | tr '\n' ' ')"
[[ -z "$WEB_PORTS" ]] && for p in 80 443 8080 8443; do echo "$QPORTS" | tr ',' '\n' | grep -qx "$p" && WEB_PORTS+="$p "; done
log "web ports: ${WEB_PORTS:-none}"

# ── Launch independent lanes in the background ───────────────────────────────
PIDS=()

# LANE 1: full TCP -p- then -sCV on the full set
lane_fullport() {
  if [[ "$FORCE" == "yes" || ! -s "$DIR/nmap/allports.gnmap" ]]; then
    tb 900 nmap -p- --min-rate 3000 -oA "$DIR/nmap/allports" "$TARGET" >/dev/null 2>&1 || true
  fi
  local allp; allp="$(parse_ports "$DIR/nmap/allports.gnmap")"
  if [[ -n "$allp" && ( "$FORCE" == "yes" || ! -s "$DIR/nmap/services.gnmap" ) ]]; then
    tb 600 nmap -sCV -p "$allp" -oA "$DIR/nmap/services" "$TARGET" >/dev/null 2>&1 || true
  fi
  echo "$allp" > "$DIR/nmap/.allports.txt"
}
lane_fullport & PIDS+=($!)

# LANE 2: UDP top-100 (needs root; skip cleanly otherwise)
lane_udp() {
  [[ -n "$SUDO" || $EUID -eq 0 ]] || { echo "(udp skipped: no non-interactive sudo)" > "$DIR/nmap/udp.skip"; return; }
  [[ "$FORCE" == "yes" || ! -s "$DIR/nmap/udp.gnmap" ]] || return
  tb 300 $SUDO nmap -sU --top-ports 100 --min-rate 1000 -oA "$DIR/nmap/udp" "$TARGET" >/dev/null 2>&1 || true
}
lane_udp & PIDS+=($!)

# LANE 3: web enumeration per known web port (whatweb + headers + dirs + vhost)
lane_web() {
  local WL=""
  for w in /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
           /usr/share/seclists/Discovery/Web-Content/common.txt \
           /usr/share/wordlists/dirb/common.txt; do
    [[ -f "$w" ]] && { WL="$w"; break; }
  done
  local VWL=""
  for v in /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
           /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt; do
    [[ -f "$v" ]] && { VWL="$v"; break; }
  done
  for port in $WEB_PORTS; do
    local scheme="http"; [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
    local host="${HOSTNAME_ARG:-$TARGET}"
    local base="$scheme://$host:$port"; [[ "$port" == "80" || "$port" == "443" ]] && base="$scheme://$host"
    local pd="$DIR/web/$port"; mkdir -p "$pd"
    ( have whatweb && tb 90 whatweb -a3 --color=never "$base" > "$pd/whatweb.txt" 2>/dev/null ) &
    ( curl -sk -I --max-time 15 "$base" > "$pd/headers.txt" 2>/dev/null ) &
    if have feroxbuster && [[ -n "$WL" ]]; then
      local tls=""; [[ "$scheme" == "https" ]] && tls="-k"
      ( tb 300 feroxbuster -u "$base" -w "$WL" $tls -x php,html,txt -q -o "$pd/ferox.txt" >/dev/null 2>&1 ) &
    elif have gobuster && [[ -n "$WL" ]]; then
      ( tb 300 gobuster dir -u "$base" -w "$WL" -q -o "$pd/gobuster.txt" >/dev/null 2>&1 ) &
    fi
    if [[ -n "$HOSTNAME_ARG" && -n "$VWL" ]] && have ffuf; then
      ( tb 180 ffuf -u "$base" -H "Host: FUZZ.$HOSTNAME_ARG" -w "$VWL" -ac -of json -o "$pd/vhosts.json" >/dev/null 2>&1 ) &
    fi
    wait
  done
}
lane_web & PIDS+=($!)

# LANE 4: CVE lookup per product+version from the quick -sCV
lane_cve() {
  [[ -x "$RECON_CVE" && -s "$QUICK.nmap" ]] || return
  # extract "product version" tokens, e.g. "nginx 1.24.0", "OpenSSH 9.6p1"
  grep -iE '^[0-9]+/tcp +open' "$QUICK.nmap" 2>/dev/null \
    | sed -E 's/^[0-9]+\/tcp +open +[^ ]+ +//' \
    | grep -oE '[A-Za-z][A-Za-z0-9._+-]* [0-9][0-9A-Za-z._-]+' | sort -u | head -8 \
    | while IFS= read -r pv; do
        [[ -n "$pv" ]] || continue
        local safe; safe="$(echo "$pv" | tr ' /' '__' | tr -cd 'A-Za-z0-9._-')"
        tb 60 bash "$RECON_CVE" "$pv" > "$DIR/cve/$safe.txt" 2>/dev/null || true
      done
}
lane_cve & PIDS+=($!)

log "lanes running (fullport, udp, web, cve) — waiting…"
for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
log "all lanes done."

# ── Merge: if -p- found NEW ports beyond the quick scan, note them ───────────
ALLP="$(cat "$DIR/nmap/.allports.txt" 2>/dev/null || echo "")"
NEWP=""
for p in $(echo "$ALLP" | tr ',' ' '); do
  echo "$QPORTS" | tr ',' '\n' | grep -qx "$p" || NEWP+="$p "
done

# ── Build the one file the model reads ───────────────────────────────────────
python3 - "$DIR" "$TARGET" "$HOSTNAME_ARG" "$QPORTS" "$ALLP" "$NEWP" "$WEB_PORTS" > "$DIR/recon-summary.md" <<'PY'
import sys, os, glob, re
DIR, TARGET, HOST, QPORTS, ALLP, NEWP, WEBP = sys.argv[1:8]
def read(p, n=0):
    try:
        t = open(p, errors="ignore").read()
        return t if not n else "\n".join(t.splitlines()[:n])
    except Exception:
        return ""
out = []
out.append(f"# recon-summary — {TARGET}" + (f" ({HOST})" if HOST else ""))
out.append("\n> Fast parallel pass (recon-fast.sh). Gaps? `deep-recon.sh --force`.\n")
out.append("## Open TCP ports")
out.append(f"- quick top-1000: `{QPORTS or '—'}`")
out.append(f"- full -p-: `{ALLP or '(pending/none)'}`")
if NEWP.strip():
    out.append(f"- ⚠ **NEW ports only found by -p-** (enumerate these!): `{NEWP.strip()}`")
# services
svc = read(os.path.join(DIR, "nmap", "services.nmap")) or read(os.path.join(DIR, "nmap", "quick.nmap"))
open_lines = [l for l in svc.splitlines() if re.match(r'^\d+/tcp +open', l)]
if open_lines:
    out.append("\n## Services (-sCV)")
    out += [f"- `{l.strip()}`" for l in open_lines]
# web
if WEBP.strip():
    out.append("\n## Web")
    for port in WEBP.split():
        pd = os.path.join(DIR, "web", port)
        ww = read(os.path.join(pd, "whatweb.txt")).strip()
        out.append(f"\n### :{port}")
        if ww: out.append(f"- whatweb: {ww[:300]}")
        fx = os.path.join(pd, "ferox.txt"); gb = os.path.join(pd, "gobuster.txt")
        hits = read(fx) or read(gb)
        if hits:
            lines = [l for l in hits.splitlines() if l.strip()][:25]
            out.append("- dir hits:")
            out += [f"    {l.strip()}" for l in lines]
        vh = os.path.join(pd, "vhosts.json")
        if os.path.exists(vh) and os.path.getsize(vh) > 2:
            out.append(f"- vhosts: see web/{port}/vhosts.json")
# cve
cves = glob.glob(os.path.join(DIR, "cve", "*.txt"))
hot = []
for c in cves:
    t = read(c)
    if re.search(r'CVE-\d{4}-\d+', t):
        first = next((l for l in t.splitlines() if 'CVE-' in l), '')
        hot.append(f"- {os.path.basename(c)[:-4]}: {first.strip()[:160]}")
if hot:
    out.append("\n## CVE candidates (recon-cve, verify before trusting)")
    out += hot[:20]
out.append("\n## Suggested first bets (EV order)")
out.append("1. If a product+version maps to a known CVE above → recon-poc.sh + drive it FIRST.")
out.append("2. Web with a login/app → source-dive the framework; check default/weak creds.")
out.append("3. Any NEW -p- port → fingerprint it before anything else.")
out.append("4. Timebox each vector; don't rabbit-hole (see AGENTS.md R16 / THINK.md).")
print("\n".join(out))
PY

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[+] reports/$SLUG/recon-summary.md   ← read this first"
[[ -n "$NEWP" ]] && echo "[!] -p- found NEW ports beyond quick scan: $NEWP"
echo "═══════════════════════════════════════════════════════════════"
