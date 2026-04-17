# BOOTSTRAP.md — Recreating Zuzu on a New Machine

## Prerequisites

- Kali Linux (VM or bare metal)
- OpenClaw installed and configured
- Node.js (for ClawHub): `nvm install 22`
- Git configured

## Quick Setup

### 1. Clone the repo
```bash
git clone git@github.com:raquel4112002/zuzu.git ~/.openclaw/workspace
cd ~/.openclaw/workspace
```

### 2. Run bootstrap
```bash
bash scripts/bootstrap.sh
```

### 3. Set environment variables
```bash
# Add to ~/.bashrc:
export TAVILY_API_KEY="your-key-here"
```

### 4. Install ClawHub CLI
```bash
npm i -g clawhub
```

### 5. Configure OpenClaw
Add to `~/.openclaw/openclaw.json`:
```json
{
  "env": {
    "TAVILY_API_KEY": "your-key-here"
  }
}
```

### 6. SSH key for GitHub
```bash
ssh-keygen -t ed25519 -C "zuzu@kali" -f ~/.ssh/github_zuzu
# Add public key to GitHub
# Add to ~/.ssh/config:
# Host github.com
#     IdentityFile ~/.ssh/github_zuzu
#     StrictHostKeyChecking accept-new
```

## What's in the Repo

```
├── AGENTS.md              # Operating rules (loaded by all sessions)
├── SOUL.md                # Zuzu's identity and personality
├── IDENTITY.md            # Name, creature, vibe
├── USER.md                # About Raquel
├── TOOLS.md               # Local tool notes
├── BOOTSTRAP.md           # This file
├── HEARTBEAT.md           # Heartbeat config
├── knowledge-base/
│   ├── mitre-attack/      # MITRE ATT&CK offensive reference
│   ├── tools/             # Kali tool reference guides
│   └── checklists/        # OWASP, AD attack checklists
├── playbooks/             # Step-by-step attack methodologies
│   ├── web-app-pentest.md
│   ├── network-pentest.md
│   └── privilege-escalation.md
├── reports/               # Attack reports (per target)
├── scripts/               # Bootstrap and utility scripts
│   └── bootstrap.sh       # Automated setup script
├── templates/             # Report and workflow templates
├── memory/                # Daily session logs
└── skills/                # ClawHub-installed skills
```

## Installed Skills

1. cybersec-helper
2. upstream-recon
3. network-device-scanner
4. git-secrets-scanner
5. docker-essentials
6. system-info
7. web-browsing
8. stealth-browser
9. tavily-search-pro
