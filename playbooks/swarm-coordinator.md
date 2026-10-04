# Playbook: Swarm Coordinator (parallel multi-front box attack)

**Use when:** you want to capture flags faster on ONE box by attacking several
independent fronts at once. One coordinator (the brain) connects the dots;
worker subagents (the hands, SAME model) each test a different front.

**Do NOT use** to parallelize a single sequential kill-chain (foothold→user→
root is serial) or to race multiple *models* on one box (that's a different,
pass@k experiment — keep it out of the per-model benchmark; see bench `--blind`).

## The loop (coordinator = you)

1. **Recon + model.** Run `recon-fast.sh`, write `surface.md` + `target-model.md`,
   seed the bank with ≥5 hypotheses across DIFFERENT fronts (services/ports/
   vectors) — breadth is what parallelism buys you. (AGENTS.md R3.)

2. **Plan the fan-out.**
   ```bash
   bash scripts/swarm.sh plan --workers 3
   ```
   It splits OPEN hypotheses into **parallel-safe** (read-only / independent)
   and **exclusive** (mutate shared box state → upload queue, brute, listener).

3. **Spawn workers for the parallel-safe set** — one per hypothesis, concurrently,
   with `sessions_spawn` (isolated, cleanup=delete), task =
   ```bash
   bash scripts/swarm.sh worker-brief <id>
   ```
   Workers test ONE hypothesis, write evidence to `reports/<t>/lanes/<id>/`, and
   REPORT BACK — they never edit the bank.

4. **Serialize the exclusive set.** Only ONE worker at a time per shared
   resource — the worker-brief makes them `lease.sh acquire <resource>` first.
   Never run two uploaders / two brute-forcers / two listeners at once (the
   pdfminer self-DoS and fail2ban walls we already hit).

5. **Connect the dots (your real job).** As each worker reports:
   - write its result to the bank: `hypotheses.sh result <id> confirmed|falsified "<note>" --evidence <path>`
   - **chain** confirmed ones into the next phase (`hypotheses.sh chain`),
   - fold NEW LEADS into `target-model.md`,
   - cross-findings: lane A's version + lane B's open port may be one chain.
   You see all lanes; the workers see only theirs. The synthesis is the win.

6. **On a foothold:** STOP fanning out exploits. Capture it (`flag.sh`), then
   switch to the **serial** kill-chain: `postfoothold.sh` (one artefact) →
   user.txt FIRST (objective #1) → privesc. Privesc is coordinator-serial.

7. **Repeat** from step 2 until `stop-gate.sh` passes.

## Guardrails (why this doesn't become expensive chaos)

- **Cap workers** (3–4). More lanes ≠ faster past the point the bank has
  independent work — it just multiplies cost (each lane ≈ 1×).
- **Time-box every lane**; kill low-EV lanes. `loop-guard.sh` still applies per
  target (shared), so a repeated dead move anywhere trips the pivot.
- **One writer.** Only the coordinator mutates `hypotheses.json` — no write races.
- **Leases auto-expire** (`lease.sh gc`) so a crashed worker can't deadlock.
- **Small worker contexts** are the antidote to R18 bloat on wide boxes: N small
  contexts beat one 280k-token monolith.

## Requirement

Workers are spawned with `sessions_spawn`, so the coordinator must run in a
harness that exposes that tool. (Models driven through the plain Ollama path
only have `exec` and cannot spawn — run the swarm from a harness that can.)

## Tools
- `scripts/swarm.sh plan | worker-brief <id> | lanes`
- `scripts/lease.sh acquire|release|list|gc <resource>`  (upload-queue, ssh-brute, callback:<port>, target-rate)
