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
  echo "Archetype topics: ai, llm, flowise, ftp, wingftp, cms, wordpress,"
  echo "                  jenkins, gitlab, devops, snmp, jwt, swagger, graphql"
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
  *ai*|*llm*|*flowise*|*langchain*|*n8n*|*anythingllm*|*dify*|*orchestrat*)
    echo "  🎯 ARCHETYPE MATCH: AI orchestration platform"
    echo "  → playbooks/archetypes/ai-orchestration.md"
    echo "  → playbooks/web-app-pentest.md"
    echo "  💡 Run: bash scripts/source-dive.sh <repo> <version> BEFORE giving up on auth"
    ;;
  *ftp*|*wingftp*|*proftpd*|*vsftpd*|*filezilla*|*file*server*)
    echo "  🎯 ARCHETYPE MATCH: Custom FTP / file server"
    echo "  → playbooks/archetypes/custom-ftp-or-file-server.md"
    echo "  → playbooks/network-pentest.md"
    ;;
  *cms*|*wordpress*|*joomla*|*drupal*|*ghost*|*plugin*)
    echo "  🎯 ARCHETYPE MATCH: CMS / plugin target"
    echo "  → playbooks/archetypes/cms-and-plugins.md"
    echo "  → playbooks/web-app-pentest.md"
    ;;
  *jenkins*|*gitlab*|*gitea*|*jira*|*confluence*|*teamcity*|*argocd*|*argo*|*devops*|*ci*cd*)
    echo "  🎯 ARCHETYPE MATCH: DevOps / CI tool"
    echo "  → playbooks/archetypes/devops-tools.md"
    echo "  → playbooks/web-app-pentest.md"
    ;;
  *snmp*|*udp*161*)
    echo "  🎯 ARCHETYPE MATCH: SNMP-enabled host"
    echo "  → playbooks/archetypes/linux-snmp-host.md"
    echo "  → playbooks/network-pentest.md"
    ;;
  *swagger*|*openapi*|*graphql*|*api*only*|*jwt*)
    echo "  🎯 ARCHETYPE MATCH: API-only target"
    echo "  → playbooks/archetypes/api-only-target.md"
    echo "  → playbooks/api-pentest.md"
    ;;
  *login*|*webapp*|*generic*web*)
    echo "  🎯 ARCHETYPE MATCH: Generic web app with login"
    echo "  → playbooks/archetypes/webapp-with-login.md"
    echo "  → playbooks/web-app-pentest.md"
    echo "  💡 Source-dive BEFORE brute force: bash scripts/source-dive.sh <repo>"
    ;;
  *windows*|*smb*share*|*winrm*|*kerberos*|*samba*|*ntlm*)
    echo "  🎯 ARCHETYPE MATCH: AD / Windows target"
    echo "  → playbooks/archetypes/ad-windows-target.md"
    echo "  → knowledge-base/checklists/ad-attack-checklist.md"
    ;;
  *all*|*everything*)
    echo "  → knowledge-base/llm-hacking-context.md"
    echo "  → playbooks/archetypes/README.md"
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
echo "🛠  HELPER SCRIPTS:"
echo "  → scripts/timebox.sh <secs> <cmd...>     Hard time cap on long commands"
echo "                                            Default 90s for hydra/medusa/ncrack"
echo "                                            Default 60s for gobuster/ffuf/feroxbuster"
echo "  → scripts/source-dive.sh <repo> [tag]    Grep open-source code for unauth"
echo "                                            routes, auth bypasses, hardcoded creds"
echo ""
echo "⚠️  RULE: If a target uses an open-source web app and seems to require auth,"
echo "          run source-dive.sh BEFORE attempting brute force. The auth bypass"
echo "          is in the source code, not the running app."
echo ""
echo "⚠️  RULE: All brute force / dir-bust commands MUST be wrapped in timebox.sh."
echo "          Hydra running >90s without a hit means stop and try a different vector."
echo ""
echo "=== END ==="
