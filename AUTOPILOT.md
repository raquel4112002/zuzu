# AUTOPILOT.md — Manual Mode (Fallback for zero.sh)

> **Use `zero.sh` first.** This file is a fallback for when `zero.sh` is unavailable or broken.

---

## The One Command You Need

```bash
bash scripts/zero.sh <target-ip-or-hostname>
```

It does everything automatically:
1. Creates `reports/<target>/` with the right folder structure.
2. Confirms reachability.
3. Quick port scan (top-1000, timeboxed 90s).
4. Fingerprints the stack (Wing FTP? WordPress? Jenkins? AD?).
5. **Tells you exactly which runbook or archetype to follow.**

---

## Manual Mode (When zero.sh is Broken)

### Step 1: Create the Target Folder

```bash
bash scripts/new-target.sh <target-ip-or-hostname> [hostname]
```

### Step 2: Quick Recon

```bash
bash scripts/timebox.sh 90 nmap -sC -sV --top-ports 1000 -oA reports/<target>/nmap/quick <target>
```

### Step 3: Follow the Decision Tree

| You See... | Go To... |
|---|---|
| Wing FTP Server ≤7.4.3 | `playbooks/runbooks/wing-ftp-rooted.md` |
| WordPress/Joomla/Drupal | `playbooks/archetypes/cms-and-plugins.md` |
| Jenkins/GitLab/Gitea | `playbooks/archetypes/devops-tools.md` |
| Active Directory ports (88, 389, 445) | `playbooks/archetypes/ad-windows-target.md` |
| FTP service | `playbooks/archetypes/custom-ftp-or-file-server.md` |
| Web server (no product) | `playbooks/archetypes/webapp-with-login.md` |
| Nothing matches | `knowledge-base/llm-hacking-context.md` |

### Step 4: When Stuck (≥2 Attempts)

```bash
bash scripts/orchestrator.sh think
```

The orchestrator will force you to write a 3-hypothesis worksheet. **Your next report must include H1/H2/H3 or it will be rejected.**

---

## Helpers (Use These by Name)

| Helper | Purpose |
|---|---|
| `scripts/timebox.sh <secs> <cmd>` | Wrap brute-force commands (default 90s). |
| `scripts/source-dive.sh <repo> [tag]` | Grep open-source repos for unauth routes/auth bypasses. |
| `scripts/walkthrough-search.sh <name>` | Get HINTS for retired HTB boxes (no spoilers). |
| `bash scripts/context-broker.sh <topic>` | Don't know which file to read? Ask the broker. |

---

## What This File Replaces

- The old **orchestrator** and **tracker** modes are deprecated.
- Use `zero.sh` for the first command.
- Use `orchestrator.sh think` only when stuck.
- All other details are in `REFERENCE.md`.