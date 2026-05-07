#!/bin/bash
# walkthrough-search.sh — Find hints (NOT solutions) for retired/public targets.
#
# When a target is a known public box (HackTheBox retired, TryHackMe free,
# VulnHub, etc.), there are usually walkthroughs online. This script searches
# for them and EXTRACTS HINTS ONLY — the techniques and tools used, NOT the
# specific commands or flags.
#
# Philosophy:
#   - Active boxes (not retired) → don't search. Be ethical.
#   - Retired/public boxes → searching is fair game (HTB explicitly allows
#     reading retired-box writeups).
#   - Output is INTENTIONALLY high-level: "uses LFI", not "exploit /xyz?file=".
#
# Usage:
#   walkthrough-search.sh <target-name>
#   walkthrough-search.sh airtouch
#   walkthrough-search.sh "wing data"
#
# Requires: curl, jq (optional), TAVILY_API_KEY env var (optional, falls back
# to plain DuckDuckGo HTML scrape).

set -uo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  cat <<EOF
walkthrough-search.sh — find HINTS (not solutions) for public boxes

Usage:
  walkthrough-search.sh <target-name>

Examples:
  walkthrough-search.sh airtouch
  walkthrough-search.sh "wing data"
  walkthrough-search.sh "openadmin htb"

Output: a /tmp/walkthrough-<target>.md file with high-level hints
extracted from public writeups. Specific exploit commands are stripped.
EOF
  exit 2
fi

SLUG="$(echo "$TARGET" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
OUT="/tmp/walkthrough-${SLUG}.md"
TMP="/tmp/walkthrough-${SLUG}-raw.txt"

echo "[*] Searching for hints on: $TARGET" >&2

# ---------------------------------------------------------------
# 1. Active-box guard
# ---------------------------------------------------------------
# We can't reliably know if an HTB box is active without an API call. Do a
# best-effort warning: if the box name is in the recent-active list of
# HTB/THM, just print a warning (we don't block — the user is in charge).
ACTIVE_WARN=0
if curl -fsS --max-time 5 "https://www.hackthebox.com/api/v4/machine/active" 2>/dev/null \
   | grep -qi "\"name\":\"$TARGET\""; then
  ACTIVE_WARN=1
  echo "[!] WARNING: '$TARGET' may be an ACTIVE HTB box. Searching writeups for active boxes is against HTB rules. Proceeding anyway — you're in charge." >&2
fi

# ---------------------------------------------------------------
# 2. Search via Tavily if available, else fall back to DuckDuckGo
# ---------------------------------------------------------------
RESULTS_FILE="/tmp/walkthrough-${SLUG}-results.json"
> "$TMP"

if [[ -n "${TAVILY_API_KEY:-}" ]]; then
  echo "[*] Using Tavily search..." >&2
  curl -fsS --max-time 20 -X POST https://api.tavily.com/search \
    -H "Content-Type: application/json" \
    -d "{
      \"api_key\": \"${TAVILY_API_KEY}\",
      \"query\": \"${TARGET} hackthebox writeup walkthrough\",
      \"search_depth\": \"basic\",
      \"max_results\": 8,
      \"include_answer\": false
    }" > "$RESULTS_FILE" 2>/dev/null

  if command -v jq >/dev/null 2>&1; then
    jq -r '.results[]? | "URL: \(.url)\nTITLE: \(.title)\nSNIPPET: \(.content)\n---"' \
      "$RESULTS_FILE" >> "$TMP" 2>/dev/null || true
  else
    # Python fallback (always present on Kali)
    python3 - "$RESULTS_FILE" >> "$TMP" <<'PYEOF' || cat "$RESULTS_FILE" >> "$TMP"
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    for r in d.get('results', []) or []:
        print(f"URL: {r.get('url','')}")
        print(f"TITLE: {r.get('title','')}")
        print(f"SNIPPET: {r.get('content','')}")
        print('---')
except Exception as e:
    sys.stderr.write(f"json parse failed: {e}\n")
    sys.exit(1)
PYEOF
  fi
else
  echo "[*] No TAVILY_API_KEY; using DuckDuckGo HTML." >&2
  curl -fsS --max-time 15 -A "Mozilla/5.0" \
    "https://duckduckgo.com/html/?q=${TARGET}+hackthebox+writeup+walkthrough" \
    | grep -oE 'href="[^"]+"' | head -30 >> "$TMP" 2>/dev/null || true
fi

if [[ ! -s "$TMP" ]]; then
  echo "[!] No results retrieved. Network or API issue." >&2
  exit 1
fi

# ---------------------------------------------------------------
# 3. Extract hints — keep WHAT was used, strip HOW exactly
# ---------------------------------------------------------------
{
  echo "# Walkthrough Hints — ${TARGET}"
  echo ""
  echo "_Generated: $(date -Iseconds)_"
  if [[ "$ACTIVE_WARN" == "1" ]]; then
    echo ""
    echo "> ⚠️  This target may be an ACTIVE HTB box. Reading writeups for"
    echo ">    active boxes violates HTB rules. Use these hints at your own risk."
  fi
  echo ""
  echo "## Source URLs (open these only if hints aren't enough)"
  echo ""
  grep -oE 'https?://[A-Za-z0-9./?=_%~&:#-]+' "$TMP" \
    | grep -viE '(google|bing|duckduckgo|youtube)' \
    | sort -u | head -10 | sed 's/^/- /'
  echo ""
  echo "## High-level technique fingerprints found in snippets"
  echo ""

  # Lookup table of techniques → their telltale words
  declare -A TECHNIQUES
  TECHNIQUES["SNMP enumeration"]='snmp|onesixtyone|snmpwalk|community string'
  TECHNIQUES["Anonymous FTP"]='anonymous ftp|anon ftp|ftp anon'
  TECHNIQUES["SMB null session"]='smb null|null session|enum4linux|smbclient -N'
  TECHNIQUES["LDAP anonymous bind"]='ldap anon|anonymous bind|ldapsearch'
  TECHNIQUES["AS-REP roasting"]='as-?rep|GetNPUsers|asreproast'
  TECHNIQUES["Kerberoasting"]='kerberoast|GetUserSPNs|tgs-rep'
  TECHNIQUES["DCSync"]='dcsync|secretsdump|drsuapi'
  TECHNIQUES["Pass-the-hash"]='pass.?the.?hash|pth|ntlm hash'
  TECHNIQUES["WiFi / WPA cracking"]='wpa|aircrack|hashcat -m 22000|handshake'
  TECHNIQUES["Web LFI"]='lfi|local file inclusion|php://filter'
  TECHNIQUES["Web RFI"]='rfi|remote file inclusion'
  TECHNIQUES["SQL injection"]='sql injection|sqlmap|sqli|union select'
  TECHNIQUES["NoSQL injection"]='nosql|mongodb injection|\\$ne'
  TECHNIQUES["XML / XXE"]='xxe|xml external|<!ENTITY'
  TECHNIQUES["SSRF"]='ssrf|server side request forgery'
  TECHNIQUES["SSTI"]='ssti|template injection|jinja|twig|freemarker'
  TECHNIQUES["Deserialization"]='deserialization|insecure deserial|gadget chain'
  TECHNIQUES["Prototype pollution"]='prototype pollution|__proto__'
  TECHNIQUES["Path traversal"]='path traversal|directory traversal|\\.\\./'
  TECHNIQUES["File upload bypass"]='file upload|polyglot|extension bypass|content.?type'
  TECHNIQUES["Reverse shell via cron"]='cron job|crontab|cron writable|cron task'
  TECHNIQUES["Web reverse shell upload"]='php-?reverse-?shell|reverse-?shell\.(php|jsp|aspx)|web shell|netcat listener'
  TECHNIQUES["SSH key theft / cracking"]='ssh.?key|id_rsa|private key|encrypted key|john.*ssh2john|ssh2john'
  TECHNIQUES["GTFOBins editor escape"]='nano.*shell|vi.*shell|less.*shell|more.*shell|escape.*editor|GTFOBins'
  TECHNIQUES["Credential reuse across users"]='same password|reuse.*password|password.*also|try.*password.*on'
  TECHNIQUES["SUID binary abuse"]='suid|gtfobins|setuid|sticky bit'
  TECHNIQUES["sudo misconfiguration"]='sudo -l|sudo nopasswd|sudo abuse|sudoers list|sudoers file|run [a-z]+ on the file|without a password.*abuse|sudo to run|run.*as root.*without'
  TECHNIQUES["Capabilities abuse"]='cap_setuid|getcap|capabilities'
  TECHNIQUES["Docker socket / container escape"]='docker socket|container escape|/var/run/docker'
  TECHNIQUES["Kernel exploit"]='kernel exploit|dirty cow|dirty pipe|cve-202[0-9]-'
  TECHNIQUES["Custom binary reverse engineering"]='reverse engin|ghidra|ida pro|disassembl'
  TECHNIQUES["JWT abuse"]='jwt|jsonwebtoken|alg.?none|jwt secret'
  TECHNIQUES["Default credentials"]='default cred|admin:admin|admin/admin'
  TECHNIQUES["Subdomain / vhost"]='subdomain|vhost|virtual host'
  TECHNIQUES["Source dive / GitHub recon"]='github|source code|repo|grep'
  TECHNIQUES["Wing FTP CVE-2025-47812"]='wing ?ftp|CVE-2025-47812|52347'
  TECHNIQUES["Flowise CVE"]='flowise|cve-2025-59528|customMCP'

  CONTENT_LOWER="$(tr '[:upper:]' '[:lower:]' < "$TMP")"
  HITS=0
  for tech in "${!TECHNIQUES[@]}"; do
    pattern="${TECHNIQUES[$tech]}"
    if echo "$CONTENT_LOWER" | grep -qE "$pattern"; then
      echo "- $tech"
      HITS=$((HITS+1))
    fi
  done

  if [[ $HITS -eq 0 ]]; then
    echo "_(no obvious techniques fingerprinted — open the source URLs)_"
  fi
  echo ""

  # Extract tool/binary names that come up
  echo "## Tools mentioned"
  echo ""
  grep -oiE '\b(nmap|gobuster|feroxbuster|ffuf|wfuzz|hydra|medusa|crackmapexec|cme|nxc|netexec|impacket|kerbrute|bloodhound|sharphound|enum4linux|smbclient|smbmap|rpcclient|ldapsearch|evil-?winrm|psexec|wmiexec|secretsdump|getuserspns|getnpusers|hashcat|john|sqlmap|nikto|wpscan|joomscan|droopescan|burp|searchsploit|metasploit|msfvenom|aircrack|hcxdumptool|reaver|wireshark|tshark|tcpdump|airmon-?ng|airodump|hostapd|ghidra|radare2|objdump|strings|binwalk|stegcracker|exiftool|zsteg|cewl|crunch|rockyou|seclists)\b' "$TMP" \
    | sort -u | sed 's/^/- /'
  echo ""

  # Strip ALL specific commands and flags from snippets, then quote the
  # cleaned snippet text. This is the spoiler firewall.
  echo "## Cleaned snippets (specific commands removed)"
  echo ""
  awk '/SNIPPET:/,/---/' "$TMP" \
    | sed -E 's@(curl|wget|nmap|hydra|medusa|gobuster|ffuf|sqlmap|crackmapexec|cme|nxc|impacket-[a-zA-Z0-9_-]+|GetUserSPNs.py|GetNPUsers.py|secretsdump.py|psexec.py|wmiexec.py|evil-?winrm|hashcat|john)( [^.]*?)(\.|$)@<command redacted>\3@gi' \
    | sed -E 's@(/[a-zA-Z0-9_/.+-]+){2,}@<path redacted>@g' \
    | sed -E 's@-[a-zA-Z]\s+[^[:space:]]+@<flag redacted>@g' \
    | sed -E 's@\b[a-fA-F0-9]{16,}\b@<hash redacted>@g' \
    | sed -E 's@HTB\{[^}]+\}@<flag redacted>@g' \
    | sed -E 's@flag\{[^}]+\}@<flag redacted>@g' \
    | grep -v '^---$' | head -80
  echo ""
  echo "## How to use this file"
  echo ""
  echo "1. **Read the high-level techniques.** Pick the one that fits your"
  echo "   recon — that's the path the box wants."
  echo "2. **Don't read the raw URLs unless you're stuck.** Hints first;"
  echo "   spoilers only as a last resort."
  echo "3. **Map the technique to its archetype playbook:**"
  echo "   - SNMP → playbooks/archetypes/linux-snmp-host.md"
  echo "   - LFI/SQLi/SSTI → playbooks/web-app-pentest.md + creative-pivots.md"
  echo "   - AD-flavoured → playbooks/archetypes/ad-windows-target.md"
  echo "4. **Try the technique end-to-end yourself.** The walkthrough is"
  echo "   only telling you WHICH bug to find — finding and exploiting it"
  echo "   is still your job."
  echo ""
} > "$OUT"

echo ""
echo "✅ Hints written to: $OUT" >&2
wc -l "$OUT" >&2
echo "" >&2
echo "View with: less $OUT" >&2
echo "$OUT"
