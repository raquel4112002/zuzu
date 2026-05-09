# QUICKSTART — Engage a target (one page, no thinking required)

> If you have a target, this page is enough. Everything else is referenced
> from here. **Do not read other docs first** — run the loop, branch when
> the orchestrator points you somewhere.

---

## The one command

```bash
bash scripts/pentest.sh <target> [hostname]
```

It does, deterministically:

1. Creates `reports/<target>/` with the right folders + `ENGAGEMENT.md` card.
2. Runs `zero.sh` — quick scan + service fingerprint + archetype/runbook match.
3. Initialises the orchestrator state.
4. Prints the **next command** explicitly.

Examples:

```bash
bash scripts/pentest.sh 10.10.10.50
bash scripts/pentest.sh 10.129.244.98 airtouch.htb
```

---

## Then loop until done

```bash
bash scripts/orchestrator.sh think                         # next move
# … execute that move with real tools …
bash scripts/orchestrator.sh report "<concrete result>"    # log & advance
```

Repeat. The orchestrator drives phase progression automatically.

---

## When you think you're done

```bash
bash scripts/stop-gate.sh <target> --why
```

This is a **deterministic** check — exit 0 means stop is allowed; exit 1
means keep working. The script prints exactly what's missing. Don't
self-rationalise past it.

You're allowed to stop when **one** is true:

- ✅ `loot/user.txt` and `loot/root.txt` exist and are non-empty
- ✅ A flag file is in `loot/` AND a "Flags / proof" box is ticked in `ENGAGEMENT.md`
- ✅ Three hypotheses (H1/H2/H3) are written + falsified in `ENGAGEMENT.md` AND mirrored in `notes.md`

---

## When stuck (≥ 2 attempts on same step)

```bash
bash scripts/orchestrator.sh think
```

It detects the loop and forces the stuck-reasoning worksheet. The next
report you submit must include H1/H2/H3 lines — **the orchestrator will
reject reports without them once the gate trips.**

If the gate already tripped, also read:

- `knowledge-base/checklists/stuck-reasoning.md`
- `knowledge-base/creative-pivots.md`
- `knowledge-base/checklists/operator-fallbacks.md`

---

## Mandatory helpers (use them by name, don't reinvent)

| Helper | When |
|---|---|
| `scripts/timebox.sh <secs> <cmd>` | Wrap **every** brute-force / dir-bust. Default 90s. |
| `scripts/source-dive.sh <repo> [tag]` | Open-source app + auth wall? **Source-dive before brute-force.** |
| `scripts/walkthrough-search.sh <name>` | Retired HTB box? Get HINTS (no spoilers). |
| `scripts/new-target.sh <ip>` | Standalone folder creation (pentest.sh / zero.sh call it). |
| `scripts/context-broker.sh <topic>` | Don't know which doc to read? Ask the broker. |

---

## Hard rules (full list in `AGENTS.md`)

1. Never write loose files in `reports/` — always `reports/<target>/...`.
2. No blind code execution — review downloaded scripts first; ask for non-Kali installs.
3. Wrap brute-force in `timebox.sh`. If it busts, **change vector**, don't bigger-wordlist it.
4. Source-dive before brute-force on open-source apps.
5. Reports / memory / state / loot stay LOCAL — never commit. See `AGENTS.md § 3 R9`.
6. Per-target work in `reports/<target>/{nmap,web,creds,loot,exploits,tunnels}/`.
7. Stuck-gate triggered ⇒ next report MUST have H1/H2/H3 hypotheses.
8. Don't enumerate forever — credible exploit path = take it.

---

## After you finish

1. Write `reports/<target>/report.md` from `templates/attack-report-template.md`.
2. Update `ENGAGEMENT.md` status to `🟢 done` (or `🔴 blocked` with the documented blocker).
3. Add new CVEs to `knowledge-base/cve-to-exploit-cache.md`.
4. If the target was distinctive, **author a runbook** in
   `playbooks/runbooks/<name>.md` so the next operator (or LLM) goes faster.
5. Drop a sanitised lesson into `learnings/` if you discovered something
   reusable.

---

## Fallbacks (if `pentest.sh` is unavailable)

```bash
# Equivalent manual sequence
bash scripts/new-target.sh <target>
bash scripts/zero.sh <target>
bash scripts/orchestrator.sh init <target>
bash scripts/orchestrator.sh think
```

Don't deviate from this loop unless you have a reason backed by evidence.
