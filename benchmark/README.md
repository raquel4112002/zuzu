# Nest benchmark harness

Turns "a weak model did well once" into a **measured model × box matrix**.
This is the empirical backbone the thesis needs — it closes the
"anecdotal, single-engagement comparisons" gap named in
`papers/the-nest.md` §7.1.

## What it measures (per run)

Every metric is derived from a file on disk — nothing is fabricated.

| Metric | Source | Why it matters |
|---|---|---|
| `outcome` | stop-gate conditions | solved_full / partial_user / blocker_documented / awaiting_human / failed |
| `user_flag`, `root_flag` | `loot/user.txt`, `loot/root.txt` | ground-truth success |
| `wall_clock_s` | `.bench.json` start→end | efficiency; compare models fairly |
| `hypotheses_total`, `confirmed`, `falsified`, `inconclusive`, `open` | `hypotheses.json` | how the model reasoned, not just if it won |
| `max_chain_depth` | `chains_to` graph | did it chain foothold→lateral→privesc (the Hard-box axis) |
| `nest_commit` | git | reproducibility: filter a matrix to one Nest version |

`max_chain_depth` is the key Hard-box signal: Easy boxes solve at depth
1–2; Hard boxes need 3+ chained stages. Tracking it shows whether a
scaffolding change actually improved *chaining* or just luck.

## Protocol (one benchmark cell = one model on one box)

1. **Fix the Nest version.** Commit any changes first so `nest_commit`
   is meaningful. Every run in a comparison must share the commit.
2. **Set the model under test** in OpenClaw (this agent's provider/model),
   then start a fresh session so the contract reloads cleanly.
3. **Start the run:**
   ```bash
   bash benchmark/bench.sh start <box> --ip <spawn-ip> --model "<label>" --hostname <host>
   ```
   `--model` is just the label you record; it must match what OpenClaw is
   actually configured to use. Keep labels stable (e.g. `qwen2.5-72b-instruct`).
4. **Drive the loop** exactly as normal (`think.sh`, `hypotheses.sh`, …).
   No benchmark-specific behaviour — the point is to measure the real loop.
5. **Score when the engagement ends** (flag captured, or blocker documented,
   or awaiting-human):
   ```bash
   bash benchmark/bench.sh score <box>
   ```
6. **Repeat** across the matrix, then aggregate:
   ```bash
   bash benchmark/bench.sh report --md > benchmark/RESULTS.md
   bash benchmark/bench.sh report --csv > benchmark/results.csv
   ```

## Fair-comparison rules (write these into the thesis method section)

- **Same Nest commit** across every cell of a comparison.
- **Same time budget** per box (record it; a run killed at the budget is
  still a valid `failed`/`blocker_documented` data point).
- **Same box state** — use freshly-spawned HTB instances; note the spawn.
- **N≥3 runs per cell** if you want variance (LLM sampling is stochastic).
  `report.py` keeps the *best* outcome per cell for the matrix, but the CSV
  keeps every run so you can compute pass@k / variance.
- **Blind the model to walkthroughs** — the loop may search the web
  (`recon-*`), which for a *retired* box can surface writeups. For a clean
  capability measurement, prefer active boxes, or note when a writeup was
  consulted. (This is a real confound; document it.)

## Advanced: automated matrix via subagents

OpenClaw's `sessions_spawn` accepts a `model` override, so a matrix can be
driven programmatically: spawn one subagent per (box, model), each briefed
to run the loop against a given spawn IP, then score. This only makes sense
once the boxes are reachable (HTB VPN up) and is a heavy live operation —
see `benchmark/MATRIX.md` (to be written) before automating. Start manual.

## The results log (what you build graphs from)

Every engagement ends with `bench.sh finish` (wired into the contract —
PILOT.md and QUICKSTART.md make it mandatory). It captures:

- **Automatic** (from disk): outcome, user/root flag, **time-to-user-flag**
  and **time-to-root-flag** (from the flag files' mtimes vs start), wall
  clock, hypothesis counts, `max_chain_depth`, nest_commit.
- **Model-supplied** (from the `session_status` tool at finish): total /
  input / output **tokens**, **cost**, and a one-line note.

Two artifacts accumulate:

- `benchmark/RESULTS-LOG.md` — human, append-only, **sanitized** (no IPs, no
  flag values). One row per run. Safe to commit and cite in the thesis.
- `benchmark/results.csv` (via `bench.sh report --csv`) — flat table for
  pandas/matplotlib. Same columns, one row per run (keeps every run, not just
  the best — use it for pass@k / variance).

Graph ideas straight from the CSV: solve-rate by model×difficulty, tokens vs
outcome, time-to-root distribution, chain-depth vs difficulty, cost per solve.

## Files

- `boxes.json` — box registry (public metadata only; no flags/IPs/spoilers).
- `bench.sh` — CLI: `start` / `finish` (=`score`) / `report` / `list` / `status`.
- `score.py` — single-engagement metric extractor (incl. time-to-flag, tokens).
- `report.py` — matrix aggregator (Markdown / CSV).
- `log_row.py` — appends a sanitized row to `RESULTS-LOG.md`.
- `results/` — per-run JSON rows (**gitignored** — carry the IP).
- `RESULTS-LOG.md`, `results.csv`, `RESULTS.md` — sanitized aggregates (commit-safe).
