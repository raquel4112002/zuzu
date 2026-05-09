# Zuzu's Nest 🐱‍💻

> An OpenClaw workspace tuned to make any LLM — open-source or proprietary,
> weak or strong — operate as an autonomous offensive-security agent on
> Kali Linux. The nest is the multiplier.

## If you are an LLM waking up here, read these in order

1. **`AGENTS.md`** — the operating contract (auto-loaded each session).
2. **`PILOT.md`** — the autonomous-loop mission spec.
3. **`QUICKSTART.md`** — the one-page reflex card.

Then act. Do not wait for permission to start.

## If you are a human

The single command for any target is:

```bash
bash scripts/pentest.sh <target> [hostname]
```

It primes everything (folders, recon, archetype/runbook match, orchestrator
state) and prints the next command. Then the loop is:

```bash
bash scripts/orchestrator.sh think
# … execute …
bash scripts/orchestrator.sh report "<concrete result>"
# repeat
```

When the engagement feels done:

```bash
bash scripts/stop-gate.sh <target> --why
```

It deterministically tells you whether stopping is allowed (flag captured
or blocker fully documented with H1/H2/H3) or whether to keep going.

## File map

| Path | What it is |
|---|---|
| `AGENTS.md` | Operating contract (rules) |
| `PILOT.md` | Autonomous-loop mission spec |
| `QUICKSTART.md` | One-page reflex card |
| `REFERENCE.md` | Full technical detail |
| `AUTOPILOT.md` | Manual fallback when scripts break |
| `SOUL.md` / `IDENTITY.md` / `USER.md` / `TOOLS.md` | Identity & local notes |
| `BOOTSTRAP.md` | Recreate the nest on a new machine |
| `MEMORY.md` | Durable lessons (NOT per-target state) |
| `scripts/` | All helpers — `pentest.sh`, `zero.sh`, `orchestrator.sh`, `timebox.sh`, `source-dive.sh`, `walkthrough-search.sh`, `stop-gate.sh`, `context-broker.sh` |
| `playbooks/runbooks/` | Copy-paste end-to-end attack scripts |
| `playbooks/archetypes/` | Target-type checklists |
| `knowledge-base/` | Decision trees, MITRE deep dives, OWASP, AD checklists |
| `templates/` | Report templates |
| `learnings/` | Sanitised, commit-safe lessons |
| `reports/<target>/` | All per-target work — local only, never committed |
| `state/` | Orchestrator runtime state — local only |
| `loot/`, `memory/` | Local only |
| `skills/` | Installed AgentSkills (clawhub) |

## Discipline

- Per-target work goes under `reports/<target>/`. Never workspace root.
- Brute-force is wrapped in `scripts/timebox.sh` — every time.
- Open-source app + auth wall ⇒ `scripts/source-dive.sh` before brute-force.
- Stuck (≥ 2 attempts same step) ⇒ `orchestrator.sh think` → write H1/H2/H3.
- Reports / loot / state / memory are **never committed**.

That's it. The loop is simple. Run it.
