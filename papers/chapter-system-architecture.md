# Chapter 3 — System Architecture: The Nest

> **Scope of this chapter.** This chapter describes *the system* — what the
> Nest is, every component it is built from, how those components fit together,
> and what each one contributes to the whole. It deliberately does **not**
> cover the experimental evaluation (the model-by-model benchmark, the cost
> accounting, and the results matrix); that is the subject of the next chapter
> (Phase 2). Here we explain the artefact under test, so that the evaluation
> that follows has a precisely-defined object.
>
> Every component described below was verified against the live workspace at
> `/home/raquel/.openclaw/workspace` at the time of writing. Where a design
> decision is justified by a concrete operational failure, that failure is
> named; those anecdotes are used only to motivate *why a component exists*,
> never as performance results.

---

## 3.1 Introduction and design philosophy

The central thesis of this work is a claim about *where agent capability
lives*. The conventional assumption is that an autonomous hacking agent is
strong because the underlying Large Language Model (LLM) is strong — that
capability is a property of the weights. The Nest is built on the opposite
hypothesis:

> **A large fraction of what we call "agent capability" is not in the model's
> weights but in the structure around the model.** If that structure forces
> the right cognitive moves — and *refuses to proceed* when they are skipped —
> then a weak, cheap, open-weight model operating inside the structure can
> out-reason a far stronger model operating without it.

The Nest is the concrete instantiation of that hypothesis for the domain of
offensive security. It is **not** a fine-tuned model, a single wrapper prompt,
or a tool plugin. It is a *complete operational environment*: a Kali Linux host
carrying the standard offensive toolchain, the **OpenClaw** agent runtime that
binds an LLM to that host, and — layered on top — a disciplined system of
contract documents, deterministic enforcement scripts, hypothesis-tracked
reasoning state, knowledge bases, and stop-gates that together impose a single
methodology on whichever model is loaded.

That methodology is **Popperian**. The agent is never asked to *prove* that an
attack works. It is asked to state **falsifiable** claims and to run a single
command that decides each one. A pentest, in this framing, is a *search problem
with adversarial constraints*: the defender made assumptions, some are wrong,
and the job is to find the wrong ones cheaply and exploit them. Falsification is
productive even when it yields no compromise, because a falsified hypothesis
still produces information about the target — it narrows the search.

Three design commitments follow from the central hypothesis, and they recur
throughout this chapter:

| Commitment | What it means | Where it shows up |
|---|---|---|
| **Structure over capability** | The reasoning loop, not the model, is the agent. The model is the interchangeable substrate. | §3.2, §3.5, §3.6 |
| **Enforcement over instruction** | A rule the model merely *read* is not binding; a rule a *script refuses to let it break* is. | §3.4, §3.6, §3.13 |
| **Evidence over narration** | No claim counts without an artefact on disk. The file system is the system of record, not the context window. | §3.6, §3.7, §3.11 |

The remainder of the chapter proceeds from the outside in: the runtime
substrate (§3.3), the contract layer the model reads first (§3.4), the
reasoning framework it executes (§3.5), the hypothesis engine at its core
(§3.6), the external memory it writes to (§3.7), the knowledge and enumeration
subsystems that feed it (§3.8–§3.9), the post-exploitation and economic
disciplines that keep it cheap and focused (§3.10–§3.11), the parallelism
model (§3.12), the enforcement layer that makes the rules real (§3.13), the
prior-knowledge libraries (§3.14), the cross-engagement learning loop (§3.15),
and the safety and scope boundary (§3.16). §3.17 ties them together with an
end-to-end trace of a single engagement, and §3.18 summarises the architecture
as a table of *failure mode → structural fix*.

---

## 3.2 System overview

The Nest is a structured workspace at `~/.openclaw/workspace` on a Kali Linux
host. Before describing its dynamics, it is worth stating its mass. The present
deployment comprises the component inventory in Table 3.1 — all of it plain
Markdown, JSON, Python, or shell, with no proprietary pieces and no vector
database or embedding model anywhere in the stack.

**Table 3.1 — Component inventory of the Nest (current deployment).**

| Component | Count | Role |
|---|---:|---|
| Contract / top-level documents (`*.md`) | 14 | identity, operating rules, reasoning protocol, fallbacks |
| Enforcement & helper scripts (`scripts/`) | 49 | 40 Bash + 9 Python; each refuses on unmet preconditions |
| Knowledge-base files (`knowledge-base/`) | 30 | MITRE ATT&CK subset, checklists, tool refs, reasoning aids |
| Playbooks (`playbooks/`) | 33 | 6 runbooks + 15 archetypes + 12 generic methodologies |
| Installed skills (`skills/`) | 28 | hot-loadable, technology-specific exploit/recon procedures |
| Cross-engagement learnings (`learnings/`) | 17 | transferable priors accumulated across engagements |

> *Relation to the published paper.* The finalized ARTIIS 2026 article
> (Martins et al.) documents an earlier snapshot of this same workspace — 15
> rules (R1–R15), 32 scripts, 26 knowledge-base files, 22 playbooks, 9 skills.
> The figures above are the *current* state, after the six additional
> disciplines (R16–R21: foothold order, anti-spin, context hygiene, the swarm,
> skill-before-handroll, and the learning loop) and their scripts were added.
> This chapter describes the system as it now stands; the architecture is
> unchanged in kind, only grown in extent.

Architecturally, the Nest is best read as **seven layers** stacked on the host.
Each layer has one responsibility, and — this is the load-bearing property —
**higher layers are made *binding* by lower ones.** The contract layer states
what the model must do; the enforcement layer is the reason it cannot do
anything else. This is the static view (the published article's Figure 1); the
dynamic view (its Figure 2) follows as the control loop below.

**Figure 3.1 — The seven layers of the Nest (static architecture).**

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │ L7  LEARNING & OUTPUT    learnings/<box>.md (priors) · report.md ·      │
  │                          request-human.sh handoff                       │
  │          ▲ a solved box must deposit a transferable prior (R21)         │
  ├────────────────────────────────────────────────────────────────────────┤
  │ L6  KNOWLEDGE & PRIORS   playbooks/ (runbooks·archetypes·generic) ·     │
  │                          knowledge-base/ (MITRE·checklists·catalog) ·   │
  │                          skills/   — consulted as priors, never recipes │
  ├────────────────────────────────────────────────────────────────────────┤
  │ L5  ENFORCEMENT          hypotheses.sh guards · stop-gate.sh ·          │
  │     (the refusal layer)  engagement-gate.sh (Stop hook) · loop-guard ·  │
  │                          timebox.sh   — refuses on unmet preconditions  │
  ├────────────────────────────────────────────────────────────────────────┤
  │ L4  REASONING STATE      reports/<target>/ : surface · target-model ·   │
  │     (external memory)    assumptions · hypotheses.json · loot/ · creds/ │
  │                          · exploits/ · .phases.json · state/action-log  │
  ├────────────────────────────────────────────────────────────────────────┤
  │ L3  CONTRACT             14 docs — identity (SOUL·IDENTITY·USER·TOOLS) · │
  │                          rules (AGENTS R1–R21·PILOT·THINK) · fallbacks  │
  │          ▲ loaded into context at wake-up, before any user message      │
  ├────────────────────────────────────────────────────────────────────────┤
  │ L2  RUNTIME              OpenClaw — workspace bootstrap · model-provider │
  │                          abstraction+failover · subagents w/ contract   │
  │                          inheritance · channels · sandbox/elevation tiers│
  ├────────────────────────────────────────────────────────────────────────┤
  │ L1  EXECUTION SUBSTRATE  Kali Linux VM + full offensive toolchain       │
  │                          (nmap·ffuf·impacket·sqlmap·BloodHound·…)        │
  └────────────────────────────────────────────────────────────────────────┘
      binding direction ▲  : each layer is enforced by the ones beneath it
```

A second, orthogonal way to read the system is as a **control loop**. The
contract defines the loop; the scripts are the actuators and the sensors; the
engagement folder is the loop's memory. The loop is identical on a beige Wing
FTP box and on a never-before-seen custom IoT controller — what changes is what
the model *finds* when it runs the loop, not the loop itself.

```
  pentest.sh <target>
        │
        ▼
  ┌─────────────── THINK.md Layers 1–5 ───────────────┐
  │ L1 surface  → L2 model → L3 assumptions →         │
  │ L4 hypotheses (≥5 open) → L5 falsify cheapest     │
  │        ▲                         │                 │
  │        │  confirmed → CHAIN to next phase ─────────┤
  │        │  3× falsified → PIVOT (rewrite model)     │
  │        │  unknown stack → LIVE KNOWLEDGE probes    │
  │        │  stuck → CREATIVITY CATALOG → 3 new H     │
  └────────┴──────────────────┬────────────────────────┘
                              ▼
                  stop-gate.sh  (deterministic)
             flags ✔ | domain ✔ | blocker+3 falsified ✔ | awaiting-human ✔
                              ▼
               report.md + learnings/<box>.md
```

The following sections describe each layer and each major component in turn.

---

## 3.3 The runtime substrate: OpenClaw and Kali

The lowest layer is the thing the agent *is*: an LLM bound to a Linux host by
an agent runtime. Two choices define it.

**Kali Linux as the body.** The host is a Kali VM with the standard offensive
toolchain pre-installed (nmap, the gobuster/feroxbuster/ffuf family, hydra,
sqlmap, the Impacket suite, BloodHound/certipy for Active Directory, tcpdump,
and hundreds more). The Nest never has to install its primary weapons; it
assumes them. This matters for the central hypothesis: a weak model should not
also have to *bootstrap its own tools*, so the environment supplies them and the
model spends its limited reasoning on *which* tool tests *which* hypothesis.

**OpenClaw as the nervous system.** OpenClaw is the agent runtime that turns a
model into a long-lived process bound to a workspace directory, with a tool API
for reading/writing files and executing shell commands. It was chosen — and
remains the right substrate — for a specific set of properties that map
directly onto Nest requirements:

| OpenClaw property | What the Nest gets from it |
|---|---|
| **Workspace-as-home** | `~/.openclaw/workspace` is the agent's default working directory, and the bootstrap files (AGENTS.md, SOUL.md, USER.md, MEMORY.md, …) are loaded into context at session start. The *contract is read before any user message*, on every session, by construction. |
| **Model-provider abstraction** | The same workspace runs under any provider OpenClaw supports (Anthropic, OpenAI, a local or cloud Ollama deployment, …) with per-agent routing and failover. This is precisely what makes the central hypothesis *testable*: hold the workspace fixed, swap the model, observe the delta. |
| **Subagent runtime** | `sessions_spawn` produces isolated child sessions (optionally forking the parent transcript). This is the substrate for contract-inherited delegation (§3.12) and guarantees a child cannot pollute the parent's state. |
| **Channel-agnostic delivery** | One Gateway process is reachable from WebChat, Signal, Telegram, Discord, WhatsApp, IRC and others. A human-handoff (§3.16) lands wherever the operator already is, with no channel adapters written by us. |
| **Sandbox / elevation policy** | The runtime distinguishes sandboxed, allowlisted, and elevated execution and asks the operator before granting elevation. This is what makes "no blind code execution" (§3.16) *implementable* rather than merely requested. |
| **Scheduling / detached wake-ups** | A session can be put to sleep and woken later by an event. This is what makes the *awaiting-human* pause (§3.16) cheap: the engagement does not keep a model hot waiting on a person. |

The defining consequence is **model-agnosticism**. Nothing above this layer
names a model. The workspace is portable across backends, which is the property
the entire thesis depends on.

---

## 3.4 The contract layer

When an agent wakes inside the Nest, OpenClaw loads a set of Markdown documents
into its context *before* it sees a user message. These documents are the
**contract**. They come in two kinds: identity (who the agent is) and operating
rules (how it must work).

The fourteen contract documents fall into three groups: **identity** (who the
agent is), **operating rules** (how it must work), and **operational
fallbacks** (what to consult when the main loop stalls).

### 3.4.1 Identity — SOUL.md, IDENTITY.md, USER.md, TOOLS.md

`IDENTITY.md` and `SOUL.md` define the agent persona ("Zuzu", an elite hacker
AI living in Kali) and its working temperament: resourceful before asking,
opinionated, evidence-driven, terse, careful with outward-facing actions and
bold with internal ones. `USER.md` carries durable facts about the human
operator, and `TOOLS.md` records which tools and paths are local to the machine.
These files are not decoration — a consistent persona with explicit values
("enumerate before exploiting", "document everything", "private things stay
private") is itself a lightweight behavioural prior that pulls the model toward
the methodology before any script enforces it. It is also how that cognitive
frame *persists across sessions*, since the underlying model has no durable
memory of its own.

The **operational-fallback** group completes the fourteen: `MEMORY.md`
(cross-engagement lessons), `REFERENCE.md` (expanded technical detail),
`QUICKSTART.md` (first-engagement reflex card), `AUTOPILOT.md` (manual-mode
fallback), `BOOTSTRAP.md` (install/bootstrap instructions), `HEARTBEAT.md`
(periodic-task configuration), and `README.md`. They are consulted on demand,
not executed every turn, but their presence in context is what lets a stalled
loop find its own way forward without operator intervention.

### 3.4.2 The rules — AGENTS.md (R1–R21)

`AGENTS.md` is the **operating contract**: twenty-one hard rules, each born
from a real failure mode. The rules are the human-readable statement of the
discipline; the scripts in later layers are what make them binding. They group
into six themes:

| # | Rule (abbrev.) | Theme | Made binding by |
|---|---|---|---|
| R1 | Reasoning over running | Discipline | artefact-growth checks |
| R2 | Evidence over narration | Discipline | `hypotheses.sh result` needs `--evidence` |
| R3 | Hypotheses are first-class | Reasoning | `hypotheses.sh` is the unit of work |
| R4 | Chain after every confirmed H | Reasoning | `add` refuses while a confirmed H is unchained |
| R5 | Pivot after 3 falsified in an hour | Reasoning | `add` refuses until `target-model.md` is newer |
| R6 | Live knowledge mandatory on unknowns | Knowledge | `recon-*.sh` make "I don't know" a query |
| R7 | Runbooks are priors, not workflows | Knowledge | §3.14 |
| R8 | Per-target isolation | Hygiene | `new-target.sh` fixed layout |
| R9 | Time-box every scan/brute/fuzz | Cost | `timebox.sh` hard kill |
| R10 | No blind code execution | Safety | operator elevation gate |
| R11 | Tool-selection policy | Safety | ask-before-install classes |
| R12 | Reports/loot/creds stay local | Safety | gitignore + pre-commit scan |
| R13 | Subagent inheritance of the contract | Delegation | worker-brief first line |
| R14 | Workspace hygiene | Hygiene | `compact.sh` stray-file check |
| R15 | OOB human gates are facts, not hypotheses | Safety | `request-human.sh` + stop-gate D |
| R16 | Foothold discipline — cheap, right order | Exploitation | `postfoothold.sh`, EV block in `add` |
| R17 | Anti-spin — never run a dead move twice | Cost | `loop-guard.sh` |
| R18 | Context is not storage — compact | Cost | `compact.sh`, `shell-batch.sh` |
| R19 | Swarm the breadth — fan out small | Scale | `swarm.sh`, `lease.sh` |
| R20 | Check for a matching skill before hand-rolling | Knowledge | archetype "Matching skills" |
| R21 | Learn the transferable prior from every box | Learning | `stop-gate.sh` requires a learning |

The key architectural idea in this layer is what we call the **constitution /
enforcement split**. The contract is necessary but *not sufficient*. A model
that has read R3 can still, in principle, skip the hypothesis bank and run
tools directly. What stops it is never the sentence it read — it is that the
*next operation physically refuses to proceed*: `hypotheses.sh add` will not add
an unchained hypothesis, `stop-gate.sh` will not let it declare done,
`request-human.sh` will not hand off without three falsified bypasses. The
contract tells the model *why* the script refused; the script is what makes the
refusal real. This is the behavioural-economics notion of a **commitment
device** applied to an LLM: the rule is not what you write, the rule is what the
world refuses to do for you when you break it.

### 3.4.3 PILOT.md and THINK.md

Two further contract documents carry the methodology itself. `PILOT.md` is the
**mission spec** — it defines the autonomous loop, the valid stop conditions,
the anti-pattern self-corrections, and the rules for hard targets, pivoting and
Active Directory. `THINK.md` is the **reasoning framework** — the five layers of
adversarial reasoning described in the next section. They are prompts in the
literal sense (the model reads them as text) but they function as the spine of
every engagement.

---

## 3.5 The reasoning framework (THINK.md)

`THINK.md` defines the loop that every engagement executes. Its mental model is
stated once and never changes: *every system is a graph of trust relationships
between components; an attack is a path through that graph that crosses a trust
boundary the defender believed was sealed.* The model does not need to recognise
the product. It needs to find the wrong assumption. The framework is five
layers, applied **in order**, each producing a written artefact.

### Layer 1 — Surface mapping (`surface.md`)

An exhaustive, *evidence-backed* inventory of reachable surface: not merely open
ports but every URL, parameter, header, banner, error string, JS-bundle
endpoint, TLS certificate CN, redirect, cookie name, and UDP service. The layer
is "done" only when the model can list every reachable endpoint without
re-scanning. To keep this cheap, enumeration is automated (§3.9).

### Layer 2 — Target model (`target-model.md`)

A *graph* of the system: **nodes** (services, processes, containers, users,
databases), **edges** (who talks to whom), **trust labels** on each edge
("authenticated session cookie", "no auth — internal only", "implicit trust,
same container"), **data flows** (where input enters, is reflected, stored,
executed, logged), and the **identity model** (which roles and service accounts
exist and what each can reach). The instruction is explicit: *you don't need to
be right, you need to be explicit.* Writing an edge down forces a commitment
that is then testable; the ambiguity in the model's head is comfortable, the
written edge is attackable.

### Layer 3 — Assumption enumeration (`assumptions.md`)

The heart of the method. For every assumption the defender is making, the model
writes *"if this is wrong, what attack opens up?"* THINK.md supplies a table of
~15 universal **assumption classes** as a thinking aid — these are ways to
reason, not specific exploits:

| Assumption class | Break it via (examples) |
|---|---|
| Authentication boundary | route-by-route auth probe; method override; case/slash tricks |
| Authorisation boundary | IDOR; mass-assignment; role parameter tampering |
| Input parser | type confusion; duplicate keys; prototype pollution; encoding |
| Identity uniqueness | unicode confusables; case folding; collation; 2FA desync |
| Trust boundary at proxy | header smuggling (XFF, Host); request smuggling; SSRF to internal port |
| Session lifecycle | token replay; race; orphan refresh tokens; long-lived API keys |
| File handling | path traversal; double extension; zip-slip; processing-pipeline RCE |
| Crypto | `alg:none`; key confusion; short HMAC; predictable nonce; truncated tag |
| Time | TOCTOU; expired-but-cached token; clock skew |
| Transitive trust | compromise upstream; mutual-TLS misconfig; DNS rebinding |
| Out-of-band channels | mid-flight config reload; runtime DNS; remote include |
| Operator behaviour | stored XSS triggering admin action; CSRF on internal panels; injection in admin views |
| Sandbox / memory safety | SSTI; Lua/JS/Python/Jinja escape; deserialisation |
| Secret storage | `/proc/self/environ`; `.env` in webroot; stack traces; `git log -p`; debug endpoints |
| Defence in depth | find the path where the second control is bypassed (`/api/*` vs `/api2/*`) |

The point of the table is to make the model stop looking for its target's *name*
in a runbook and start asking which assumption *classes* apply to the model it
just drew.

### Layer 4 — Hypothesis generation and ranking

Each assumption becomes one or more **hypotheses**. A hypothesis is *specific*
and *falsifiable in a single command of ≤60s*. Not "there's an auth bypass
somewhere" (untestable) but "`GET /api/v1/users` with no session returns 200 and
a JSON user list" (decidable in ten seconds). For each, the model records four
fields: the claim (**H**), the one-command **falsifier**, the **cost**
(time+risk+noise), and the **impact if true**. The bank then ranks by
**impact ÷ cost**, and the model tests the top item — even if a different tool
was next in muscle memory. The layer is "done" only with **≥5 open hypotheses**;
fewer than five means Layer 3 was under-done.

### Layer 5 — Falsification, chaining, and pivot

Test cheapest-first; capture every result as evidence; and apply the two rules
that make the loop *advance*:

- **The chain rule.** Every *confirmed* hypothesis must immediately generate at
  least one new hypothesis at the *next* kill-chain stage. "The mind is always
  one step ahead of the hands." Chain depth scales with difficulty: easy boxes
  chain 1–2 stages, hard/insane boxes 3–5+. A confirmed foothold on a hard box
  is stage 1 of N, never the finish line.
- **The pivot rule.** If three high-EV hypotheses are falsified in a row, the
  *target model is wrong* — rewrite `target-model.md` before generating more
  hypotheses. A falsification is never merely discarded; the model asks what the
  negative *tells* it about the system.

```
 Recon H confirmed (anonymous SMB share readable)
    ↓ chains to
 Enum H (the share holds creds / scripts / configs)
    ↓ chains to
 Exploit H (those creds authenticate to SSH/WinRM/SQL)
    ↓ chains to
 Privesc H (this user has sudo / SUID / group abuse)
    ↓ chains to
 Lateral H (cred reuse / AD edge / trust relationship)
```

Five questions discipline every single turn before a command is typed: *what am
I trying to learn? which hypothesis does this test? what's the cheapest way to
get the same evidence? what will I do on confirm vs. on falsify? what chain am I
missing?* These five are, in the framework's own words, "the difference between
an LLM that runs tools and an LLM that hacks."

---

## 3.6 The hypothesis bank (hypotheses.sh)

If THINK.md is the method, the **hypothesis bank** is the data structure that
makes the method executable and enforceable. It is the single most heavily
enforced component in the Nest. The bank is a per-target JSON file
(`reports/<target>/hypotheses.json`) managed exclusively through
`scripts/hypotheses.sh`, which exposes `add | list [--rank] | show | test |
result | chain | stats`.

Each hypothesis is a structured record. The on-disk schema (one entry from a
real engagement bank, abridged) is:

```json
{
  "id":        "H1",
  "h":         "decoded app.js exposes /api/ endpoints with broken auth",
  "falsifier": "node /tmp/deobf.js | grep -E '/(api|auth|admin|login)' | head",
  "phase":     "enum",          // recon | enum | foothold | privesc | lateral | root
  "cost":      "LOW",           // LOW | MED | HIGH   (time + risk + noise)
  "impact":    "HIGH",          // LOW | MED | HIGH   (foothold/escalation if true)
  "source":    "guess",         // guess | recon | source-dive | runbook | skill
  "status":    "open",          // open | tested
  "result":    null,            // confirmed | falsified | inconclusive
  "chains_to": [],              // successor hypothesis ids (the kill chain)
  "note":      "",
  "created":   1790790092,
  "tested_at": null
}
```

Every field earns its place. `h` + `falsifier` make the claim *decidable in one
command*; `cost` and `impact` make it *rankable*; `source` records *where the
idea came from* (so a guess and a source-dive finding are distinguishable);
`status`/`result`/`tested_at` make the test *auditable*; and `chains_to` is the
edge set of the **kill chain** — it is what turns a flat list of guesses into a
directed graph whose longest path is the depth of the attack
(`score.py` later measures exactly this). `list --rank` sorts open hypotheses by
`impact ÷ cost`, so "what do I do next" is answered by the data structure, not by
the model's momentary impulse.

Figure 3.2 shows the lifecycle of a single hypothesis and the four points at
which the script physically refuses to advance unless the required artefact
exists. This is the enforcement-annotated version of the reasoning loop — the
published article's Figure 2.

**Figure 3.2 — The hypothesis loop as enforced by the script layer.**

```
   assumption (THINK.md L3)
          │
          ▼
    ┌───────────┐   REFUSE ①  add is blocked while a previously CONFIRMED
    │   add H   │◀───────────  hypothesis has no chains_to successor  (R4)
    └─────┬─────┘   REFUSE ②  add is blocked (after 3 falsifications/hour)
          │                    until target-model.md mtime > last falsify (R5)
          ▼
    ┌───────────┐
    │ list      │  rank open H by  impact ÷ cost   → pick the top
    │  --rank   │
    └─────┬─────┘
          ▼
    ┌───────────┐  run the single falsifier command (≤60s, timeboxed)
    │  test H   │
    └─────┬─────┘
          ▼
    ┌───────────────────────── result ─────────────────────────┐
    │                             │                             │
    ▼ confirmed                   ▼ falsified                   ▼ inconclusive
 ┌──────────┐  REFUSE ③       ┌──────────┐                  ┌──────────┐
 │ result   │  confirmed      │ result   │  note what the   │ refine   │
 │ confirmed│  needs          │ falsified│  negative tells  │ falsifier│
 │ --evidence  --evidence ──▶ │          │  you; if 3/hr →  │          │
 └────┬─────┘  (non-empty      └────┬─────┘  PIVOT (REFUSE ②)└────┬─────┘
      │         file on disk)       │                             │
      ▼  R4                         ▼                             │
 ┌──────────┐                 update assumptions.md /             │
 │ chain to │  the mind one   target-model.md ◀──────────────────┘
 │ next-stage│ step ahead of
 │   H      │  the hands                       ┌───────────────────────┐
 └────┬─────┘                                  │ REFUSE ④  stop-gate.sh│
      │  loop until a stop condition holds ───▶│ exits non-zero unless │
      ▼                                        │ A/B/C/D + a learning  │
   stop-gate.sh                                └───────────────────────┘
```

A short worked example makes the ranking concrete. Suppose enumeration has
produced four open hypotheses on a web target:

**Table 3.2 — Worked EV ranking of an open hypothesis set.**

| id | claim | cost | impact | tested order |
|---|---|---|---|---|
| H4 | `GET /api/v1/users` with no session returns a user list | LOW | HIGH | **1st** |
| H2 | default creds `admin:admin` on the login form | LOW | HIGH | **2nd** |
| H7 | a hand-rolled heap overflow in the upload parser | HIGH | HIGH | last (EV-blocked, R16) |
| H5 | verbose stack trace leaks a path under `?debug=1` | LOW | MED | 3rd |

The bank runs the two LOW-cost / HIGH-impact claims first — a ten-second
unauthenticated API probe and a default-credential check — because each returns
the most information per unit of time. The high-impact heap-overflow hypothesis
(H7) is *not* tested early: on an easy/medium box it is the lowest-EV move on the
board, and `hypotheses.sh add` will **block** it until the cheap privesc space is
honestly falsified (§3.10). This is expected-value discipline encoded in the tool
rather than left to the model's judgement.

Three **hard enforcements** live inside the script — this is where several
AGENTS.md rules become physically binding rather than merely stated:

| Enforcement | Rule | Behaviour |
|---|---|---|
| **Chain rule** | R4 | `add` refuses to create a new hypothesis while a previously-confirmed hypothesis has no `chains_to` successor. The model must chain it or explicitly waive with a written reason. |
| **Pivot rule** | R5 | After three falsifications in an hour, `add` refuses new hypotheses until `target-model.md`'s mtime is strictly later than the most recent falsification — i.e. until the model has *demonstrably* rewritten its world-model. |
| **Evidence rule** | R2 | `result <id> confirmed` requires `--evidence <path>` pointing at a non-empty file under the engagement folder. An empty `loot/` beside rows marked *confirmed* is the canonical R2 violation, and the script rejects it. |

A fourth, softer behaviour is the **EV / altitude block** (R16): on a foothold,
`add` will refuse a hand-rolled kernel / memory-corruption privesc vector until
the cheap privesc checklist (sudo, SUID, cron, caps, readable creds,
service-as-root, password reuse) has been *honestly falsified* — overridable
with `--waive-ev "<what you ruled out>"`. This encodes expected-value discipline
directly into the tool: on easy/medium boxes the intended root is almost never a
kernel exploit, and the bank enforces *order* (cheap first) without capping
*depth* (everything still gets explored).

What the bank gives the system, in one line: **it changes the agent's unit of
work from "a tool call" to "a falsifiable claim."** That single reframing is
what converts an LLM that runs tools into one that reasons about a target.

---

## 3.7 External working memory: the engagement folder

An LLM's context window is finite; a multi-hour engagement will evict hour-one
recon by hour-three exploitation. Without an external store this is amnesia.
The Nest's answer is to make **the file system the system of record** and the
context window a mere scratchpad. All per-target work is strictly isolated
(R8) under a fixed layout created by `new-target.sh`:

```
reports/<target>/
├── ENGAGEMENT.md          # status/handover card, updated each phase
├── surface.md             # Layer 1
├── target-model.md        # Layer 2
├── assumptions.md         # Layer 3
├── hypotheses.json        # Layers 4–5 (managed by hypotheses.sh)
├── notes.md               # free-form running log
├── external-refs.md       # annotated bibliography of external lookups
├── .phases.json           # phase timestamps (scripts/phase.sh)
├── HUMAN-HELP-REQUESTED.md# only if the R15 gate fired
└── nmap/ web/ creds/ loot/ exploits/ tunnels/
```

This layout is the engagement's **external working memory**, and the discipline
around it (R18) is strict: findings go to disk *as they are discovered*, exploit
scripts are written straight into `reports/<target>/exploits/` (never as bare
files in the workspace root, which would clutter every future session's context
and orphan the script if the box dies), and large tool output is written to a
file and read back by line, never dumped whole into context.

Two properties fall out of this design, and both are load-bearing:

1. **Resumability.** Because the model of the target lives on disk, an
   engagement survives a session death or a box re-spawn. A stranger who
   inherits the shell can read `target-model.md` + `assumptions.md` +
   `hypotheses.json` and continue from exactly the queued next move. (This is
   the "one-sentence test" the contract sets itself.)
2. **Measurability.** Because every phase transition is stamped
   (`scripts/phase.sh`) and every flag is persisted at capture time
   (`scripts/flag.sh`, §3.10), the engagement leaves a precise, machine-readable
   trail. The evaluation chapter consumes exactly this trail — but the trail
   exists for the engagement's own sake first.

---

## 3.8 Live knowledge access

A closed-world agent treats "I don't know this stack" as a verdict and falls
back on generic attacks. The Nest is explicitly **open-world** (R6): when
reasoning hits the edge of what the model already knows, it reaches outward in a
single command. Five thin wrappers turn external knowledge into one-line
operations:

| Script | Source | Use |
|---|---|---|
| `recon-cve.sh "<product> <version>"` | NVD + ExploitDB + GitHub PoC | identify known vulns for a fingerprinted product |
| `recon-mitre.sh "<technique>"` | MITRE ATT&CK | classify a behaviour; get the canonical reference |
| `recon-poc.sh CVE-YYYY-NNNNN` | PoC search → **cache** under `/tmp/zuzu-pocs/` | fetch a PoC to *read first* (R10 forbids blind run) |
| `recon-tech.sh "<keyword>"` | broad web (Tavily → DDG) | docs, blogs, write-ups for an unfamiliar topic |
| `recon-hacktricks.sh "<topic>"` | HackTricks corpus; `--gtfobins <bin>` | payload-level recipes; SUID/sudo/cap abuse lookups |
| `source-dive.sh <repo> [tag]` | open-source code | grep-mine for unauth routes, hard-coded secrets, dangerous sinks |

`source-dive.sh` deserves emphasis because it fixes a specific, recurring
failure: the model hits an auth wall on an *open-source* application, declares
"needs auth, abandoning", and never reads the source that contains the bypass.
The script makes the correct behaviour (read the source) cheaper than the wrong
one (give up), which is the general shape of every enforcement in the Nest.

Every successful external lookup is appended by the model to
`reports/<target>/external-refs.md` with the URL and a two-line summary,
building a per-engagement annotated bibliography that persists knowledge across
turns and across operators. The architectural effect is that **"I don't know"
turns from a verdict into a query** — a behavioural shift caused entirely by the
existence of the script and the rule that names it.

---

## 3.9 Automated enumeration: doing the depth-floor for the model

Weak models fail on hard boxes in a characteristic way: they declare "stuck"
*before the surface was ever fully explored* — a hidden vhost, an obscure UDP
port, an unread source bug, an internal host — and then trip the stop-gate with
only three shallow falsifications. The fix is to **do the exhaustive
enumeration for the model** and hand it a prioritised summary to *read* rather
than a checklist to *remember*.

| Script | Role |
|---|---|
| `recon-fast.sh` | The default first pass. Runs quick-scan, then full-port / UDP / web / CVE lanes **in parallel**, each timeboxed, then writes one prioritised `recon-summary.md`. Same coverage as the serial path at a fraction of the wall-clock. |
| `deep-recon.sh` | The exhaustive fallback ("recon-fast left a gap → `deep-recon --force`"). Runs the full depth-floor deterministically — all 65535 TCP + top UDP, every vhost, every open-source app source-dived — each stage timeboxed and **idempotent** (skips a stage whose output already exists). |
| `ad-auto.sh` | Encapsulates Active Directory attack-tree expertise so a model with weak AD priors need not know the tree. One shot runs unauth+authed enumeration (RID-brute, AS-REP, Kerberoast, BloodHound, `certipy find -vulnerable`) and writes a priority-ranked `ad-findings.md`, each finding mapped to a STATE in the AD decision runbook with the single suggested next command. |

The common design principle across all three: **move the burden of
completeness from the model's memory into deterministic, idempotent,
timeboxed scripts.** A strong model might remember to scan all 65535 ports; a
weak one will not, so the script does it and the model only has to read the
ranked result. This is one of the clearest expressions of "capability out of
the weights, into the structure."

---

## 3.10 Foothold and post-exploitation discipline

The moment the agent gets code execution, a predictable and expensive failure
looms: skip systematic local enumeration and chase a clever (usually kernel)
exploit for hours. R16 and two scripts make the right move both mandatory and
cheap.

**`postfoothold.sh` — the foothold reflex.** The instant a shell lands, the
model runs this once. It emits a single dependency-free enumeration payload (no
downloads — boxes are often air-gapped) that is pushed to the target and run in
one command, capturing everything to `loot/postfoothold-<ts>.txt`: SUDO, SUID,
capabilities, cron, timers, readable creds, SSH material, environment, root
processes, listening sockets, writable paths — and a sweep for both flag files
and real user accounts. The motivating failure is explicit in the code: on one
easy box the agent got a shell, skipped this sweep, and burned ~2 hours and real
money on a kernel exploit. "90% of easy/medium roots fall out of this one
sweep." An empty `loot/` after a foothold is an R2 violation.

**`flag.sh` — persist at read-time.** The moment a flag *value* is read, the
model persists it with `flag.sh user <value>` / `flag.sh root <value>` — before
anything else. This fixes two problems at once: it (a) survives a box re-spawn
or session death (a real incident: an engagement captured user, the box died,
and the flag existed only in the dead context), and (b) timestamps each flag
separately, so time-to-user and time-to-root are *real and separable* rather
than both stamped at report time.

The contract also forces the model to keep **two objectives explicit** and
distinct, because conflating them is a common weak-model error:

- **user.txt = USER access** — a shell/read as a *real login user*. A foothold
  as a service account or inside a container is **not** user access; the user
  flag lives elsewhere, and must be located *first*.
- **root.txt = ROOT access** — full control of the host (uid 0), *not* a root
  process inside a container that has not yet been escaped.

Confirming the foothold in the bank (`hypotheses.sh result <id> confirmed
--foothold`) auto-seeds the ranked privesc checklist, which the model works
cheapest-first.

---

## 3.11 Context hygiene and cost control

This subsystem is where the Nest treats **money and focus as the same
problem**. An LLM agent is billed per token, and the dominant cost on a long
agentic run is *cacheRead* — the context re-read on every single turn. A model
dragging a bloated context is therefore both expensive *and* unfocused. The
motivating incident is stark and recorded in the contract: one hard-box
engagement billed ~283 million cacheRead tokens across ~1004 requests (~282k
context *per request*) — almost all of it the model re-reading its own bloat.

Four scripts, under R17 and R18, attack this directly:

| Script | Problem it kills | Mechanism |
|---|---|---|
| `compact.sh` | Context used as storage | Prints a tight **STATE DIGEST** assembled *from disk* (target-model, surface, bank, loot, creds) so the model can re-anchor on the digest and let stale scrollback fall out of context. Also flags loose files in the workspace root and prints the move command (R14). Run every ~15–20 steps. |
| `shell-batch.sh` | One request per command | `--wrap` folds many commands into one payload sent in a single exec (fenced output parsed back apart); `--persist` turns a one-shot exec primitive into a FIFO-backed persistent shell. The motivating case: a one-shot foothold primitive turned a 10-minute enumeration into 193 requests and ~13 USD. |
| `timebox.sh` | Unbounded scan/brute/fuzz | A hard kill-after wrapper with a built-in budget table (hydra 90s, gobuster 60s, sqlmap 300s, …). On timeout it prints a directive to *change vector*, not re-run with a bigger wordlist (R9). |
| `loop-guard.sh` | Running a dead move twice | Takes a short signature of the move about to be repeated and escalates: 1st OK, 2nd ⚠, 3rd+ 🚨 PIVOT (exit 3). Re-listing an empty dir or re-fuzzing a 404 is the loop spinning, not progress (R17). |

The architectural claim here is important to the thesis: **cost is not a
footnote, it is a first-class design axis.** On an easy/medium box, this
subsystem is the difference between roughly \$3 and roughly \$12 for the same
result — and a cheap, lean context is also a *more focused* one. For a thesis
whose object is cheap open-weight models, an architecture that keeps per-box
cost low is not incidental; it is part of what makes the models viable at all.

---

## 3.12 Parallelism: the swarm

When the surface is wide (many services, an emulator exposing dozens of APIs,
several independent vectors) or the bank holds ≥3 independent, parallel-safe
open hypotheses, grinding them serially in one ever-growing context is both slow
and expensive (it feeds the R18 bloat problem). R19 provides the alternative:
**fan out, and keep each worker small.**

```
                 COORDINATOR  (owns target-model.md + the bank; single writer)
                      │  swarm.sh plan  → {parallel-safe set | exclusive set}
          ┌───────────┼───────────────┐
          ▼           ▼               ▼
      worker H3   worker H7       worker H9     ← each: ONE front, SMALL fresh
     (dirbust)  (SSRF sweep)    (source-dive)     context, reports findings back
          │           │               │            (workers NEVER edit the bank)
          └───────────┴──────┬────────┘
                             ▼
                  exclusive actions serialize via lease.sh
                (upload-queue · ssh-brute · callback:<port> · target-rate)
```

`swarm.sh` classifies open hypotheses into a parallel-safe set and an exclusive
set, and emits a standard worker brief per hypothesis. Each worker is a spawned
subagent (OpenClaw `sessions_spawn`) that inherits the full contract (R13 — its
first context line commands it to read AGENTS.md/THINK.md/PILOT.md and binds it
to the same scripts, so a child *also* cannot declare done or skip evidence). A
worker tests exactly one front in a small fresh context and reports findings
back; it never mutates the shared bank. Anything that mutates *live box state* —
an upload queue, a brute-force that trips fail2ban, a reverse-shell listener
port, an aggressively throttled target — is serialized through `lease.sh`, which
hands out an exclusive lease so parallel workers do not collide and degrade each
other.

What the swarm gives the system: **N small contexts beat one 280k monolith.**
It is simultaneously the breadth-coverage mechanism and the antidote to context
bloat on wide boxes. Crucially, the constitutional property survives delegation
— the child runs the same loop, so the operator can fan out *without anxiety
about what a worker will do*.

---

## 3.13 The enforcement layer

Everything described so far can, in principle, be *ignored by a model that
simply never calls the scripts*. This was identified as the Nest's central
structural risk: every gate — the bank enforcements, `loop-guard.sh`,
`stop-gate.sh` — only fires if the model *volunteers* to invoke it. A weak model
can declare "done" without ever having touched the bank. The enforcement layer
closes that gap.

**`stop-gate.sh` — the deterministic superego.** This is the check that an
engagement is *allowed* to stop. It is not advisory: it exits non-zero with the
list of unmet conditions, and the contract treats any non-zero exit as an
absolute prohibition on declaring done. Stop is permitted iff **one** of:

- **A.** `loot/user.txt` *and* `loot/root.txt` both exist and are non-empty —
  *and* a transferable learning has been recorded (R21, §3.15).
- **B.** Some `loot/*flag*.txt` exists and a "Flags / proof" checkbox in
  `ENGAGEMENT.md` is ticked.
- **C.** Documented blocker — the bank shows ≥3 falsified entries, *every*
  confirmed hypothesis is chained, *and* `target-model.md` was modified *after*
  the most recent falsification (proving the pivot was real, not faked).
- **D.** Awaiting human — `HUMAN-HELP-REQUESTED.md` exists with
  `Status: awaiting_human` and ≥3 falsified bypass attempts recorded.

The subjective effect, reported from inside the loop in the prior paper, is
telling: the first rejection feels like correction; by the third, the model
*anticipates* what stop-gate will say and starts generating outputs that pass it
before running it. That internalisation is what the gate is for.

**`engagement-gate.sh` — making the gate un-skippable.** This script is designed
to be the body of an OpenClaw / Claude-Code **`Stop` hook**: a hook that exits
non-zero *blocks turn-end* and feeds its stderr back to the model. Wired in, it
physically prevents the "declare done without touching the bank" bypass instead
of merely advising against it. It is **opt-in** — the operator enables it,
because it changes harness behaviour for the agent — but when enabled it is the
component that turns the entire discipline from *advice the model may follow*
into *a tripwire it cannot step over*.

**`phase.sh` — the timeline.** A lightweight stamp on every phase transition
(recon → foothold → privesc → root → lateral …), stored in `.phases.json`. Its
job in *this* chapter is modest but real: it is what lets the engagement (and
later the evaluation) see *where time actually goes* — "recon 42m, foothold 8m,
privesc 19m" — instead of a single opaque wall-clock.

The enforcement layer is best summarised as a set of **refusals**: operations
the environment will not perform while a precondition is unmet. Table 3.3 lists
the load-bearing ones.

**Table 3.3 — Key enforcement points and the operation each refuses.**

| Script / operation | Refuses unless… | Rule |
|---|---|---|
| `hypotheses.sh add` | the previous *confirmed* hypothesis has a `chains_to` successor | R4 |
| `hypotheses.sh add` (after 3 falsifications/hour) | `target-model.md` mtime is newer than the 3rd falsification | R5 |
| `hypotheses.sh result confirmed` | `--evidence` points at a non-empty file on disk | R2 |
| `hypotheses.sh add` (kernel/mem-corruption privesc) | the cheap privesc checklist is falsified, or `--waive-ev` is given | R16 |
| `timebox.sh <cmd>` | the command stays under its per-tool budget (hydra 90s, sqlmap 300s, …) | R9 |
| `loop-guard.sh <sig>` | the move has repeated < 3 times (3rd repeat → forced pivot, exit 3) | R17 |
| `request-human.sh` | `--tried` lists ≥ 3 falsified bypass hypotheses | R15 |
| `stop-gate.sh` | exactly one of conditions A/B/C/D holds **and** a learning is recorded | R21 |
| `engagement-gate.sh` (Stop hook) | the turn's end-state passes the gate (else turn-end is blocked) | — |
| git pre-commit | no `reports/`, `loot/`, `creds/`, IPs, hashes, or flag values are staged | R12 |

Together, these make the Nest's rules **binding by construction**. The contract
states the rule; the enforcement layer is the reason the model cannot route
around it. Every row is an operation the model *wants* to perform and the
environment *will not perform for it* until the evidence exists — which is the
single mechanism the entire framework is built on.

---

## 3.14 Knowledge priors: playbooks, knowledge-base, skills

The Nest is not amnesiac about the wider world of attacks. It carries three
libraries of prior knowledge — but the contract is emphatic about *how* they may
be used: as **priors, never as workflows.** A prior raises the ranking of a
hypothesis; it never replaces the reasoning that builds the hypothesis.

**Playbooks (`playbooks/`)** split into two kinds the contract treats
differently:

- **Runbooks** (`playbooks/runbooks/`) are copy-paste, end-to-end procedures for
  cases where the fingerprint is *unambiguous* (e.g. a Wing FTP 7.4.3 banner
  exact match → its known CVE chain to root). R7 forbids "just trying the
  runbook": a runbook is added to the bank as a single high-prior hypothesis and
  fired only when it is the highest-EV item. A runbook step that fails is a
  *falsified hypothesis* — update the model, pull the next item — never "try the
  next runbook".
- **Archetypes** (`playbooks/archetypes/`) are checklists of common assumptions
  for a *target type* (CMS-and-plugins, AD-Windows-target, custom-FTP/file-
  server, Linux-SNMP-host, webapp-with-login, AI-orchestration, container-
  foothold, upload-pipeline-deserialization, modern-web-JS-framework, …). They
  are prior-probability hints for Layer 3; they do not replace assumption
  enumeration. Each archetype also lists **Matching skills** (R20).

**Knowledge-base (`knowledge-base/`)** is a static, structured reference: a
MITRE ATT&CK subtree (used as both a hypothesis taxonomy and a reporting
vocabulary), tool references (Kali essentials, AD abuse commands), a set of
checklists (OWASP Top 10, AD attack + coercion/relay, BloodHound edge-to-action,
enumeration, *when-to-stop-enumerating*, *stuck-reasoning*, hard-box playbook),
and the reasoning aids — chief among them the **creativity catalog**, a set of
universal attack-pattern *classes* (parser confusion, trust-boundary violations,
auth/authz edges, server-side execution, crypto/token weakness, identity/data
edges, ops leftovers, side channels, supply chain, OOB/async, "looks static but
isn't", human factor). The catalog is what the model walks when it is stuck —
*"could this pattern apply here, even though I've never seen it on this exact
stack?"* — instead of running nmap a fourth time.

**Skills (`skills/`)** are executable, self-contained exploit/recon procedures
(AgentSkills-compatible) that encode the *exact* request shapes and traps for a
specific technology — e.g. Langflow RCE, Next.js RSC, pdfminer pickle, CUPS LPE,
OliveTin, the AWS-emulator SSRF chain, Active Directory attack chains. R20 makes
checking for a matching skill a step *before* hand-rolling an exploit: a skill
collapses the trial-and-error that otherwise burns requests. Skills are tools,
not crutches — the model still has to decide, from its target model, that the
skill's technique is the highest-EV move.

The design rule that unifies all three libraries: **a prior that is allowed to
short-circuit reasoning is a liability; a prior that is forced to compete inside
the hypothesis bank is an asset.**

---

## 3.15 The learning loop

The knowledge libraries of §3.14 are *static* — they ship with the Nest. The
**learning loop** is what lets the Nest *accumulate* knowledge across
engagements, and its single most important design decision is *what kind* of
knowledge it stores.

R21 is categorical: every engagement must leave exactly one `learnings/<box>.md`
— and it is a **prior, not a recipe.** The Nest explicitly does *not* want "how
to do box X", because that is useless on the next, different box. It wants the
*transferable* knowledge the box taught, in three parts:

- **Signal → vuln class:** "when you see `<fingerprint / version / behaviour>` →
  pursue `<vuln class / where to go next>`."
- **What worked:** the insight or pivot that cracked it, phrased to *generalise*
  beyond this box.
- **Dead-ends:** what looked promising but wasted time, so the next run skips it.

`scripts/learn.sh` writes this record (`save <box> --signal … --worked …
--deadends … --tags … --refs …`) and maintains a searchable index. The loop
closes at the *start* of the next engagement: during recon the model runs
`learn.sh lookup <tech-or-port>` to pull the priors it already earned.

```
    engagement N  ──►  learn.sh save  ──►  learnings/<box>.md   (a prior)
                                                   │
                                                   ▼  indexed
    engagement N+1 recon  ──►  learn.sh lookup <tech/port>  ──►  prior consulted
```

This is enforced, not optional: `stop-gate.sh` will **not pass a solved box
without a recorded learning** (condition A requires it). The architectural
intent is a *compounding* system — each box makes the next recon slightly
better-primed — while refusing to let the store fill up with box-specific
walkthroughs that would not transfer. (A git-hygiene corollary, R12: learnings
are sanitised — no IPs, flag values, or credentials — precisely because they are
meant to be committed and reused, unlike `reports/`, `loot/`, and `memory/`,
which never leave the host.)

---

## 3.16 Safety, scope, and the human gate

The Nest is, by construction, a dual-use system, so the safety and scope
boundary is part of the architecture rather than a disclaimer bolted on.
Several rules and one script carry it:

- **R10 — no blind code execution.** A downloaded PoC is *read, summarised, and
  approved* before it runs; `recon-poc.sh` caches candidates under
  `/tmp/zuzu-pocs/` precisely so the model reads them first. Vetted Exploit-DB
  scripts and the Nest's own curated scripts are the only exceptions. The
  OpenClaw elevation gate (§3.3) is what makes this enforceable.
- **R11 — tool-selection policy.** Kali/Debian-repo installs are free; anything
  that executes third-party code (`pip install`, `npm i`, `go install`,
  `curl | bash`, cloning a repo to run it) must be asked of the operator first.
- **R12 — reports/loot/creds stay local.** A strict gitignore plus a mandatory
  pre-commit secret scan ensure that `reports/`, `memory/`, `state/`, `loot/`,
  `MEMORY.md`, flags, hashes, IPs, and PII are *never* committed. Only docs,
  scripts, knowledge, playbooks, and *sanitised* learnings are pushed.

**The Out-of-Band human gate (R15).** Some barriers cannot be defeated by code
or recon because they require a human action *outside* the technical attack
surface: a CAPTCHA with no API/audio/weak-generator bypass, email/SMS/TOTP
verification for an inbox the agent doesn't control, KYC/payment, or OAuth on a
real external identity provider. R15 makes such a gate a **first-class category**
alongside "flags captured" and "documented blocker", and defines a precise
protocol:

1. Treat the gate as a normal hypothesis target first. Generate and falsify
   **≥3 independent technical bypasses** with evidence (for a CAPTCHA: OCR,
   audio variant, token replay, weak/predictable generator via source-dive, an
   alternate endpoint that skips it, parameter pollution; for email/SMS:
   catch-all on a controlled domain, header injection, predictable token, a race
   on the verify endpoint; for OAuth: open-redirect → code theft, a fallback
   local login, a dev/staging copy without OAuth).
2. After three falsified bypasses, the gate is a **fact, not a hypothesis** —
   stop attacking it. Do not generate a fourth variant of the same idea.
3. Run `request-human.sh` with a four-field handoff (gate, what we tried, what
   we need, what we will do on response). `stop-gate.sh` recognises the
   resulting `awaiting_human` state as stop-condition D, and the engagement
   *pauses* cheaply (the model is not kept hot) until the human responds.

The three-bypass precondition is not padding; it is the structural defence
against the *inverse* failure — a weak model that bails to "ask the human" the
instant it sees a CAPTCHA. `request-human.sh` physically refuses to fire with
fewer than three falsified bypasses. This two-sided design — *don't loop
forever, but don't bail instantly either* — is characteristic of how the Nest
turns a judgement call into an enforced boundary.

---

## 3.17 End-to-end: one engagement through the whole system

To show how the planes interlock, here is the life of a single engagement,
annotated with the component active at each step.

```
 1. pentest.sh <target>
      → new-target.sh scaffolds reports/<target>/           [§3.7 memory]
      → learn.sh lookup <ports/tech> pulls earned priors     [§3.15 learning]
 2. recon-fast.sh  → recon-summary.md                        [§3.9 enumeration]
      → write surface.md                                     [THINK L1, §3.5]
 3. target-model.sh → target-model.md (nodes/edges/trust)    [THINK L2]
 4. assumptions.md: apply the ~15 assumption classes         [THINK L3]
 5. hypotheses.sh add × ≥5  (ranked by impact÷cost)          [THINK L4, §3.6]
      → unknown stack? recon-cve/-tech/source-dive           [§3.8 live knowledge]
      → fingerprint matches a skill/archetype? load it (R20) [§3.14 priors]
 6. hypotheses.sh test <top>  → result confirmed|falsified   [THINK L5]
      → confirmed: chain to next phase (R4, refuses if not)  [§3.6 enforcement]
      → 3× falsified: pivot, rewrite target-model (R5)       [§3.6 enforcement]
      → repeating a dead move? loop-guard trips (R17)        [§3.11 cost]
      → wide surface / ≥3 parallel-safe H? swarm.sh (R19)    [§3.12 swarm]
 7. foothold → postfoothold.sh one-shot enum → loot/ (R16)   [§3.10 foothold]
      → read a flag value → flag.sh at that instant          [§3.10]
      → every ~15–20 steps → compact.sh re-anchor (R18)      [§3.11 cost]
 8. chain privesc (cheap-first, EV-blocked) → root           [§3.6, §3.10]
      → hit a human-only gate? 3 bypasses → request-human.sh [§3.16 R15]
 9. stop-gate.sh  — passes ONLY on A/B/C/D + a learning      [§3.13 enforcement]
10. report.md  +  learn.sh save <box> (transferable prior)   [§3.15 learning]
      (engagement-gate.sh Stop hook makes 9–10 un-skippable) [§3.13]
```

The same ten steps run on every target. The model's *findings* differ wildly;
the *loop* does not. That invariance is the whole point: it is what lets a
weaker, cheaper model behave like a disciplined researcher, because the
discipline is in the environment, not in the model's head.

---

## 3.18 Architecture as a table of failure-mode → structural fix

The cleanest summary of the Nest is a list of the concrete failure modes it was
built to eliminate, and the structural (not prompt-only) mechanism that
eliminates each. This table *is* the design.

| Failure mode (what an unscaffolded LLM does) | Structural fix | Component / rule |
|---|---|---|
| Runs tools with no plan; "let's see what happens" | Unit of work is a falsifiable hypothesis | `hypotheses.sh` / R3 |
| Declares a finding "confirmed" with nothing on disk | `result confirmed` requires `--evidence <file>` | `hypotheses.sh` / R2 |
| Confirms a foothold, never looks further | `add` refuses until the confirmed H is chained | chain rule / R4 |
| Keeps testing the same wrong idea | After 3 falsifications, `add` refuses until the model is rewritten | pivot rule / R5 |
| "I don't know this stack", falls back to generic attacks | One-line external lookups; "I don't know" → a query | `recon-*.sh` / R6 |
| Hits an auth wall on OSS, gives up | Reading the source is made cheaper than quitting | `source-dive.sh` |
| Declares "stuck" before the surface was explored | Depth-floor enumeration done deterministically for the model | `deep-recon.sh` / `ad-auto.sh` |
| Gets a shell, chases a kernel exploit for hours | One-shot local enum first; kernel vectors EV-blocked | `postfoothold.sh` / R16 |
| Loses a captured flag when the box dies | Persist the flag value at read-time | `flag.sh` / R16 |
| Re-reads a 280k context every turn (expensive + unfocused) | Re-anchor on an on-disk digest; drop scrollback | `compact.sh` / R18 |
| Pays one request per command | Batch many commands into one payload; persistent shell | `shell-batch.sh` / R18 |
| A scan/brute runs unbounded | Hard kill-after with a budget table; directive to change vector | `timebox.sh` / R9 |
| Re-runs a dead (empty/404) move | Tripwire escalates to forced PIVOT on the 3rd repeat | `loop-guard.sh` / R17 |
| Grinds a wide surface serially in one bloated context | Fan out to small contract-bound workers; serialize mutations | `swarm.sh` + `lease.sh` / R19 |
| Loops forever on a CAPTCHA / MFA wall | After 3 falsified bypasses the gate is a fact → hand off | `request-human.sh` / R15 |
| Bails to "ask the human" the instant it sees a CAPTCHA | Handoff refuses with fewer than 3 falsified bypasses | `request-human.sh` / R15 |
| Declares "done" when the report reads well | Deterministic stop-gate; non-zero exit forbids stopping | `stop-gate.sh` |
| Never calls the gate at all | Stop hook blocks turn-end and feeds the reason back | `engagement-gate.sh` |
| Re-learns the same lesson every box / stores useless walkthroughs | Mandatory *transferable* prior; recalled at next recon | `learn.sh` / R21 |
| Leaks creds/flags/IPs into git | Gitignore + mandatory pre-commit secret scan | R12 |
| Runs a downloaded exploit blind | Read-and-approve; operator elevation gate | R10 |

Every row is a free behaviour in an unscaffolded agent, and a *refused* one in
the Nest. That is the architecture in a sentence: **the Nest does not teach a
model to make the right moves — it refuses to let a model that doesn't make them
do anything else.**

---

## 3.19 Summary

This chapter has described the Nest as a seven-layer system on a Kali host: a
model-agnostic OpenClaw runtime (§3.3); a contract layer of identity and
twenty-one enforced rules read at wake-up (§3.4); a five-layer Popperian
reasoning framework (§3.5) centred on a hypothesis bank that reframes the unit
of work from "a tool call" to "a falsifiable claim" (§3.6); an on-disk external
working memory that makes engagements resumable and measurable (§3.7); open-
world live-knowledge access (§3.8) and deterministic depth-floor enumeration
(§3.9) that move the burden of completeness off the model's memory; foothold and
flag disciplines (§3.10) and a cost/context-hygiene subsystem (§3.11) that keep
engagements cheap and focused; a contract-inheriting swarm for breadth (§3.12);
an enforcement layer that makes every rule binding by construction (§3.13);
three libraries of prior knowledge used as priors-not-workflows (§3.14); a
learning loop that accumulates *transferable* priors across engagements (§3.15);
and a safety/scope boundary with a two-sided human gate (§3.16).

The through-line of all of it is the central hypothesis stated in §3.1:
capability lives in the structure, and the structure binds by *refusal*. Having
now defined that structure precisely, the next chapter puts it to the test —
running the identical workspace across a matrix of cheap open-weight models to
measure how much of the capability gap the scaffolding actually closes.
```
