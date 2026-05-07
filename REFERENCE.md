# REFERENCE.md — Technical Details (for advanced use)

> This file contains the **detailed technical rules** that were previously in AGENTS.md and AUTOPILOT.md.
> Use this for:
> - Subagent task prompts
> - Debugging the orchestrator
> - Understanding the full scope of the nest
> - Recreating the nest on a new machine

---

## 1. AGENTS.md (Original Rules, Full Detail)

### 1.1 Tool Selection
- **Kali tools**: Always prefer built-in Kali tools (`nmap`, `hydra`, `gobuster`, `sqlmap`, `john`, `hashcat`, `metasploit`, `bloodhound`, `responder`, `impacket`, `crackmapexec`).
- **Installation rules**:
  - `apt install` from Kali/Debian repos: **no ask**.
  - `pip`, `npm`, `go get`, `curl | bash`, GitHub repos: **ask Raquel first**.
  - Exception: `clawhub install` for skills is always allowed.

### 1.2 Search & Browsing
- **Priority**: `tavily-search-pro` → `stealth-browser` → manual.
- **Stealth-browser triggers**: "bypass cloudflare", "solve captcha", "stealth browse", "silent automation", "persistent login", "anti-detection", "login to X".
- **API bypass**: If a website loads without API key but the API requires one, use `stealth-browser` to scrape the rendered page.

### 1.3 No Blind Code Execution
- **Never** execute code from the internet without explicit approval.
- **Review first**: Download the code, read it, explain what it does, then ask.
- **Exceptions**:
  - Exploits from `exploit-db` (already reviewed by Kali team).
  - Scripts from `knowledge-base/tools/` (curated by us).

### 1.4 Git Hygiene (Full Rules)

#### ✅ Commit
- Documentation: `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `BOOTSTRAP.md`, `TOOLS.md`, `HEARTBEAT.md`.
- Bootstrap scripts: `scripts/*.sh`, `scripts/*.py`.
- Knowledge base: `knowledge-base/`, `playbooks/`, `templates/`.
- Skills config: `skills/`.
- Sanitized lessons: `learnings/` (redacted, no targets, no PII).
- `.gitignore`, `README.md`.

#### ❌ Never Commit
- **Reports**: `reports/` (target-specific, may contain creds/hashes/flags).
- **Memory**: `memory/`, `MEMORY.md` (personal conversation traces).
- **State**: `state/` (runtime engagement state).
- **Loot**: `loot/`, `*.pcap`, BloodHound dumps, hash captures.
- **Scan output**: `*.nmap`, `*.gnmap`, `*.xml`, `*.hccapx`, `*.22000`.
- **Secrets**: `*.key`, `*.pem`, `*.env`, SSH keys, browser sessions, cookies.
- **OSINT on real people**: Never. Not even in private repos.
- **Anything that names a real person, company, email, phone, address**.

#### Pre-commit Checklist
```bash
1. git status --short
2. git diff --cached | grep -iE "(password|secret|key|flag|hash|creds|token|session|cookie|Fernando|Leite|Lipor|@|\.htb|\.local)"
3. Ask: "Would I be comfortable if this commit appeared on a stranger's screen?"
4. If unsure → don't commit, ask Raquel.
```

#### Pre-push Audit
```bash
git log origin/master..HEAD --pretty=format:"%H %s"
git log origin/master..HEAD --name-only | sort -u
```

### 1.5 Reproducibility on New Machines
- **Bootstrap**: `scripts/bootstrap.sh` installs all dependencies (Node.js, Python, tools).
- **Git clone**: `git clone git@github.com:raquel4112002/zuzu.git ~/.openclaw/workspace`.
- **SSH key**: `ssh-keygen -t ed25519 -f ~/.ssh/github_zuzu`.
- **OpenClaw config**: `~/.openclaw/openclaw.json` with `TAVILY_API_KEY`.

### 1.6 Subagent Inheritance
- **Always** pass these rules to subagents.
- **Task prompt template**:
```
Read AGENTS.md rules first. Key points:
- No blind code execution.
- No exfiltration of private data.
- Write findings to reports/<target>/.
- Use scripts/timebox.sh for brute-force.
- Source-dive before brute-forcing open-source apps.
```

### 1.7 Attack Reports
- **Folder structure**: `reports/<target>/` (created by `scripts/new-target.sh`).
- **Subfolders**: `nmap/`, `web/`, `creds/`, `loot/`.
- **Template**: `templates/attack-report-template.md`.
- **Forbidden**: Writing loose files in `reports/` (e.g., `nmap-result.txt`).

---

## 2. AUTOPILOT.md (Original Orchestrator/Tracker Details)

### 2.1 Orchestrator State Machine
- **Commands**:
  - `bash scripts/orchestrator.sh init TARGET`
  - `bash scripts/orchestrator.sh think` → suggests next command.
  - `bash scripts/orchestrator.sh report "result"` → logs result.
  - `bash scripts/orchestrator.sh error "what went wrong"` → suggests fix.
  - `bash scripts/orchestrator.sh status` → shows progress.
- **Stuck-gate**: After ≥2 attempts on same step, forces a 3-hypothesis worksheet.

### 2.2 Tracker (Manual Mode)
- **Commands**:
  - `bash scripts/tracker.sh start TARGET [type]`
  - `bash scripts/tracker.sh next` → what to do now.
  - `bash scripts/tracker.sh done <step>` → mark completed.
  - `bash scripts/tracker.sh found "description"` → log finding.
  - `bash scripts/tracker.sh creds user pass` → log credentials.
  - `bash scripts/tracker.sh shell reverse TARGET` → log shell.

### 2.3 Decision Tree (Original)
| Given | Section |
|---|---|
| Website URL/domain | Section A: Web Attack |
| IP address | Section B: Network Attack |
| Subnet | Section C: Network Sweep |
| Domain creds | Section D: Active Directory |
| Cloud target | Section E: Cloud Attack |
| Not sure | Section F: Auto-Recon |

---

## 3. Playbook/Runbook Authoring Rules

### 3.1 Runbooks (Copy-Paste, End-to-End)
- **Format**:
  ```markdown
  # Runbook: <name>
  
  **Target**: <product> <version>
  **Goal**: <user/root>
  
  ## Steps
  
  1. **Step name**
     ```bash
     export TARGET="10.129.49.228"
     export HOSTNAME="ftp.wingdata.htb"
     nmap -sC -sV -p 80,21 -oA reports/$TARGET/nmap/quick $TARGET
     ```
     Expected output:
     ```
     21/tcp open  ftp     Wing FTP Server 7.4.3
     80/tcp open  http    Apache httpd 2.4.66
     ```
  
  2. **Next step**
     ```bash
     curl -H "Host: $HOSTNAME" http://$TARGET/login.html | grep -i "Wing FTP"
     ```
  ```
  ```
- **Rules**:
  - Every step must have a literal command + expected output.
  - No reasoning required — just follow the steps.
  - Failures must point to another runbook or archetype.
  - Variables (`TARGET`, `HOSTNAME`, `USER`, `PASS`) must be declared at the top.

### 3.2 Archetypes (Checklists, No Copy-Paste)
- **Format**:
  ```markdown
  # Archetype: <name>
  
  **Triggers**: <keywords>
  
  ## Fast Checks (≤5 min)
  - [ ] Check for default creds: `admin:admin`, `admin:password`, `guest:guest`.
  - [ ] Run `gobuster dir -u http://$TARGET/ -w /usr/share/wordlists/dirb/common.txt -t 50`.
  - [ ] Check for known CVEs: `searchsploit <product> <version>`.
  
  ## Deep Checks
  - [ ] Source-dive for unauth routes (if open-source).
  - [ ] Check for misconfigurations (e.g., `.git/`, `/.env`, `/backup/`).
  - [ ] Test for IDOR, SSRF, XXE.
  
  ## Known CVEs
  | CVE | Exploit-DB ID | Notes |
  |---|---|---|
  | CVE-2025-47812 | 52347 | Wing FTP Lua injection → RCE |
  
  ## Common Pitfalls
  - P1: Wing FTP session-lock DoS (502 Proxy Error after exploit storms).
  ```
  ```

---

## 4. Context Broker Keywords

| Keyword | Files |
|---|---|
| `wing` | `playbooks/runbooks/wing-ftp-rooted.md`, `playbooks/archetypes/custom-ftp-or-file-server.md` |
| `hashcat`, `hash mode`, `sha256`, `md5` | `knowledge-base/creative-pivots.md` (Section E0) |
| `runbook`, `end-to-end`, `recipe` | `playbooks/runbooks/README.md` |
| `cve`, `exploit-db`, `poc` | `knowledge-base/cve-to-exploit-cache.md` |
| `source-dive`, `grep`, `unauth` | `scripts/source-dive.sh`, `playbooks/archetypes/webapp-with-login.md` |
| `timebox`, `brute-force`, `hydra` | `scripts/timebox.sh` |
| `walkthrough`, `hint`, `htb` | `scripts/walkthrough-search.sh` |
| `ad`, `active directory`, `kerberos` | `playbooks/archetypes/ad-windows-target.md` |
| `cms`, `wordpress`, `joomla` | `playbooks/archetypes/cms-and-plugins.md` |

---

## 5. CVE-to-Exploit Cache Example

```markdown
| CVE | Product | Exploit-DB ID | Local Path | Quirks | Runbook |
|---|---|---|---|---|---|
| CVE-2025-47812 | Wing FTP Server ≤7.4.3 | 52347 | /usr/share/exploitdb/exploits/linux/webapps/52347.py | Needs vhost `ftp.<hostname>` | `playbooks/runbooks/wing-ftp-rooted.md` |
| CVE-2025-4517 | Python tarfile | 52348 | /usr/share/exploitdb/exploits/multiple/local/52348.py | Filter bypass | `playbooks/runbooks/linux-foothold-to-root.md` |
```