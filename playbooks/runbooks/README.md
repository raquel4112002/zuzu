# Runbooks — copy-paste, end-to-end attack scripts

Runbooks are **ordered, numbered, copy-pasteable** procedures designed for
weak (open-source) LLMs to follow literally. They differ from playbooks
and archetypes in three ways:

1. **No reasoning required** — every step is a literal command (with
   variables clearly marked `<like_this>`).
2. **Linear** — no decision points. If a step fails, the runbook tells
   you which other runbook to switch to.
3. **Self-contained** — every command includes its expected output so the
   model can verify success/failure without prior context.

## Available runbooks

| File | When to use |
|---|---|
| `wing-ftp-rooted.md` | Target = Wing FTP Server 7.4.3 (CVE-2025-47812). Full chain to root via wacky-style sudo+tarfile. |
| `linux-foothold-to-root.md` | You have ANY Linux shell as a non-root user. Standard privesc enumeration + 7 most common escalation paths. |
| `web-recon-to-foothold.md` | You have a HTTP target with no obvious framework hits. Linear web recon checklist. |
| `cracked-cred-pivot.md` | You cracked a password. How to fan out across SSH/SMB/WinRM/web/FTP/etc. systematically. |

## How to write a new runbook

Template:
```
# Runbook: <short title>

**Use when:** <one-line trigger condition>
**Produces:** <what the runbook gives you when done>
**Time:** <approx — e.g. 10 min if everything works>
**Prerequisites:** <list>

## Variables
TARGET=<target_ip>
HOSTNAME=<vhost or empty>
USER=<low-priv user if known>

## Step 1 — <action>
[concrete command]

Expected output:
[what success looks like]

If failed:
- <reason 1> → goto Step <X>
- <reason 2> → switch to runbook <other.md>

## Step 2 — ...

## End condition
You should now have: <concrete artifact: a flag, a shell, a hash, etc.>
```

## Rules for runbook authors

1. **Every command is literal copy-paste.** No "use the appropriate
   wordlist" — write `/usr/share/wordlists/rockyou.txt`.
2. **Every variable is declared at the top.** No "replace with target IP"
   in step 5 if you didn't define it in the variables section.
3. **Every step has an expected-output block.** "uid=1000(wingftp)" is
   how the model knows the exploit worked.
4. **Every failure mode points somewhere.** Either another step or
   another runbook. Never leave the model stuck.
5. **No prose paragraphs.** Bullet points and code blocks only.
