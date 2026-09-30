#!/usr/bin/env bash
# deep-recon.sh — The "depth floor" enumeration, done FOR the model.
#
# Kills the #1 weak-model failure mode on Hard/Insane boxes: declaring
# "stuck" before the surface was actually explored (stop-gate C1 with only
# 3 falsifications). See knowledge-base/checklists/hard-box-playbook.md §2.
#
# It runs the full enumeration surface deterministically — every stage
# TIMEBOXED (scripts/timebox.sh) and IDEMPOTENT (skips a stage whose output
# already exists; --force redoes) — then writes ONE prioritized summary the
# model only has to READ: reports/<slug>/recon-summary.md.
#
# Usage:
#   bash scripts/deep-recon.sh [<target>] [<hostname>] [--force]
#
# If <target> is omitted, the active target is read from
# state/orchestrator.json (like hypotheses.sh does).
#
# Examples:
#   bash scripts/deep-recon.sh                       # active target
#   bash scripts/deep-recon.sh 10.129.49.228
#   bash scripts/deep-recon.sh 10.10.10.50 airtouch.htb
#   bash scripts/deep-recon.sh 10.10.10.50 airtouch.htb --force
#
# Never hard-fails on a missing tool: it checks with `command -v`, warns,
# and skips. It NEVER overwrites surface.md — instead it tells you (in the
# printed output) to fold recon-summary.md into surface.md + the bank.

set -uo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$WS/state/orchestrator.json"
TIMEBOX="$WS/scripts/timebox.sh"
RECON_CVE="$WS/scripts/recon-cve.sh"

# ── Arg parsing ───────────────────────────────────────────────────────────
FORCE="no"
POSARGS=()
for a in "$@"; do
  case "$a" in
    --force|-f) FORCE="yes" ;;
    -h|--help)
      cat <<EOF
deep-recon.sh — automatic depth-floor enumeration + prioritized summary

Usage:
  bash scripts/deep-recon.sh [<target>] [<hostname>] [--force]

If <target> is omitted, reads the active target from state/orchestrator.json.

Stages (each timeboxed + idempotent):
  1. Full TCP (-p-) then -sCV on the open ports
  2. UDP top-100
  3. Per web port: whatweb + curl -I, dir brute, vhost fuzz (if hostname known)
  4. Per product+version: recon-cve.sh
  5. SMB / LDAP / SNMP light anon checks

Writes reports/<slug>/recon-summary.md. Never overwrites surface.md.
Use --force to redo stages whose output already exists.
EOF
      exit 2 ;;
    *) POSARGS+=("$a") ;;
  esac
done

TARGET="${POSARGS[0]:-}"
HOSTNAME_HINT="${POSARGS[1]:-}"

# ── Resolve target (arg > orchestrator state) ─────────────────────────────
if [[ -z "$TARGET" ]]; then
  if [[ -f "$STATE_FILE" ]]; then
    TARGET=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['target'])" 2>/dev/null || echo "")
  fi
  if [[ -z "$TARGET" ]]; then
    echo "❌ No target given and none in $STATE_FILE."
    echo "   Usage: bash scripts/deep-recon.sh [<target>] [<hostname>] [--force]"
    echo "   Or start an engagement first: bash scripts/pentest.sh <target>"
    exit 1
  fi
  echo "ℹ️  No target arg — using active target from orchestrator: $TARGET"
fi

# ── SLUG sanitize + folder layout (matches new-target.sh) ─────────────────
SLUG="$(echo "$TARGET" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"
mkdir -p "$DIR"/{nmap,web,cve}
SUMMARY="$DIR/recon-summary.md"

# ── Helpers ───────────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

# skip_done <file> → 0 (skip) when file exists non-empty and not --force
skip_done() { [[ "$FORCE" == "no" && -s "$1" ]]; }

warn() { echo "      ⚠️  $*"; }

# tb <seconds> <cmd...> — timebox wrapper (falls back to plain timeout)
tb() {
  local secs="$1"; shift
  if [[ -x "$TIMEBOX" ]]; then
    bash "$TIMEBOX" "$secs" "$@"
  else
    timeout --kill-after=5s "${secs}s" "$@"
  fi
}

# Derive a base domain (last two DNS labels) from a hostname string
base_domain() {
  local h="$1"
  # strip protocol / path if any
  h="${h#*://}"; h="${h%%/*}"
  local n; n=$(echo "$h" | awk -F. '{print NF}')
  if (( n >= 2 )); then
    echo "$h" | awk -F. '{print $(NF-1)"."$NF}'
  else
    echo "$h"
  fi
}

# ── Wordlists (first that exists wins) ────────────────────────────────────
pick_wordlist() {
  for w in "$@"; do [[ -f "$w" ]] && { echo "$w"; return; }; done
}
DIR_WL="$(pick_wordlist \
  /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
  /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt \
  /usr/share/wordlists/dirb/common.txt)"
VHOST_WL="$(pick_wordlist \
  /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  /usr/share/seclists/Discovery/DNS/namelist.txt)"

# ── Hostname / base domain resolution ─────────────────────────────────────
# Prefer the arg; otherwise look the IP up in /etc/hosts (the .htb hostname).
if [[ -z "$HOSTNAME_HINT" ]]; then
  ETC_HOST=$(grep -E "^[[:space:]]*$TARGET([[:space:]]|$)" /etc/hosts 2>/dev/null \
    | grep -oiE '[a-z0-9.-]+\.(htb|local|lan|thm|box)' | head -1 || true)
  [[ -n "$ETC_HOST" ]] && HOSTNAME_HINT="$ETC_HOST"
fi
BASE_DOMAIN=""
[[ -n "$HOSTNAME_HINT" ]] && BASE_DOMAIN="$(base_domain "$HOSTNAME_HINT")"

# ── Banner ────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " 🔬 DEEP-RECON — depth floor for $TARGET${HOSTNAME_HINT:+ ($HOSTNAME_HINT)}"
echo "═══════════════════════════════════════════════════════════════"
echo "   Working folder : reports/$SLUG/"
echo "   Force redo      : $FORCE"
[[ -n "$BASE_DOMAIN" ]] && echo "   Base domain     : $BASE_DOMAIN"
[[ -n "$DIR_WL" ]]   && echo "   Dir wordlist    : $DIR_WL"
[[ -z "$DIR_WL" ]]   && warn "no directory wordlist found — dir brute will be skipped"
echo ""

if ! have nmap; then
  echo "❌ nmap not installed — this script cannot do its core work. Aborting."
  echo "   apt install nmap"
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════
# STAGE 1 — Full TCP scan, then -sCV on the open ports
# ════════════════════════════════════════════════════════════════════════
echo "[1/5] Full TCP port sweep (-p-, timeboxed 900s)…"
ALLPORTS_NMAP="$DIR/nmap/allports.nmap"
ALLPORTS_GNMAP="$DIR/nmap/allports.gnmap"
if skip_done "$ALLPORTS_NMAP"; then
  echo "      ⏭  nmap/allports.nmap exists — skipping (use --force to redo)."
else
  tb 900 nmap -p- --min-rate 3000 -oA "$DIR/nmap/allports" "$TARGET" >/dev/null 2>&1 \
    || warn "full TCP scan exited non-zero / timed out (partial results kept)."
fi

# Parse open TCP ports from gnmap (robust) with .nmap fallback.
OPEN_TCP=""
if [[ -s "$ALLPORTS_GNMAP" ]]; then
  OPEN_TCP=$(grep -oE '[0-9]+/open/tcp' "$ALLPORTS_GNMAP" 2>/dev/null \
    | cut -d/ -f1 | sort -un | paste -sd, -)
fi
if [[ -z "$OPEN_TCP" && -s "$ALLPORTS_NMAP" ]]; then
  OPEN_TCP=$(grep -E '^[0-9]+/tcp[[:space:]]+open' "$ALLPORTS_NMAP" \
    | cut -d/ -f1 | sort -un | paste -sd, -)
fi

if [[ -z "$OPEN_TCP" ]]; then
  warn "no open TCP ports parsed. Target may be slow/filtered — check reports/$SLUG/nmap/allports.*"
else
  echo "      ✅ Open TCP ports: $OPEN_TCP"
fi

echo "      → Service/version scan (-sCV) on open ports…"
SERVICES_NMAP="$DIR/nmap/services.nmap"
if [[ -z "$OPEN_TCP" ]]; then
  warn "skipping -sCV (no open ports known)."
elif skip_done "$SERVICES_NMAP"; then
  echo "      ⏭  nmap/services.nmap exists — skipping (use --force to redo)."
else
  tb 600 nmap -sCV -p "$OPEN_TCP" -oA "$DIR/nmap/services" "$TARGET" >/dev/null 2>&1 \
    || warn "service scan exited non-zero / timed out (partial results kept)."
fi

# ════════════════════════════════════════════════════════════════════════
# STAGE 2 — UDP top-100 (needs root; timeboxed generously)
# ════════════════════════════════════════════════════════════════════════
echo ""
echo "[2/5] UDP top-100 scan (timeboxed 600s)…"
UDP_NMAP="$DIR/nmap/udp.nmap"
if skip_done "$UDP_NMAP"; then
  echo "      ⏭  nmap/udp.nmap exists — skipping (use --force to redo)."
else
  SUDO=""
  if [[ "$(id -u)" -ne 0 ]] && have sudo; then SUDO="sudo -n"; fi
  tb 600 $SUDO nmap -sU --top-ports 100 --min-rate 1000 -oA "$DIR/nmap/udp" "$TARGET" >/dev/null 2>&1 \
    || warn "UDP scan exited non-zero / timed out (needs root; partial results kept)."
fi
OPEN_UDP=""
if [[ -s "$DIR/nmap/udp.gnmap" ]]; then
  OPEN_UDP=$(grep -oE '[0-9]+/open(\|filtered)?/udp' "$DIR/nmap/udp.gnmap" 2>/dev/null \
    | cut -d/ -f1 | sort -un | paste -sd, -)
fi
[[ -n "$OPEN_UDP" ]] && echo "      ✅ Open/possible UDP ports: $OPEN_UDP"

# ════════════════════════════════════════════════════════════════════════
# STAGE 3 — Web enumeration per web port
# ════════════════════════════════════════════════════════════════════════
echo ""
echo "[3/5] Web enumeration (whatweb + headers + dir brute + vhost fuzz)…"

# Build "port scheme" pairs. Prefer the -sCV output; fall back to a known
# web-port list intersected with the open TCP set.
declare -a WEB_PORTS=()
declare -a WEB_SCHEMES=()
add_web() {  # $1 port, $2 scheme
  local p="$1" s="$2" i
  for i in "${WEB_PORTS[@]:-}"; do [[ "$i" == "$p" ]] && return; done
  WEB_PORTS+=("$p"); WEB_SCHEMES+=("$s")
}
if [[ -s "$SERVICES_NMAP" ]]; then
  while IFS= read -r line; do
    p=$(echo "$line" | grep -oE '^[0-9]+' | head -1)
    [[ -z "$p" ]] && continue
    if echo "$line" | grep -qiE 'ssl/http|https|ssl.*http'; then
      add_web "$p" https
    elif echo "$line" | grep -qiE 'http'; then
      if [[ "$p" == "443" || "$p" == "8443" ]]; then add_web "$p" https; else add_web "$p" http; fi
    fi
  done < <(grep -E '^[0-9]+/tcp[[:space:]]+open' "$SERVICES_NMAP")
fi
# Fallback: known web ports among the open set
if [[ ${#WEB_PORTS[@]} -eq 0 && -n "$OPEN_TCP" ]]; then
  for p in $(echo "$OPEN_TCP" | tr ',' ' '); do
    case "$p" in
      80|8080|8000|8008|8081|8888|3000|5000) add_web "$p" http ;;
      443|8443) add_web "$p" https ;;
    esac
  done
fi

if [[ ${#WEB_PORTS[@]} -eq 0 ]]; then
  echo "      ℹ️  No web ports detected — skipping web stage."
else
  echo "      Web ports: ${WEB_PORTS[*]}"
  for idx in "${!WEB_PORTS[@]}"; do
    P="${WEB_PORTS[$idx]}"; S="${WEB_SCHEMES[$idx]}"
    URL="$S://$TARGET:$P/"
    PORTDIR="$DIR/web/$P"
    mkdir -p "$PORTDIR"
    echo "      ── $URL ──"

    # whatweb fingerprint
    if have whatweb; then
      if skip_done "$PORTDIR/whatweb.txt"; then echo "         ⏭  whatweb.txt exists";
      else tb 90 whatweb -a 3 --color=never "$URL" >"$PORTDIR/whatweb.txt" 2>/dev/null || warn "whatweb failed on $URL"; fi
    else warn "whatweb not installed — skipping fingerprint"; fi

    # curl -I headers (add -k for https)
    CURL_TLS=""; [[ "$S" == "https" ]] && CURL_TLS="-k"
    if skip_done "$PORTDIR/headers.txt"; then echo "         ⏭  headers.txt exists";
    elif have curl; then
      curl -sI $CURL_TLS -m 10 "$URL" >"$PORTDIR/headers.txt" 2>/dev/null \
        || warn "curl -I failed on $URL"
    else warn "curl not installed — skipping headers"; fi

    # Directory brute (feroxbuster preferred, gobuster fallback)
    if [[ -z "$DIR_WL" ]]; then
      warn "no wordlist — skipping dir brute on $URL"
    elif skip_done "$PORTDIR/dirs.txt"; then
      echo "         ⏭  dirs.txt exists"
    elif have feroxbuster; then
      FTLS=""; [[ "$S" == "https" ]] && FTLS="-k"
      tb 300 feroxbuster -u "$URL" -w "$DIR_WL" $FTLS -x php,html,txt \
        --no-recursion -q -o "$PORTDIR/dirs.txt" >/dev/null 2>&1 \
        || warn "feroxbuster exited non-zero / timed out on $URL"
    elif have gobuster; then
      GTLS=""; [[ "$S" == "https" ]] && GTLS="-k"
      tb 300 gobuster dir -u "$URL" -w "$DIR_WL" $GTLS -x php,html,txt \
        -o "$PORTDIR/dirs.txt" >/dev/null 2>&1 \
        || warn "gobuster exited non-zero / timed out on $URL"
    else warn "no feroxbuster/gobuster — skipping dir brute"; fi

    # vhost fuzz — only if we know a base domain
    if [[ -n "$BASE_DOMAIN" && -n "$VHOST_WL" ]]; then
      if skip_done "$PORTDIR/vhosts.txt"; then
        echo "         ⏭  vhosts.txt exists"
      elif have ffuf; then
        FFTLS=""; [[ "$S" == "https" ]] && FFTLS="-k"
        # -ac auto-calibrates to drop the wildcard/default-size responses
        tb 300 ffuf -u "$URL" -H "Host: FUZZ.$BASE_DOMAIN" -w "$VHOST_WL" \
          $FFTLS -ac -noninteractive -o "$PORTDIR/vhosts.json" -of json >/dev/null 2>&1 \
          || warn "ffuf vhost fuzz exited non-zero / timed out on $URL"
        # extract hostnames of hits into a readable list
        if [[ -s "$PORTDIR/vhosts.json" ]]; then
          python3 - "$PORTDIR/vhosts.json" "$BASE_DOMAIN" >"$PORTDIR/vhosts.txt" 2>/dev/null <<'PY' || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
dom=sys.argv[2]
for r in d.get('results',[]):
    fuzz=r.get('input',{}).get('FUZZ','')
    print(f"{fuzz}.{dom}\tstatus={r.get('status')}\tlen={r.get('length')}")
PY
        fi
      else warn "ffuf not installed — skipping vhost fuzz"; fi
    else
      [[ -z "$BASE_DOMAIN" ]] && echo "         ℹ️  no hostname/domain known — skipping vhost fuzz (pass a hostname arg)"
    fi
  done
fi

# ════════════════════════════════════════════════════════════════════════
# STAGE 4 — CVE lookup per product+version
# ════════════════════════════════════════════════════════════════════════
echo ""
echo "[4/5] CVE recon per detected product+version…"
declare -a PRODUCTS=()
if [[ -s "$SERVICES_NMAP" ]]; then
  # Take everything after the SERVICE column as the version banner.
  while IFS= read -r line; do
    prod=$(echo "$line" | awk '{ $1=""; $2=""; $3=""; sub(/^ +/,""); print }' \
      | sed 's/((.*//; s/  */ /g; s/ *$//')
    # keep only lines that actually carry a version-ish token
    if echo "$prod" | grep -qE '[0-9]'; then
      PRODUCTS+=("$prod")
    fi
  done < <(grep -E '^[0-9]+/tcp[[:space:]]+open' "$SERVICES_NMAP")
fi

# Dedupe
declare -a UNIQ_PRODUCTS=()
for p in "${PRODUCTS[@]:-}"; do
  [[ -z "$p" ]] && continue
  seen="no"; for q in "${UNIQ_PRODUCTS[@]:-}"; do [[ "$q" == "$p" ]] && seen="yes"; done
  [[ "$seen" == "no" ]] && UNIQ_PRODUCTS+=("$p")
done

if [[ ${#UNIQ_PRODUCTS[@]} -eq 0 ]]; then
  echo "      ℹ️  No versioned products parsed from -sCV — skipping CVE recon."
elif [[ ! -f "$RECON_CVE" ]]; then
  warn "scripts/recon-cve.sh missing — skipping CVE recon."
else
  for prod in "${UNIQ_PRODUCTS[@]}"; do
    key=$(echo "$prod" | tr '/ ' '__' | tr -cd 'a-zA-Z0-9._-' | cut -c1-60)
    out="$DIR/cve/$key.md"
    if skip_done "$out"; then echo "      ⏭  cve/$key.md exists ($prod)"; continue; fi
    echo "      → $prod"
    bash "$RECON_CVE" "$prod" >"$out" 2>/dev/null || warn "recon-cve.sh failed for '$prod'"
  done
fi

# ════════════════════════════════════════════════════════════════════════
# STAGE 5 — SMB / LDAP / SNMP light anon checks
# ════════════════════════════════════════════════════════════════════════
echo ""
echo "[5/5] SMB / LDAP / SNMP light anonymous checks…"
port_open() { echo ",$OPEN_TCP," | grep -q ",$1,"; }
udp_open()  { echo ",$OPEN_UDP," | grep -q ",$1,"; }

SMB_OUT="$DIR/smb.txt"; LDAP_OUT="$DIR/ldap.txt"; SNMP_OUT="$DIR/snmp.txt"
NXC_BIN=""
for c in nxc netexec crackmapexec; do have "$c" && { NXC_BIN="$c"; break; }; done

# SMB (139/445)
if port_open 445 || port_open 139; then
  if [[ -n "$NXC_BIN" ]]; then
    if skip_done "$SMB_OUT"; then echo "      ⏭  smb.txt exists";
    else
      echo "      → SMB null session: shares + RID brute ($NXC_BIN)"
      {
        echo "### $NXC_BIN smb — null session"
        tb 90 "$NXC_BIN" smb "$TARGET" -u '' -p '' --shares 2>&1
        echo ""
        echo "### $NXC_BIN smb — RID brute"
        tb 120 "$NXC_BIN" smb "$TARGET" -u '' -p '' --rid-brute 2>&1
      } >"$SMB_OUT" 2>&1 || true
    fi
  else warn "no nxc/netexec/crackmapexec — skipping SMB checks"; fi
else
  echo "      ℹ️  SMB (139/445) not open — n/a"
fi

# LDAP (389/636)
if port_open 389 || port_open 636; then
  if have ldapsearch; then
    if skip_done "$LDAP_OUT"; then echo "      ⏭  ldap.txt exists";
    else
      echo "      → LDAP anonymous bind: rootDSE + namingContexts"
      {
        echo "### rootDSE (anonymous)"
        tb 60 ldapsearch -x -H "ldap://$TARGET" -s base -b '' namingContexts 2>&1
        NC=$(tb 60 ldapsearch -x -H "ldap://$TARGET" -s base -b '' namingContexts 2>/dev/null \
             | grep -i '^namingContexts:' | head -1 | sed 's/^namingContexts:[[:space:]]*//')
        if [[ -n "$NC" ]]; then
          echo ""
          echo "### anonymous dump of $NC (first 200 lines)"
          tb 90 ldapsearch -x -H "ldap://$TARGET" -b "$NC" 2>&1 | head -200
        fi
      } >"$LDAP_OUT" 2>&1 || true
    fi
  else warn "ldapsearch not installed — skipping LDAP checks"; fi
else
  echo "      ℹ️  LDAP (389/636) not open — n/a"
fi

# SNMP (UDP 161)
if udp_open 161; then
  if have snmpwalk; then
    if skip_done "$SNMP_OUT"; then echo "      ⏭  snmp.txt exists";
    else
      echo "      → SNMP snmpwalk with community 'public' (system subtree)"
      # keep it light: system + a bounded walk
      tb 90 snmpwalk -v2c -c public "$TARGET" 1.3.6.1.2.1.1 >"$SNMP_OUT" 2>&1 || true
      if have onesixtyone && [[ ! -s "$SNMP_OUT" ]]; then
        echo "### onesixtyone community brute" >>"$SNMP_OUT"
        tb 30 onesixtyone "$TARGET" public private community manager >>"$SNMP_OUT" 2>&1 || true
      fi
    fi
  else warn "snmpwalk not installed — skipping SNMP checks"; fi
else
  echo "      ℹ️  SNMP (UDP 161) not open — n/a"
fi

# ════════════════════════════════════════════════════════════════════════
# WRITE PRIORITIZED SUMMARY (never touches surface.md)
# ════════════════════════════════════════════════════════════════════════

# Collect CVE candidates ranked (high CVSS first) across all cve/*.md
CVE_TABLE=$(python3 - "$DIR/cve" <<'PY' 2>/dev/null || true
import os,re,sys
root=sys.argv[1]
rows=[]
if os.path.isdir(root):
    for fn in os.listdir(root):
        if not fn.endswith('.md'): continue
        prod=fn[:-3].replace('_',' ')
        for line in open(os.path.join(root,fn),encoding='utf-8',errors='ignore'):
            m=re.search(r'\[(CVE-\d{4}-\d+)\]', line)
            if not m: continue
            cid=m.group(1)
            cells=[c.strip() for c in line.split('|')]
            cvss='?'
            for c in cells:
                if re.fullmatch(r'\d{1,2}(\.\d)?', c): cvss=c; break
            summ=''
            if len(cells)>=5: summ=cells[4][:80]
            try: score=float(cvss)
            except: score=-1
            rows.append((score,cid,cvss,prod,summ))
seen=set(); out=[]
for score,cid,cvss,prod,summ in sorted(rows,key=lambda r:-r[0]):
    if cid in seen: continue
    seen.add(cid); out.append((cid,cvss,prod,summ))
for cid,cvss,prod,summ in out[:15]:
    print(f"| {cid} | {cvss} | {prod} | {summ} |")
PY
)

# Anon-access wins
ANON=""
if [[ -s "$SMB_OUT" ]] && grep -qiE 'READ|WRITE|\[\+\]|SidTypeUser' "$SMB_OUT"; then
  ANON+="- **SMB**: null session returned shares/RIDs → see reports/$SLUG/smb.txt"$'\n'
fi
if [[ -s "$LDAP_OUT" ]] && grep -qiE 'namingContexts|dn:' "$LDAP_OUT"; then
  ANON+="- **LDAP**: anonymous bind exposed naming contexts/entries → see reports/$SLUG/ldap.txt"$'\n'
fi
if [[ -s "$SNMP_OUT" ]] && grep -qiE 'STRING|OID|iso\.' "$SNMP_OUT"; then
  ANON+="- **SNMP**: community 'public' responded → see reports/$SLUG/snmp.txt"$'\n'
fi
[[ -z "$ANON" ]] && ANON="- _None detected via null/anonymous checks._"$'\n'

# Web findings block
WEB_MD=""
if [[ ${#WEB_PORTS[@]} -gt 0 ]]; then
  for idx in "${!WEB_PORTS[@]}"; do
    P="${WEB_PORTS[$idx]}"; S="${WEB_SCHEMES[$idx]}"
    WEB_MD+="### $S://$TARGET:$P/"$'\n'
    if [[ -s "$DIR/web/$P/whatweb.txt" ]]; then
      WEB_MD+="- whatweb: \`$(tr -d '\n' < "$DIR/web/$P/whatweb.txt" | sed 's/  */ /g' | cut -c1-200)\`"$'\n'
    fi
    if [[ -s "$DIR/web/$P/dirs.txt" ]]; then
      HITS=$(grep -cE 'http|^[0-9]{3}|Status' "$DIR/web/$P/dirs.txt" 2>/dev/null); HITS=${HITS:-0}
      WEB_MD+="- dir brute: $HITS lines → reports/$SLUG/web/$P/dirs.txt"$'\n'
    fi
    if [[ -s "$DIR/web/$P/vhosts.txt" ]]; then
      VH=$(wc -l < "$DIR/web/$P/vhosts.txt" | tr -d ' ')
      WEB_MD+="- vhosts found: $VH → reports/$SLUG/web/$P/vhosts.txt"$'\n'
      WEB_MD+="$(sed 's/^/    - /' "$DIR/web/$P/vhosts.txt" | head -10)"$'\n'
    fi
    WEB_MD+=$'\n'
  done
else
  WEB_MD="_No web ports detected._"$'\n'
fi

# Open ports table from services.nmap (fallback allports)
PORTS_MD=""
if [[ -s "$SERVICES_NMAP" ]]; then
  PORTS_MD=$(grep -E '^[0-9]+/tcp[[:space:]]+open' "$SERVICES_NMAP" \
    | awk '{port=$1; state=$2; svc=$3; $1=$2=$3=""; sub(/^ +/,""); printf "| %s | %s | %s | %s |\n", port, state, svc, $0}')
elif [[ -n "$OPEN_TCP" ]]; then
  PORTS_MD=$(for p in $(echo "$OPEN_TCP" | tr ',' ' '); do echo "| $p/tcp | open | ? | (run -sCV) |"; done)
fi
[[ -z "$PORTS_MD" ]] && PORTS_MD="| _none parsed_ | | | |"
UDP_MD=""
[[ -n "$OPEN_UDP" ]] && UDP_MD="**UDP open/possible:** $OPEN_UDP"

# TOP NEXT ACTIONS (heuristic)
NEXT=""
n=1
if [[ -n "$CVE_TABLE" ]]; then
  TOPCVE=$(echo "$CVE_TABLE" | head -1 | awk -F'|' '{print $2}' | tr -d ' ')
  NEXT+="$n. Investigate top CVE candidate **$TOPCVE** (see reports/$SLUG/cve/) — fetch a PoC with recon-poc.sh before running anything."$'\n'; ((n++))
fi
if [[ ${#WEB_PORTS[@]} -gt 0 ]]; then
  P="${WEB_PORTS[0]}"; S="${WEB_SCHEMES[0]}"
  NEXT+="$n. Manually review $S://$TARGET:$P/ dir-brute hits + read any open-source app source (source-dive.sh) BEFORE brute-forcing (R7)."$'\n'; ((n++))
fi
if [[ -n "$BASE_DOMAIN" ]]; then
  NEXT+="$n. Add any discovered vhosts to /etc/hosts and re-run web enum against each: bash scripts/deep-recon.sh $TARGET <vhost>."$'\n'; ((n++))
else
  NEXT+="$n. Find a hostname (cert CN, HTTP redirect, LDAP) then re-run for vhost fuzzing: bash scripts/deep-recon.sh $TARGET <hostname>."$'\n'; ((n++))
fi
if [[ "$ANON" != *"None detected"* ]]; then
  NEXT+="$n. Mine the anon-access wins above for usernames/creds, then spray them across every service (timeboxed)."$'\n'; ((n++))
fi
NEXT+="$n. Fold this summary into surface.md + add each promising item to the hypothesis bank (hypotheses.sh add … --falsifier …)."$'\n'; ((n++))
NEXT+="$n. If UDP/SNMP/LDAP untested (tool missing), install the tool and re-run --force before declaring stuck (hard-box §2 depth floor)."$'\n'

cat > "$SUMMARY" <<EOF
# Deep-recon summary — $TARGET${HOSTNAME_HINT:+ ($HOSTNAME_HINT)}

> Generated by scripts/deep-recon.sh at $(date -Iseconds).
> This is the **depth-floor** result (hard-box-playbook.md §2). Read this
> instead of re-running enumeration. **Do NOT treat "stuck" as real until
> every applicable item here has a result.**
>
> ⚠️  This file does NOT replace surface.md. Fold the findings below into
> reports/$SLUG/surface.md and the hypothesis bank (see TOP NEXT ACTIONS).

## Open ports & services

| Port | State | Service | Version |
|------|-------|---------|---------|
$PORTS_MD

$UDP_MD

## Web findings

$WEB_MD
## CVE candidates (ranked by CVSS)

| CVE | CVSS | Product | Summary |
|-----|------|---------|---------|
${CVE_TABLE:-| _none parsed_ | | | |}

_Full per-product CVE detail: reports/$SLUG/cve/*.md_

## Anonymous / null-session access wins

$ANON
## TOP NEXT ACTIONS (add these to the hypothesis bank)

$NEXT
---
_Artifacts: reports/$SLUG/nmap/{allports,services,udp}.*, web/<port>/, cve/*.md, smb.txt, ldap.txt, snmp.txt_
EOF

# ════════════════════════════════════════════════════════════════════════
# Human summary
# ════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " ✅ DEEP-RECON complete — $TARGET"
echo "═══════════════════════════════════════════════════════════════"
echo "   Open TCP : ${OPEN_TCP:-none parsed}"
[[ -n "$OPEN_UDP" ]] && echo "   Open UDP : $OPEN_UDP"
[[ ${#WEB_PORTS[@]} -gt 0 ]] && echo "   Web ports: ${WEB_PORTS[*]}"
[[ -n "$CVE_TABLE" ]] && echo "   CVE cands: $(echo "$CVE_TABLE" | wc -l | tr -d ' ') ranked (see cve/)"
echo ""
echo "   📄 Prioritized summary written to:"
echo "        reports/$SLUG/recon-summary.md"
echo ""
echo "   👉 NEXT: read recon-summary.md, then FOLD it into:"
echo "        reports/$SLUG/surface.md        (Layer 1 observations)"
echo "        the hypothesis bank             (bash scripts/hypotheses.sh add …)"
echo ""
echo "   Re-run any stage fresh with:  bash scripts/deep-recon.sh $TARGET${HOSTNAME_HINT:+ $HOSTNAME_HINT} --force"
echo "═══════════════════════════════════════════════════════════════"
