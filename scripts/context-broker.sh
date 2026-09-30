#!/usr/bin/env bash
# Context Broker — context-aware knowledge router for the Nest.
#
# The point: a weaker model shouldn't have to KNOW which knowledge file to
# open, nor drown in the whole KB. This serves the *minimal relevant slice*
# for where the engagement actually is.
#
# Modes:
#   context-broker.sh                     auto — infer topic(s) from the live
#                                         engagement state, list the files.
#   context-broker.sh <topic>             keyword lookup (web, ad, pivot, hard,
#                                         privesc, recon, cred, lateral, cloud,
#                                         snmp, cms, api, report, stuck, cve, all)
#   context-broker.sh --print [topic|auto]  dump the top files' CONTENT, capped
#                                         at CB_BUDGET bytes (default 24000) so
#                                         it lands in-context without flooding.
#   context-broker.sh auto [--print]
#
# Only files that actually exist are ever emitted.

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$WS/state/orchestrator.json"
BUDGET="${CB_BUDGET:-24000}"

exists() { [[ -f "$WS/$1" ]]; }

# ── topic → candidate files (priority order). Return 1 if unknown topic. ──
files_for_topic() {
  case "$1" in
    hard|insane|depth)
      echo knowledge-base/checklists/hard-box-playbook.md
      echo knowledge-base/checklists/when-to-stop-enumerating.md ;;
    web|owasp|xss|sqli|injection|lfi|rfi|ssrf|idor)
      echo playbooks/web-app-pentest.md
      echo knowledge-base/mitre-attack/techniques/web-exploitation.md
      echo knowledge-base/checklists/owasp-top10.md ;;
    api|rest|graphql|swagger|openapi)
      echo playbooks/archetypes/api-only-target.md
      echo playbooks/api-pentest.md ;;
    ad|active|directory|kerberos|domain|ldap|bloodhound|windows|winrm|ntlm|kerberoast|smb)
      echo playbooks/runbooks/ad-decision-runbook.md
      echo knowledge-base/checklists/ad-attack-checklist.md
      echo knowledge-base/checklists/ad-coercion-and-relay.md
      echo knowledge-base/mitre-attack/techniques/adcs-esc-deep.md
      echo knowledge-base/checklists/bloodhound-edge-to-action.md
      echo knowledge-base/tools/ad-abuse-commands.md ;;
    pivot|lateral|tunnel|tunneling|movement|multihost|pivoting)
      echo playbooks/pivoting-and-tunneling.md
      echo playbooks/archetypes/multi-host-pivot.md
      echo knowledge-base/checklists/pivoting-checklist.md
      echo knowledge-base/mitre-attack/techniques/lateral-movement-deep.md ;;
    privesc|priv|escalation|suid|sudo|linpeas|winpeas)
      echo playbooks/privilege-escalation.md
      echo playbooks/runbooks/linux-foothold-to-root.md ;;
    recon|osint|subdomain|enumeration|enum|service|fingerprint)
      echo knowledge-base/checklists/enumeration-checklist.md
      echo playbooks/network-pentest.md
      echo knowledge-base/mitre-attack/techniques/reconnaissance-deep.md ;;
    cred|credential|password|hash|crack|dump|mimikatz)
      echo knowledge-base/mitre-attack/techniques/credential-access-ad.md
      echo knowledge-base/creative-pivots.md ;;
    c2|command|control|beacon|callback)
      echo knowledge-base/mitre-attack/techniques/c2-tunneling.md
      echo knowledge-base/checklists/reverse-shells.md ;;
    shell|reverse|bind|payload|msfvenom)
      echo knowledge-base/checklists/reverse-shells.md ;;
    cloud|aws|azure|gcp|s3|iam)
      echo playbooks/cloud-pentest.md
      echo knowledge-base/mitre-attack/techniques/cloud-attacks.md ;;
    wireless|wifi|wpa)
      echo playbooks/wireless-pentest.md ;;
    snmp)
      echo playbooks/archetypes/linux-snmp-host.md ;;
    cms|wordpress|joomla|drupal)
      echo playbooks/archetypes/cms-and-plugins.md
      echo playbooks/web-app-pentest.md ;;
    devops|jenkins|gitlab|jira|confluence)
      echo playbooks/archetypes/devops-tools.md ;;
    ai|llm|flowise|langchain|n8n)
      echo playbooks/archetypes/ai-orchestration.md ;;
    ftp|fileserver)
      echo playbooks/archetypes/custom-ftp-or-file-server.md ;;
    login|webapp)
      echo playbooks/archetypes/webapp-with-login.md
      echo playbooks/web-app-pentest.md ;;
    stuck|creative|unstuck|alternative)
      echo knowledge-base/checklists/stuck-reasoning.md
      echo knowledge-base/creative-pivots.md
      echo knowledge-base/checklists/operator-fallbacks.md ;;
    cve|exploit|poc)
      echo knowledge-base/cve-to-exploit-cache.md ;;
    report|template)
      echo templates/attack-report-template.md ;;
    mitre|attack|tactic|technique)
      echo knowledge-base/mitre-attack/enterprise-tactics.md ;;
    all|everything)
      echo knowledge-base/llm-hacking-context.md
      echo knowledge-base/checklists/hard-box-playbook.md
      echo playbooks/archetypes/README.md
      echo knowledge-base/creative-pivots.md
      echo knowledge-base/mitre-attack/enterprise-tactics.md ;;
    *) return 1 ;;
  esac
}

# ── topic → relevant installed ClawHub skills (invoked via the Skill tool,
#    not read as files). These carry expert priors weak models lack. ──
skills_for_topic() {
  case "$1" in
    web|owasp|xss|sqli|injection|lfi|rfi|ssrf|idor)
      echo sqli-sql-injection; echo authbypass-authentication-flaws
      echo xxe-xml-external-entity; echo jwt-oauth-token-attacks
      echo unauthorized-access-common-services ;;
    api|rest|graphql|swagger|openapi)
      echo jwt-oauth-token-attacks; echo authbypass-authentication-flaws ;;
    ad|active|directory|kerberos|domain|ldap|bloodhound|windows|winrm|ntlm|kerberoast|smb)
      echo ntlm-relay-coercion; echo windows-privilege-escalation
      echo windows-lateral-movement ;;
    pivot|lateral|tunnel|tunneling|movement|multihost|pivoting)
      echo tunneling-and-pivoting; echo linux-lateral-movement
      echo windows-lateral-movement ;;
    privesc|priv|escalation|suid|sudo|linpeas|winpeas)
      echo windows-privilege-escalation; echo linux-security-bypass
      echo container-escape-techniques; echo sandbox-escape-techniques ;;
    pwn|binary|rop|bof|overflow|heap|format|kernel|reversing|exploitdev)
      echo stack-overflow-and-rop; echo heap-exploitation
      echo format-string-exploitation; echo binary-protection-bypass
      echo kernel-exploitation ;;
    shell|reverse|bind|payload|msfvenom)
      echo reverse-shell-techniques ;;
    recon|enum|service|fingerprint)
      echo unauthorized-access-common-services ;;
    cred|credential|password|hash|crack)
      echo ntlm-relay-coercion ;;
    hard|insane)
      echo unauthorized-access-common-services; echo stack-overflow-and-rop ;;
    *) return 1 ;;
  esac
}

# ── auto: infer topics from the live engagement state ──
auto_topics() {
  [[ -f "$STATE" ]] || { echo "recon hard"; return; }
  local slug bench=""
  slug="$(python3 -c "import json;print(json.load(open('$STATE')).get('target',''))" 2>/dev/null | tr '/' '-' | tr -cd 'a-zA-Z0-9._-')"
  [[ -n "$slug" && -f "$WS/reports/$slug/.bench.json" ]] && bench="$WS/reports/$slug/.bench.json"
  python3 - "$STATE" "$bench" <<'PY'
import json, sys
state = json.load(open(sys.argv[1])) if sys.argv[1] else {}
bench = json.load(open(sys.argv[2])) if len(sys.argv) > 2 and sys.argv[2] else {}
topics = []
diff = (bench.get("difficulty") or "").lower()
if diff in ("hard", "insane"):
    topics.append("hard")
# Fingerprint from discovered services.
svc = state.get("services", {}) or {}
blob = " ".join(f"{p} {v.get('service','')} {v.get('version','')}"
                for p, v in svc.items() if isinstance(v, dict)).lower()
ports = set()
for p in list(svc.keys()) + [str(x) for x in (state.get("ports", {}) or {}).get("tcp", [])]:
    ports.add(str(p).split("/")[0])
is_ad = any(k in blob for k in ("kerberos", "ldap", "microsoft-ds", "smb", "netbios")) \
        or bool(ports & {"88", "389", "445", "464", "3268", "636"})
is_web = ("http" in blob) or bool(ports & {"80", "443", "8080", "8000", "8443", "8888"})
is_snmp = ("snmp" in blob) or ("161" in ports)
if is_ad:
    topics.append("ad")
if is_web:
    topics.append("web")
if is_snmp:
    topics.append("snmp")
# Phase-driven.
phase = (state.get("phase") or "").lower()
if phase in ("privesc",):
    topics.append("privesc")
elif phase in ("lateral", "pivot"):
    topics.append("pivot")
elif phase in ("exploit",):
    topics.append("cve")
elif phase in ("recon", "enum", "") and not (is_ad or is_web):
    topics.append("recon")
# Multi-host hint.
if len(state.get("hostnames", []) or []) > 1:
    topics.append("pivot")
if not topics:
    topics = ["recon"]
# Dedupe preserving order.
seen = set(); out = []
for t in topics:
    if t not in seen:
        seen.add(t); out.append(t)
print(" ".join(out))
PY
}

# ── render: list ──
render_list() {
  local topic="$1"; shift
  local files=("$@")
  echo "═══ CONTEXT BROKER ═══"
  echo "Mode: ${topic}"
  echo ""
  if [[ ${#files[@]} -eq 0 && ${#SKILLS[@]} -eq 0 ]]; then
    echo "No specific match. Start here:"
    echo "  → knowledge-base/llm-hacking-context.md"
  elif [[ ${#files[@]} -gt 0 ]]; then
    echo "📂 READ THESE (most relevant first):"
    for f in "${files[@]}"; do echo "  → $f"; done
  fi
  if [[ ${#SKILLS[@]} -gt 0 ]]; then
    echo ""
    echo "🧩 RELEVANT SKILLS (invoke via the Skill tool — expert priors):"
    for s in "${SKILLS[@]}"; do echo "  ⚡ $s"; done
  fi
  cat <<EOF

🛠  ONE-SHOT SCRIPTS (prefer these over remembering commands):
  → scripts/deep-recon.sh <target> [host]   full enumeration depth floor → recon-summary.md
  → scripts/ad-auto.sh --dc <ip> --domain <d> [--user --pass]   AD sweep → ad-findings.md
  → scripts/verify.sh cred|host|flag ...     ground a claim before marking confirmed
  → scripts/timebox.sh <secs> <cmd...>       hard time cap on brute/dir-bust
  → scripts/source-dive.sh <repo> [tag]      read source for auth bypass BEFORE brute force

📖 Rules: AGENTS.md   |   Reflex card: QUICKSTART.md
💡 Tip: 'context-broker.sh --print' dumps the CONTENT of the top files, byte-capped.
═══ END ═══
EOF
}

# ── render: print (bounded content dump) ──
render_print() {
  local topic="$1"; shift
  local files=("$@")
  echo "═══ CONTEXT (topic: $topic · budget: ${BUDGET}B) ═══"
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "(no matching files; see knowledge-base/llm-hacking-context.md)"; return
  fi
  local total=0 f sz
  for f in "${files[@]}"; do
    sz=$(wc -c < "$WS/$f" 2>/dev/null || echo 0)
    if (( total > 0 && total + sz > BUDGET )); then
      echo ""
      echo "── omitted (budget): $f (${sz}B) — read it directly if needed ──"
      continue
    fi
    echo ""
    echo "──────── FILE: $f (${sz}B) ────────"
    cat "$WS/$f"
    total=$((total + sz))
  done
  echo ""
  echo "═══ END (${total}B served) ═══"
}

# ── main ──
PRINT="no"; TOPIC=""
for a in "$@"; do
  case "$a" in
    --print|print) PRINT="yes" ;;
    *) TOPIC="${a,,}" ;;
  esac
done
[[ -z "$TOPIC" ]] && TOPIC="auto"

# Expand "auto" to a concrete topic list.
if [[ "$TOPIC" == "auto" ]]; then
  RESOLVED_TOPICS="$(auto_topics)"
else
  RESOLVED_TOPICS="$TOPIC"
fi

# Resolve topics → ordered, existing, deduped file list.
mapfile -t FILES < <(
  seen=" "
  for t in $RESOLVED_TOPICS; do
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ -f "$WS/$f" ]] || continue
      [[ "$seen" == *" $f "* ]] && continue
      seen+="$f "; echo "$f"
    done < <(files_for_topic "$t" 2>/dev/null || true)
  done
)

# Resolve topics → relevant INSTALLED skills (dedupe, existence-checked).
mapfile -t SKILLS < <(
  seen=" "
  for t in $RESOLVED_TOPICS; do
    while IFS= read -r s; do
      [[ -z "$s" ]] && continue
      [[ -d "$WS/skills/$s" ]] || continue
      [[ "$seen" == *" $s "* ]] && continue
      seen+="$s "; echo "$s"
    done < <(skills_for_topic "$t" 2>/dev/null || true)
  done
)

LABEL="$TOPIC"
[[ "$TOPIC" == "auto" ]] && LABEL="auto → ${RESOLVED_TOPICS:-recon}"

if [[ "$PRINT" == "yes" ]]; then
  render_print "$LABEL" "${FILES[@]}"
else
  render_list "$LABEL" "${FILES[@]}"
fi
