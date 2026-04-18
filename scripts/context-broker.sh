#!/usr/bin/env bash
# Context Broker — Tells any LLM which knowledge base files to load
# Usage: bash scripts/context-broker.sh <keyword|topic>
# Examples:
#   bash scripts/context-broker.sh web
#   bash scripts/context-broker.sh "active directory"
#   bash scripts/context-broker.sh privesc
#   bash scripts/context-broker.sh recon
#   bash scripts/context-broker.sh all

set -e

KB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOPIC="${*,,}"  # lowercase all args

if [ -z "$TOPIC" ]; then
  echo "Usage: context-broker.sh <topic>"
  echo ""
  echo "Topics: web, api, network, ad, privesc, recon, cloud, wireless,"
  echo "        credential, lateral, c2, shell, enumeration, mitre, report, all"
  echo ""
  echo "Returns the files you should read for that topic."
  exit 1
fi

echo "=== CONTEXT BROKER ==="
echo "Topic: $TOPIC"
echo ""

# Always recommend the decision tree first
echo "📋 START HERE (always read first):"
echo "  → knowledge-base/llm-hacking-context.md"
echo ""

echo "📂 RECOMMENDED FILES:"

case "$TOPIC" in
  *web*|*owasp*|*xss*|*sqli*|*injection*|*lfi*|*rfi*|*ssrf*|*idor*)
    echo "  → playbooks/web-app-pentest.md"
    echo "  → knowledge-base/checklists/owasp-top10.md"
    echo "  → knowledge-base/mitre-attack/techniques/web-exploitation.md (if exists)"
    echo "  → knowledge-base/tools/kali-essentials.md (web section)"
    ;;
  *api*|*rest*|*graphql*|*endpoint*)
    echo "  → playbooks/api-pentest.md"
    echo "  → knowledge-base/checklists/owasp-top10.md"
    ;;
  *network*|*infrastructure*|*port*|*scan*|*nmap*)
    echo "  → playbooks/network-pentest.md"
    echo "  → knowledge-base/checklists/enumeration-checklist.md"
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (Recon + Discovery)"
    ;;
  *ad*|*active*directory*|*kerberos*|*domain*|*ldap*|*bloodhound*)
    echo "  → knowledge-base/checklists/ad-attack-checklist.md"
    echo "  → knowledge-base/mitre-attack/techniques/credential-access-ad.md (if exists)"
    echo "  → knowledge-base/tools/kali-essentials.md (AD section)"
    ;;
  *priv*|*escalat*|*suid*|*sudo*|*linpeas*|*winpeas*)
    echo "  → playbooks/privilege-escalation.md"
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0004)"
    ;;
  *recon*|*osint*|*subdomain*|*harvest*|*passive*)
    echo "  → playbooks/network-pentest.md (recon phase)"
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0043)"
    echo "  → knowledge-base/mitre-attack/techniques/reconnaissance-deep.md (if exists)"
    echo "  → knowledge-base/tools/kali-essentials.md (recon section)"
    ;;
  *cloud*|*aws*|*azure*|*gcp*|*s3*|*iam*)
    echo "  → playbooks/cloud-pentest.md"
    echo "  → knowledge-base/mitre-attack/techniques/cloud-attacks.md (if exists)"
    ;;
  *wireless*|*wifi*|*wpa*|*aircrack*|*bluetooth*)
    echo "  → playbooks/wireless-pentest.md"
    ;;
  *cred*|*password*|*hash*|*brute*|*crack*|*mimikatz*|*dump*)
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0006)"
    echo "  → knowledge-base/mitre-attack/techniques/credential-access-ad.md (if exists)"
    echo "  → knowledge-base/tools/kali-essentials.md (credential section)"
    ;;
  *lateral*|*pivot*|*movement*|*psexec*|*wmi*|*smb*)
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0008)"
    echo "  → knowledge-base/mitre-attack/techniques/lateral-movement-deep.md (if exists)"
    echo "  → knowledge-base/checklists/enumeration-checklist.md (SMB/services)"
    ;;
  *c2*|*command*control*|*callback*|*beacon*|*tunnel*)
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0011)"
    echo "  → knowledge-base/checklists/reverse-shells.md"
    echo "  → knowledge-base/mitre-attack/techniques/c2-tunneling.md (if exists)"
    ;;
  *shell*|*reverse*|*bind*|*payload*|*msfvenom*)
    echo "  → knowledge-base/checklists/reverse-shells.md"
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0002)"
    ;;
  *enum*|*service*|*version*|*fingerprint*)
    echo "  → knowledge-base/checklists/enumeration-checklist.md"
    echo "  → knowledge-base/tools/kali-essentials.md"
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0007)"
    ;;
  *mitre*|*att.ck*|*tactic*|*technique*)
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md"
    echo "  → knowledge-base/mitre-attack/techniques/ (all files)"
    ;;
  *report*|*template*|*document*)
    echo "  → templates/attack-report-template.md"
    ;;
  *persist*|*backdoor*|*implant*)
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0003)"
    echo "  → knowledge-base/mitre-attack/techniques/persistence-deep.md (if exists)"
    ;;
  *evasi*|*bypass*|*av*|*edr*|*defense*)
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md (TA0005)"
    echo "  → knowledge-base/mitre-attack/techniques/defense-evasion-deep.md (if exists)"
    ;;
  *all*|*everything*)
    echo "  → knowledge-base/llm-hacking-context.md"
    echo "  → knowledge-base/mitre-attack/enterprise-tactics.md"
    echo "  → knowledge-base/tools/kali-essentials.md"
    echo "  → knowledge-base/checklists/ (all files)"
    echo "  → playbooks/ (all files)"
    echo "  → templates/attack-report-template.md"
    echo "  → knowledge-base/mitre-attack/techniques/ (all files)"
    ;;
  *)
    echo "  ⚠️  Unknown topic '$TOPIC'"
    echo "  → Defaulting to full knowledge base:"
    echo "  → knowledge-base/llm-hacking-context.md"
    echo "  → knowledge-base/tools/kali-essentials.md"
    echo "  → knowledge-base/checklists/enumeration-checklist.md"
    echo ""
    echo "  Try: web, network, ad, privesc, recon, cloud, wireless, credential,"
    echo "       lateral, c2, shell, enumeration, mitre, report, persist, evasion, all"
    ;;
esac

echo ""
echo "📖 RULES (always apply):"
echo "  → AGENTS.md"
echo ""
echo "=== END ==="
