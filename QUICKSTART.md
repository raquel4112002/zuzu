# QUICKSTART — Attack a target (1 page, no thinking required)

> If you have a target IP/hostname, this is the only file you need to read.
> Every other file is referenced from here.

---

## The one command you always run first

```bash
bash scripts/zero.sh <target-ip-or-hostname>
```

It does, automatically:
1. Creates `reports/<target>/` with the right folder structure.
2. Confirms reachability.
3. Quick port scan (top-1000, timeboxed 90s).
4. Fingerprints the stack (Wing FTP? WordPress? Jenkins? AD?).
5. **Tells you exactly which runbook or archetype to follow.**

The output is deterministic. Just read it and follow the action plan.

---

## What to do with the action plan

zero.sh always ends in one of three states:

### A. ✨ Runbook match
```
✨ RUNBOOK MATCH (copy-paste, end-to-end):
   ✅ playbooks/runbooks/wing-ftp-rooted.md
```
**→ Open that runbook. Follow it literally. It has every command + expected
output. Do not improvise — the runbook is validated end-to-end.**

### B. 📚 Archetype match
```
📚 ARCHETYPE MATCH:
   ✅ playbooks/archetypes/<name>.md
```
**→ Open that archetype. It has fast checks (≤5min), deep checks, known
CVEs, and common pitfalls. No literal copy-paste, but a tight checklist.**

### C. 📋 No match
**→ Read `knowledge-base/llm-hacking-context.md`** for the generic decision
tree, then `playbooks/web-app-pentest.md` or `playbooks/network-pentest.md`.

---

## When stuck (≥ 2 attempts on same step)

```bash
bash scripts/orchestrator.sh think
```
The orchestrator detects loops and forces you to write a 3-hypothesis
worksheet. Reading the worksheet output — not improvising — is the way out.

If the orchestrator says "stuck-gate triggered", **your next report MUST
include H1/H2/H3 hypothesis lines** or it will be rejected.

---

## Helpers — use these by name, not by reinventing

| Helper | When |
|---|---|
| `scripts/timebox.sh <secs> <cmd>` | **Wrap every brute-force / dir-bust.** Default 90s. |
| `scripts/source-dive.sh <repo> [tag]` | Open-source app + auth wall? Source-dive BEFORE brute force. |
| `scripts/walkthrough-search.sh <name>` | Retired HTB box? Get HINTS (no spoilers). |
| `scripts/new-target.sh <ip>` | Standalone folder creation (zero.sh calls it for you). |
| `bash scripts/context-broker.sh <topic>` | Don't know which file to read? Ask the broker. |

---

## Hard rules (no exceptions)

1. **Never write loose files in `reports/`** — always `reports/<target>/...`.
2. **No blind code execution** — ask Raquel before running any code from the internet.
3. **Wrap brute-force in timebox.sh** — 90s budget for hydra; if it exhausts, change vector, don't bigger-wordlist it.
4. **Source-dive before brute force** on open-source web apps.
5. **Reports/memory/state stay LOCAL** — never commit. See `AGENTS.md` § 8.
6. **Per-target work in `reports/<target>/{nmap,web,creds,loot}/`** — created by `new-target.sh`/`zero.sh`.

---

## When you finish

1. Write the report at `reports/<target>/report.md` using `templates/attack-report-template.md`.
2. Add the CVE/exploit-db ID to `knowledge-base/cve-to-exploit-cache.md` if it was new.
3. If the target was distinctive enough, **author a runbook** in `playbooks/runbooks/<name>.md` so the next operator (or LLM) goes faster.

---

## What this file replaces

This is the **single entry point**. The legacy AUTOPILOT.md still exists for
reference but you do not need it for normal engagements — `zero.sh` covers
the same ground in 90 seconds.

If `zero.sh` is missing or broken, fall back to:
- `AUTOPILOT.md` Section F (Auto-Recon)
- `AGENTS.md` for the rules
- `knowledge-base/llm-hacking-context.md` for the manual decision tree
