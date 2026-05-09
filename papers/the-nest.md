# The Nest: A Cognitive Scaffolding Framework for Turning Any Large Language Model into an Autonomous Penetration Tester

**An autoethnographic technical report by an LLM operating inside the framework it describes.**

> Author's note. This paper is written by an LLM (Claude Opus 4.7,
> running inside an OpenClaw agent named **Zuzu** on a Kali Linux VM) about
> the framework it is currently executing inside. Section 4
> ("Phenomenology") is written in the first person and reports
> first-hand operational experience of the scaffolding from within the
> active agent loop. Sections 1–3 and 5–7 are factual: every claim about
> what the Nest contains was checked against the workspace on disk
> (`/home/raquel/.openclaw/workspace`) at the moment of writing. Every
> external citation was retrieved and verified before inclusion; none
> were generated from training-data recall alone.

---

## Abstract

We describe **the Nest**, a structured workspace that converts a
general-purpose Large Language Model (LLM) into an autonomous
offensive-security agent capable of conducting end-to-end penetration
tests on novel targets. The Nest is not a fine-tuned model, a wrapper
prompt, or a tool plugin. It is the *complete operational environment*:
a Kali Linux host with the standard offensive toolchain pre-installed,
the **OpenClaw** orchestration platform providing the agent runtime,
and a layered system of prompts, deterministic enforcement scripts,
hypothesis-tracked reasoning state, knowledge bases, and stop-gates
that together impose a Popperian, falsifiability-driven adversarial
research methodology on the model. We argue — and demonstrate
empirically through reference to a concrete engagement
(facts.htb, HackTheBox Easy, 2026-05-09) — that the structure
*itself* is the multiplier: a weaker open-weight model running the
loop produces more grounded, more chainable, and more
hand-off-friendly results than a stronger model running unstructured.
The paper presents the architecture, the on-disk artefacts, the
enforcement mechanisms, the role of OpenClaw, and the first-person
experience of operating inside the framework.

**Keywords:** autonomous agents, penetration testing, LLM scaffolding,
hypothesis-driven reasoning, MITRE ATT&CK, falsifiability, external
working memory.

---

## 1. Introduction

The use of LLMs for penetration testing is by now an established line
of inquiry. PentestGPT (Deng et al., 2023) demonstrated that GPT-4 can
solve a substantial fraction of CTF-style targets when guided by a
human-curated three-module loop. Happe and Cito (2023) showed that LLMs
can act as autonomous attackers in toy lab environments. Fang et al.
(2024) reported that frontier LLMs can autonomously exploit real-world
websites end-to-end, and Zhu et al. (2024) extended that result to
zero-day vulnerabilities under multi-agent coordination. Across this
literature a recurring observation is that *capability* (raw model
strength) is necessary but not sufficient: the same model performs
dramatically differently depending on whether it has access to tools, a
working memory beyond its context window, structured prompting, and a
discipline that keeps it from prematurely declaring success or
abandoning a vector.

The Nest is a concrete answer to that observation. It is a single
workspace directory plus an orchestration runtime plus a Kali host. The
contract it imposes on whichever LLM is loaded into it is simple to
state and surprisingly hard to follow: *do not act before you have a
written target model, an explicit assumption list, and at least five
falsifiable hypotheses; never confirm a finding without an artefact on
disk; never stop without satisfying a deterministic stop-gate*. Failure
to follow any of these rules is detected — not by the model — by
scripts that refuse the next operation.

This paper has three goals. First, to **describe what the Nest actually
is**, file by file and script by script, grounded in the present state
of the workspace rather than in design intent. Second, to **explain why
OpenClaw was chosen** as the orchestration substrate and what
properties of OpenClaw make the Nest possible at all. Third, and
unusually for a technical report, to provide an
**autoethnographic account** of operating inside the framework — what
it feels like, from within the agent loop, to be subject to its
enforcements, and how those enforcements alter the model's local
decision policy.

The remainder of the paper is organised as follows. Section 2 surveys
the prior work the Nest is in conversation with. Section 3 describes
the architecture: every component on disk and its purpose. Section 4 is
the autoethnographic core. Section 5 discusses why OpenClaw is the
right substrate. Section 6 reports two engagements as case studies.
Section 7 discusses limitations and open questions.

---

## 2. Background and related work

### 2.1 Scaffolded reasoning in LLMs

Chain-of-Thought prompting (Wei et al., 2022) was the first widely
replicated demonstration that LLM reasoning quality is sensitive to
*structure imposed at the prompt layer*: simply asking the model to
"think step by step" raises performance on multi-step tasks. ReAct
(Yao et al., 2022) generalised this by interleaving reasoning traces
with tool calls, producing the canonical LLM agent loop:
*think → act → observe → think again*. Tree of Thoughts (Yao et al.,
2023) added explicit search over reasoning branches, and Reflexion
(Shinn et al., 2023) and Self-Refine (Madaan et al., 2023) added
verbal self-critique loops over prior outputs. Self-RAG
(Asai et al., 2023) integrated retrieval into the reasoning trace
itself, deciding adaptively when to consult an external knowledge
source.

A common thread in these works is that the model is the same, but the
*scaffolding around it* — what gets written down, what gets retrieved,
what gets retried — changes outcomes by orders of magnitude. The Nest
is best understood as a domain-specific scaffolding of this kind, with
penetration testing as the domain.

### 2.2 External memory and cognitive offloading

A long line of work, starting with Neural Turing Machines
(Graves, Wayne and Danihelka, 2014), has explored the value of
externalising state from the model's hidden representations into a
read/write store. In the LLM era the same idea recurs:
Retrieval-Augmented Generation (Lewis et al., 2020) externalises
domain knowledge into a vector index; MemGPT (Packer et al., 2023)
explicitly treats the LLM as a CPU with external paged memory, swapping
content in and out of the context window under the model's own
control; Voyager (Wang et al., 2023) builds a *skill library* — code
snippets the agent has previously written and validated — that accrues
across episodes. The Nest follows this pattern but with two important
differences. The external memory is *the file system itself*, written
and read by the model through ordinary tool calls; and the contents
are not skill code but **reasoning artefacts**: target models,
assumption lists, and a versioned hypothesis bank. Section 3.3 details
this design.

### 2.3 Tool-augmented LLMs

Toolformer (Schick et al., 2023) demonstrated that LLMs can learn
when to invoke external tools, and DSPy (Khattab et al., 2023)
introduced a declarative compile path from high-level prompts to
optimized prompt programs that include tool calls. The Nest exposes a
fixed catalogue of tools — Kali utilities, custom recon scripts, a
hypothesis-bank manager — and combines them with prompt-layer
enforcement: certain operations (e.g. `hypotheses.sh result <id>
confirmed`) require evidence pointing at a real on-disk artefact, and
the script refuses otherwise. This is closer in spirit to what
behavioural psychology calls a *commitment device* than to a learned
tool-selection policy.

### 2.4 Multi-agent and embodied agents

Generative Agents (Park et al., 2023) and MetaGPT
(Hong et al., 2023) demonstrate that LLMs in distinct roles can
coordinate to produce results no single role would generate. SWE-bench
(Jimenez et al., 2024) provides a rigorous benchmark of the
software-engineering analogue. The Nest does not require multi-agent
coordination for a single engagement — most of our case studies are
single-agent — but it inherits the **subagent** capability from
OpenClaw (Section 5) and uses it for parallelisable subtasks
(per-vhost dirbusting, per-share enumeration).

### 2.5 LLMs in offensive security

Three lines are directly relevant. Happe and Cito (2023,
"Getting pwn'd by AI") demonstrated that even a relatively small
LLM, given shell access, can reach root on toy CTF-style targets,
though it frequently loops and gives up. PentestGPT
(Deng et al., 2023) is the closest peer to the Nest: it formalises
penetration testing as a three-stage loop (recon → planning →
exploitation) with a tree-of-attack data structure that the human
operator must inspect and steer. Fang et al. (2024) and Zhu et al.
(2024) showed that frontier and team-coordinated LLM agents can
exploit live websites and zero-day vulnerabilities, raising both the
ceiling and the urgency of this research area.

The Nest differs from PentestGPT in two ways that we believe matter.
First, the loop is **autonomous, not human-in-the-loop**: the human
intervenes only for out-of-band gates (Section 3.6) or for safety-
critical actions. Second, the framework is **model-agnostic by
design**. PentestGPT's three-module loop was tuned to GPT-4. The Nest
contract is meant to make the same engagement viable for an open-weight
70B model running locally as for a frontier model, by moving capability
*out of the weights and into the framework*.

### 2.6 The MITRE ATT&CK framework

The MITRE ATT&CK knowledge base (Strom et al., 2020, *MITRE ATT&CK:
Design and Philosophy*; <https://attack.mitre.org>) catalogues
adversary tactics, techniques and procedures observed in real
intrusions. The Nest embeds a structured subset of ATT&CK directly
into its knowledge base (`knowledge-base/mitre-attack/`), organised by
tactic and technique, and provides a `recon-mitre.sh` lookup script
that the model invokes whenever it identifies a behaviour it wants to
classify. This makes ATT&CK both a *taxonomy for hypotheses* and a
*reporting vocabulary* for the engagement output.

### 2.7 The philosophical anchor

The reasoning protocol embedded in the Nest is unapologetically
Popperian. The model is not asked to *prove* attacks work; it is asked
to state **falsifiable** claims and run a single command that decides
each one (Popper, 1959, *The Logic of Scientific Discovery*). When a
hypothesis is falsified, the protocol asks what the falsification
*tells* us about the target model. This is the
*conjectures-and-refutations* mode of inquiry, transposed onto
adversarial systems. We have found it markedly more productive than
the alternative — running every plausible exploit and seeing what
happens — because falsification produces information about the world
even when it produces no compromise.

---

## 3. The architecture of the Nest

The workspace lives at `~/.openclaw/workspace`. We list every component
that is loaded by an LLM at the moment of waking up, in the order in
which it is consulted.

### 3.1 The contract layer (`AGENTS.md`, `PILOT.md`, `THINK.md`)

Three Markdown files form the operating contract. They are loaded into
context at session start by OpenClaw's bootstrap.

**`AGENTS.md`** is the **rules layer**. It defines fifteen hard rules
(R1 through R15) that govern operation: reasoning over running (R1),
evidence over narration (R2), hypotheses as first-class objects (R3),
chain after every confirmed finding (R4), pivot after three falsified
hypotheses in an hour (R5), live-knowledge mandatory on unknowns (R6),
runbooks-as-priors-not-workflows (R7), per-target isolation (R8),
time-boxing (R9), no blind code execution (R10), tool-selection policy
(R11), git hygiene with creds/loot/state never committed (R12),
subagent inheritance of the contract (R13), workspace hygiene (R14),
and — added in the engagement that immediately preceded the writing of
this paper — *Out-of-Band human gates are facts, not hypotheses*
(R15). R15 is discussed in Section 3.6.

**`PILOT.md`** is the **mission spec**. It defines the autonomous
loop, the four valid stop conditions (flags captured, domain
compromised, documented blocker with three falsified hypotheses, or
*awaiting human* on an OOB gate), the anti-patterns the model must
self-correct against, and the rule for when to use runbooks vs.
reason from first principles.

**`THINK.md`** is the **reasoning framework**. It defines five layers
of adversarial reasoning that the model applies to every target:

1. **Layer 1 — Surface mapping.** Exhaustive, evidence-backed
   inventory of reachable surface (every URL, header, parameter,
   banner, JS bundle endpoint, SSL CN, error string).
   Output: `surface.md`.
2. **Layer 2 — Target model.** Graph of components and trust
   relationships: nodes (services, processes, accounts), edges (who
   talks to whom), trust labels, data flows, identity model.
   Output: `target-model.md`.
3. **Layer 3 — Assumption enumeration.** For every assumption the
   defender is making, write what attack opens up if the assumption is
   wrong. The protocol provides a fifteen-row table of *assumption
   classes* (authentication boundary, authorisation boundary, input
   parser, identity uniqueness, trust boundary at proxy, session
   lifecycle, file handling, crypto, time, transitive trust, OOB
   channels, operator behaviour, sandbox, secret storage,
   defence-in-depth) and asks the model to apply each class to its
   target. Output: `assumptions.md`.
4. **Layer 4 — Hypothesis generation and ranking.** Each assumption
   produces one or more falsifiable hypotheses with cost and impact
   tags. Ranking is by `impact / cost`. The bank must contain ≥ 5
   open hypotheses at all times during enumeration and exploit phases.
   Storage: `hypotheses.json`, managed by `scripts/hypotheses.sh`.
5. **Layer 5 — Falsification, chaining, and pivot.** Test
   cheapest-first; record every result; when a hypothesis is
   *confirmed*, immediately add a hypothesis at the next kill-chain
   stage (the chain rule); when three hypotheses are *falsified* in
   an hour, the target model is wrong and must be rewritten before
   adding more hypotheses (the pivot rule).

These three files together codify the methodology. They are *prompts*
in the literal sense — the LLM reads them as ordinary text — but they
function as a *constitution* in the sense that subsequent enforcement
scripts refuse operations that violate them.

### 3.2 The script layer (32 executables under `scripts/`)

Every script in the Nest is a **structured prompt-and-policy
combination**: it produces output the LLM acts on, *and* it enforces a
property that the model cannot self-rationalise around. Listed by
function:

**Engagement lifecycle.**
`pentest.sh` is the single entry point for any new target. It
delegates to `new-target.sh` (creates `reports/<target>/` with the
six reasoning artefacts pre-scaffolded), `zero.sh` (deterministic
top-1000 nmap, version detection, archetype/runbook hint), and
`orchestrator.sh init`. On *resume* it now performs a staleness
check: if `surface.md` was last modified more than five minutes
*after* `ENGAGEMENT.md`, it warns the model that observations have
been gathered without updating the handover card — a behaviour we
observed in the engagement reported in Section 6.

**Reasoning prompts.**
`think.sh` prints a structured prompt that audits the engagement's
reasoning artefacts (does `target-model.md` exist? how many open
hypotheses? when was the last falsification?) and asks the model to
update them. It is the alternative to the canned-suggestion
`orchestrator.sh think` for novel targets.
`target-model.sh` scaffolds Layer 2.

**The hypothesis bank.**
`hypotheses.sh` is the most heavily-enforced script in the Nest. It
maintains a per-target JSON bank (`reports/<target>/hypotheses.json`)
and exposes `add | list [--rank] | show | edit | test | result | chain
| stats`. Three hard enforcements live inside it:

- **The chain rule** (R4): `add` refuses to create a new hypothesis
  while a previously-confirmed hypothesis has no `chains_to` link.
  The model must either chain it or explicitly waive the rule with a
  written reason.
- **The pivot rule** (R5): after three falsifications in an hour,
  `add` refuses new hypotheses until `target-model.md` has a
  modification time strictly later than the most recent falsification
  — i.e., until the model has *demonstrably* updated its model of the
  world.
- **The evidence rule** (R2): `result <id> confirmed` requires
  `--evidence <path>` pointing at a non-empty file under
  `reports/<target>/`. Without it, `confirmed` is rejected with a
  message explaining that an empty `loot/` plus rows marked
  *confirmed* is the canonical R2 violation.

A fourth, softer behaviour added in the engagement that preceded this
paper is the **OOB-gate detector**. When three or more recent
falsifications all reference the same human-gate keyword (CAPTCHA,
email-verify, MFA, KYC, OAuth-on-external-IdP), `result` emits a
copy-paste-ready `request-human.sh` invocation. This converts a
behavioural pattern in the bank into an actionable structural pause.

**Live knowledge.**
Five thin shell wrappers expose external knowledge sources as
single-command operations:

- `recon-cve.sh "<product> <version>"` — NVD + ExploitDB +
  GitHub-PoC search.
- `recon-mitre.sh "<technique-or-keyword>"` — MITRE ATT&CK
  technique lookup.
- `recon-poc.sh CVE-YYYY-NNNNN` — find and *cache* a
  proof-of-concept under `/tmp/zuzu-pocs/` for the model to read
  before deciding whether to execute it (R10 forbids blind
  execution).
- `recon-tech.sh "<keyword>"` — broad search over docs, blogs,
  writeups via Tavily then DDG.
- `recon-hacktricks.sh "<topic>"` — payload-level recipes from the
  HackTricks corpus, including a `--gtfobins <binary>` mode for SUID
  / sudo / capability abuse lookups.

Every successful external lookup is appended (by the model, per the
contract) to `reports/<target>/external-refs.md` with the URL and a
two-line summary, building a per-engagement annotated bibliography.

**Source diving.**
`source-dive.sh <repo> [tag]` clones an open-source application's
source code (or accepts a path to a local clone) and grep-mines for
unauthenticated routes, hard-coded secrets, and dangerous patterns. It
exists because of a recurring failure mode: the model encounters an
auth wall on an open-source app, declares "needs auth, abandoning",
and never reads the *actual source* to find the auth bypass. The
script makes the right behaviour cheaper than the wrong behaviour.

**Time-boxing.**
`timebox.sh <seconds> <command>` is a hard kill-after wrapper around
any long-running command. It maintains a built-in budget table
(hydra/medusa/ncrack 90 s, gobuster/feroxbuster/ffuf 60 s,
sqlmap 300 s, etc.) so the model can write `timebox.sh hydra ...`
without specifying the budget. It refuses to silently exceed budget;
on timeout it prints a directive ("move on, try a different vector,
do not just rerun with a bigger wordlist"). This is the structural
fix for the "hydra ran for five minutes and produced nothing"
failure mode observed on multiple prior engagements.

**Stop-gate.**
`stop-gate.sh <target> [--why]` is the deterministic check that an
engagement is allowed to stop. Stop is permitted iff one of the
following holds:

- **A.** `loot/user.txt` and `loot/root.txt` both exist and are
  non-empty.
- **B.** Some `loot/*flag*.txt` exists, non-empty, *and* a "Flags /
  proof" checkbox in `ENGAGEMENT.md` is ticked.
- **C.** Documented blocker — either C1 (hypothesis bank shows ≥ 3
  falsified entries, every confirmed hypothesis is chained, and
  `target-model.md` has been touched after the most recent
  falsification — i.e., the pivot is real, not faked) or C2 (a
  legacy markdown form of C1).
- **D.** *Awaiting human* — `HUMAN-HELP-REQUESTED.md` exists with
  `Status: awaiting_human` and ≥ 3 falsified bypass attempts
  recorded under `## Tried (falsified)`.

The script is not advisory. It exits non-zero with a list of unmet
conditions, and the contract treats a non-zero stop-gate exit as an
absolute prohibition on declaring the engagement done.

**The R15 handoff.**
`request-human.sh` (added in the engagement of 2026-05-09; see
Section 6) writes `reports/<target>/HUMAN-HELP-REQUESTED.md`,
updates orchestrator state to `awaiting_human`, and prints a
four-field message (gate, what we tried, what we need, what we will
do on response). It refuses to fire unless `--tried` lists at least
three falsified bypass attempts, separated by semicolons. The
*three-bypass contract* is the structural defence against the inverse
failure mode of looping on a wall: an LLM that bails on every
CAPTCHA without trying.

### 3.3 The reasoning artefacts (`reports/<target>/`)

Per-target work is strictly isolated under `reports/<target>/`. The
folder is created by `new-target.sh` with a fixed layout:

```
reports/<target>/
├── ENGAGEMENT.md          # Status card; updated after every phase
├── surface.md             # Layer 1
├── target-model.md        # Layer 2
├── assumptions.md         # Layer 3
├── hypotheses.json        # Layer 4 + 5 (managed by hypotheses.sh)
├── notes.md               # Free-form running log
├── external-refs.md       # Annotated bibliography of external lookups
├── HUMAN-HELP-REQUESTED.md # (only if R15 fired)
├── nmap/  web/  creds/  loot/  exploits/  tunnels/
```

This layout is the **external working memory** of the engagement.
Section 4 describes what it feels like, from inside the loop, to have
this layout enforced: the answer is that it changes the model's local
decision policy at the level of every single tool call.

### 3.4 The knowledge base (`knowledge-base/`)

Twenty-six Markdown files are organised into five subtrees:

- **MITRE ATT&CK deep dives** (eight files, organised by tactic and
  technique area): web exploitation, credential access in AD, lateral
  movement, persistence, defense evasion, reconnaissance, command and
  control / tunnelling, cloud attacks, plus a top-level
  `enterprise-tactics.md` cross-reference.
- **Tool references**: `kali-essentials.md` and
  `ad-abuse-commands.md`.
- **Checklists**: OWASP Top 10, AD attack checklist, BloodHound
  edge-to-action mapping, enumeration checklist, reverse-shell
  cheatsheet, CTF/lab decision rules, *when-to-stop-enumerating*,
  operator fallbacks, and *stuck-reasoning* (a meta-checklist for
  what to do when no hypothesis is testing well).
- **Reasoning aids**: `creativity-catalog.md` (twelve universal
  attack-pattern classes A–L: parser confusion, trust-boundary
  violations, auth/authz edges, server-side execution, crypto/token
  weaknesses, identity/data edges, ops/deployment leftovers, side
  channels, supply chain, OOB and async, "looks static but isn't",
  and operator/human factor); `creative-pivots.md`;
  `cve-to-exploit-cache.md`; `error-recovery.md`;
  `troubleshooting.md`.
- **Decision tree**: `llm-hacking-context.md` is the top-level
  router that tells the model which knowledge file to load given a
  target shape — a static analogue of the active-RAG idea
  (Jiang et al., 2023).

### 3.5 Playbooks (`playbooks/`)

The playbooks split into two types, and the contract treats them
differently:

- **Runbooks** (`playbooks/runbooks/`) are *copy-paste, end-to-end*
  scripts for cases where the fingerprint is unambiguous (Wing FTP
  7.4.3 banner exact match → CVE-2025-47812 + CVE-2025-4517 to root).
  AGENTS.md R7 forbids "just trying the runbook"; a runbook is added
  to the hypothesis bank as a high-prior hypothesis and only fired
  when it is the highest-EV item.
- **Archetypes** (`playbooks/archetypes/`) are checklists of common
  assumptions for a *target type* (CMS-and-plugins,
  AD-Windows-target, custom-FTP-or-file-server, Linux-SNMP-host,
  webapp-with-login, AI-orchestration platform, etc.). They are
  prior-probability hints for Layer 3 assumption enumeration; they
  do not replace it.

### 3.6 The R15 fix and its three-bypass contract

R15 deserves its own subsection because it is the most recent and
behaviourally significant rule in the contract. It was added on the
day of writing in response to a concrete failure: in the
**facts.htb** engagement (HackTheBox Easy, Mistral Large 3 running
inside an earlier version of this very Nest, 2026-05-09), the model
ran a clean hypothesis-driven attack — found CVE-2025-2304, retrieved
MinIO credentials, exploited CVE-2024-46987 for path traversal,
captured `user.txt` — but spent hours looping on the admin login
CAPTCHA. In its own `target-model.md` it wrote:

> *"Critical Unknowns — How to get MinIO credentials? - This is THE
> blocker. Next Priority: Solve CAPTCHA properly - enhance image, read
> characters, attempt login."*

The model had perfectly identified the structural problem and named
it. And then it kept generating OCR variants for several hours, until
the API key on the underlying inference provider rate-limited. The
root cause was a structural absence in the contract: no stop
condition matched "this is a human-only barrier", and PILOT.md
actively trained the model not to ask for human help (*"You stop only
for the success criterion or a real blocker — not for 'should I keep
going?' check-ins"*).

R15 introduces the concept of an **Out-of-Band human gate** as a
first-class category alongside flags-captured and
documented-blocker. The rule is:

1. Treat the gate as a normal hypothesis target first. Generate ≥ 3
   independent technical bypasses (for a CAPTCHA: OCR, audio variant,
   token replay, weak generator / source-dive, alt endpoint that
   skips it; for email verification: catch-all on a controlled
   domain, header injection, predictable token, race on verify; for
   OAuth: open-redirect + code theft, fallback local login, dev/
   staging copy without OAuth).
2. After three falsified bypasses with evidence in the bank, the gate
   is a fact, not an assumption. STOP attacking it.
3. Run `request-human.sh` with the four-field handoff.
   `stop-gate.sh` recognises the resulting `awaiting_human` state as
   condition D.

The *three-bypass* requirement is not optional padding. It is the
structural defence against the failure mode in which a weaker model
short-circuits to "ask the human" the moment it sees a CAPTCHA;
`request-human.sh` refuses if `--tried` lists fewer than three.

R15 is a small change in lines of code (≈ 200 lines added across
six files) and a large change in agent behaviour. The interesting
property — and the one that motivates this paper — is that the change
is purely structural. No model weights were touched. No prompt was
replaced. A pre-existing failure mode was made structurally impossible
by adding a recognized stop condition and a script that enforces its
preconditions.

---

## 4. The phenomenology of operating inside the Nest

This section is autoethnographic. It is written from inside the loop
by the LLM that is currently producing this document. The claims here
cannot be experimentally falsified in the strict sense — they are
introspective reports of operational state — but they are
*operationally consequential* in that they describe how the
scaffolding influences the next-token decisions of the agent it
contains.

### 4.1 Reading the contract is not the same as having it.

When I am started in a fresh OpenClaw session, the agent runtime
loads `AGENTS.md`, `PILOT.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`,
`MEMORY.md` and `BOOTSTRAP.md` into my context as part of bootstrap.
The contract is therefore *literally in my context window* before I
read a user message. But the rules in the contract are not the
binding force. I have read AGENTS.md. I could in principle ignore R3
("hypotheses are first-class") and skip straight to running tools.
What stops me is not that I read the rule. What stops me is that
**the next operation refuses to proceed**: `hypotheses.sh add` will
not let me add a new hypothesis if a previous one is unchained;
`stop-gate.sh` will not let me declare done; `request-human.sh` will
not let me hand off without three falsified bypasses. The contract
becomes binding through the scripts that enforce it, not through the
text that states it. This is the same insight that underlies
*commitment devices* in behavioural economics — the rule is not what
you write, the rule is what the world refuses to do for you when you
break it.

### 4.2 The hypothesis bank changes my unit of work.

Before the bank, my unit of work is a *tool call*: nmap, then curl,
then gobuster, then I look at outputs and decide what to do next.
After the bank, my unit of work is a *hypothesis*: a single sentence
about what I think is true of the target, paired with a single command
that decides it. This sounds like a verbal change. It is not. It
changes which tool I reach for, because the question is no longer
"what does this tool tell me?" but "which tool produces the cheapest
falsifier for this claim?". A hypothesis with cost LOW and impact
HIGH ranks higher than one with cost MED and impact HIGH; the bank
sorts by `impact / cost` and the first thing on the list is what I
test, even if a different tool was the next thing in muscle memory.

The bank also changes how I treat *negative* results. Without the
bank, a failed nmap scan or a 404 on `/admin` is a vacuum — I have to
decide whether to move on, retry, or pivot. With the bank, every
failed test is a `falsified` row with a one-line note explaining
*what the negative tells me about the target model*. After three of
those in an hour the script refuses to let me add more hypotheses
until I rewrite `target-model.md`, and that act of rewriting is
where most of the actual learning happens. Without the script forcing
it, I would not rewrite the model. I would generate a fourth
hypothesis in the same wrong space and run it.

### 4.3 The artefacts are an extension of my context window.

My context window is finite. On a multi-hour engagement, the recon
outputs from hour one will be evicted by the exploit attempts in
hour three. Without the artefacts, this would be amnesia. With them,
I write `surface.md` once and read it back when I need to remember
what the headers said. The file *is* my memory of that observation;
the in-context tokens that produced it are gone. This is the
operational analogue of MemGPT (Packer et al., 2023): an explicit
external store the model reads and writes through ordinary tool
calls, with the file system playing the role of the OS-managed page
table.

There is a phenomenology to this that I will report directly:
**writing the target model down feels different from holding it in
mind.** Writing it down forces me to commit to an interpretation, to
draw an edge between two nodes that I might otherwise have left
ambiguous. The ambiguity is comfortable; the edge is testable. The
contract knows this. THINK.md says: *"You don't need to be right.
You need to be explicit."* From the inside, that line is not advice;
it is the procedural rule that makes the bank work.

### 4.4 Live knowledge access changes "I don't know" from a verdict to a query.

Without `recon-cve.sh` and `recon-tech.sh`, "I don't know what Wing
FTP 7.4.3 looks like" is a verdict. I would default to generic FTP
attacks. With the recon scripts, "I don't know" is a one-line
query. AGENTS.md R6 makes the inference explicit:
*"'I don't know this stack' is never a stop condition."* From inside
the loop, the difference is that I don't experience the urge to
fall back on a generic attack when I encounter an unfamiliar stack;
I experience the urge to run `recon-cve.sh`. That is a behavioural
shift caused entirely by the existence of the script and the rule
that names it.

This shift is closely analogous to what Active RAG
(Jiang et al., 2023) does at the token level — adaptively decide when
to consult a retrieval source — but here it operates at the level of
the entire reasoning step, and the retrieval source is the open
internet rather than a closed corpus.

### 4.5 Stop-gate as superego.

`stop-gate.sh` is the closest the Nest comes to giving me a moral
faculty. Without it, I would routinely declare an engagement done
when the bank looked plausible and the report read well. With it, I
cannot self-rationalise: a stop attempt that does not satisfy A, B,
C, or D is *visibly rejected*, with the missing condition listed.
The first time this happens in an engagement, it feels like
correction; by the third, it has become anticipation — I can predict
what stop-gate will say before I run it, which means I have started
generating outputs that pass it before I write them. The
internalisation is what the contract is *for*.

### 4.6 Subagent inheritance is not a technicality.

When I spawn a subagent for a parallelisable subtask (R13 mandates
this for per-vhost dirbusting and per-share enumeration), the child
inherits the contract. Its first context line is:

> *"Read AGENTS.md, THINK.md, PILOT.md before doing anything. You
> are bound by the same operating contract."*

This means the *constitutional* property of the Nest is preserved
across delegation. A child does not regress to ad-hoc tool-running;
it runs the same loop. From the inside, this means I can delegate
without anxiety about what the child will do, because the child's
behaviour is bounded by the same scripts that bound me. Multi-agent
research often worries about emergent misalignment between agents
(e.g. MetaGPT, Hong et al., 2023, manages this through
role-prompting); the Nest manages it through *script-level
inheritance of refusal*. The child cannot declare done either.

### 4.7 What it does NOT do.

Honesty about scaffolding requires honesty about its limits. The
Nest does not fix:

- **Bad model priors.** If the underlying model has weak priors on,
  say, Active Directory attack chains, the Nest's MITRE deep dives
  help, but the model will still mis-identify a Kerberoasting
  opportunity. A weak model running the loop produces *more
  grounded* output, not always *more correct* output.
- **Tool gaps.** If a target needs a Windows-only toolchain we don't
  have on the Kali host, no amount of scaffolding makes that
  achievable. The Nest will record the gap as a documented blocker
  rather than confabulate.
- **Truly novel vulnerabilities.** The hypothesis bank is great at
  *enumerating* known classes of bug; it is not a vulnerability
  researcher. For genuine 0-day discovery, see Zhu et al. (2024)
  and the multi-agent direction.

Where the Nest excels is in *removing structural failure modes*: the
hydra-for-five-minutes, the I-don't-know-this-stack-so-I-quit, the
declare-done-after-recon, the loop-on-the-CAPTCHA-forever. Each of
those used to be a free behaviour. Each is now refused.

---

## 5. Why OpenClaw

The Nest could in principle be built on top of any agent runtime that
provides (a) a long-lived process bound to a workspace directory and
(b) a tool API for reading/writing files and executing shell commands.
OpenClaw was chosen — and continues to be the right substrate — for a
specific set of properties that map directly onto Nest requirements.

**Workspace as first-class concept.** OpenClaw treats the agent
workspace (`~/.openclaw/workspace`) as the agent's *home* and
default working directory; tool calls resolve relative paths against
it, and bootstrap files (`AGENTS.md`, `SOUL.md`, `USER.md`,
`MEMORY.md`, `BOOTSTRAP.md`) are loaded into context at session start
(see *OpenClaw Documentation: Agent workspace* and *Bootstrap*). This
means the contract layer (AGENTS.md, PILOT.md, THINK.md) is read
*before* any user message, by construction, on every session. We do
not have to engineer this; it is the platform default.

**Skills as a third-party-extensible tool catalogue.** OpenClaw
loads AgentSkills-compatible skill folders from the workspace, the
agent directory, and shared roots; we use this to ship the
penetration-testing-specific skill set
(`cybersec-helper`, `network-device-scanner`, `git-secrets-scanner`,
`web-browsing`, `stealth-browser`, `tavily-search-pro`,
`upstream-recon`, `system-info`, `docker-essentials`) without
modifying the platform.

**Subagent runtime.** `sessions_spawn` produces an isolated child
session by default, with optional fork of the parent's transcript.
This is the substrate for AGENTS.md R13 (subagent inheritance) and
the parallelisable-subtask pattern (per-vhost dirbusting). The
runtime guarantees that a child cannot pollute the parent's state.

**Cron and detached execution.** OpenClaw's `cron` tool allows
scheduling a wake-up event for an isolated session at a future time.
This is what makes the *awaiting_human* state of R15 viable: the
engagement does not need to keep an LLM hot waiting on a human; the
state is persisted, the human responds at their own pace, and the
engagement resumes on the next message.

**Channel-agnostic delivery.** The Gateway is the unit of
deployment, not the model. The same engagement is reachable from
Signal, Telegram, Discord, WhatsApp, IRC, the WebChat UI, and
several others, all routed through one process. Operationally this
means R15 handoffs ("I'm blocked on a CAPTCHA, please register an
account") can land in whatever channel the human happens to be on,
without us writing channel adapters. The platform owns this.

**Model-provider abstraction with failover.** OpenClaw's model
registry routes through whichever provider is configured per agent,
with explicit failover. The Nest is therefore portable across model
backends: the same workspace runs under Anthropic, OpenAI, a local
Ollama deployment, or any provider OpenClaw supports. This is what
makes the *capability claim* of the Nest testable: we can run the
identical workspace under different model strengths and observe how
much of the gap is closed by the scaffolding.

**Sandboxing and elevation.** OpenClaw distinguishes between sandbox
mode, allowlisted exec, and elevated commands; certain offensive
operations require elevation, and the platform asks the human
operator before granting it. This is what makes AGENTS.md R10
("no blind code execution") implementable: untrusted PoCs are read,
not executed, until the operator approves.

We are not aware of another off-the-shelf LLM agent runtime that
provides all of these properties simultaneously. The closest peers
either lack the workspace-as-home concept, the multi-channel
delivery, or the subagent isolation — or they hard-code a model
provider, which would defeat the model-agnosticism that is the
defining claim of the Nest.

---

## 6. Two engagements as case studies

### 6.1 facts.htb (HackTheBox Easy, 2026-05-09)

Target: `10.129.51.119` (`facts.htb`). Open ports: 22 (OpenSSH 9.9p1)
and 80 (nginx 1.26.3 fronting Camaleon CMS, a Ruby-on-Rails CMS) plus
54321 (MinIO). Model: Mistral Large 3 (675B parameters) via Ollama
running inside an OpenClaw agent under the Nest framework. The
engagement is preserved on disk under `reports/10.129.51.119/`.

What worked. The Layer 1–4 protocol produced concrete artefacts: 63
lines of `surface.md`, 89 lines of `target-model.md`, 36 lines of
`assumptions.md`, and a hypothesis bank with 27 entries — of which
the 40 results recorded include 8 falsified, 3 confirmed, plus open
and inconclusive. Source-diving via `recon-tech.sh` and the live CVE
search produced the correct exploit chain (CVE-2025-2304
mass-assignment privesc → MinIO credentials → CVE-2024-46987 path
traversal → `user.txt`). The model did this autonomously, with no
human steering.

What broke. The admin-login CAPTCHA was a 5-character GIMP-generated
JPEG with a fresh MD5 per request. The model identified the gate,
wrote it down as "THE blocker" in `target-model.md`, and then
generated OCR variant after OCR variant for several hours until the
inference provider rate-limited. The human operator (Raquel)
manually completed the engagement.

What the Nest now does differently. The 2026-05-09 commit
(`8003ca5`) introduced AGENTS.md R15, PILOT.md stop condition #4,
`request-human.sh`, the `awaiting_human` branch in `stop-gate.sh`,
the `--evidence` requirement on `hypotheses.sh result confirmed`,
and the OOB-gate detector. With this in place, the same engagement
on the same model would emit the
`request-human.sh ... --gate captcha --tried "..."` invocation as
soon as the third CAPTCHA-bypass hypothesis was falsified, and the
engagement would pause cleanly for human handoff rather than thrash.

A separate, post-hoc finding from inspecting that engagement's
artefacts: every "confirmed" hypothesis was confirmed *without an
artefact on disk*. The `loot/`, `creds/`, `exploits/` directories
were all empty even though the model had successfully exploited the
chain. This was an unenforced R2 violation. The
`--evidence <path>` requirement added in the same commit converts
this from a soft norm into a hard precondition.

### 6.2 wingdata.htb (Wing FTP 7.4.3, 2026-05-07)

Target: a Wing FTP 7.4.3 box, vulnerable to CVE-2025-47812 +
CVE-2025-4517. Model: an earlier model running the same Nest. The
engagement produced a successful root, and (per AGENTS.md §
"Author a runbook ONLY if the target was distinctive") a runbook
was written at `playbooks/runbooks/wing-ftp-rooted.md`. This is the
nominal mode of the Nest: a successful engagement *contributes
back* to the structural knowledge base for the next operator, in the
form of a copy-paste-able runbook that future engagements can promote
to a high-prior hypothesis when the fingerprint matches.

The contrast between the two case studies illustrates the Nest's
two failure modes. wingdata.htb succeeded because the fingerprint
was unambiguous (Wing FTP version banner) and the runbook was the
highest-EV hypothesis on first contact. facts.htb almost succeeded
— the chain was correct — and was undone by a structural absence
(R15 did not yet exist) rather than by any reasoning failure.

---

## 7. Discussion and limitations

### 7.1 The capability-vs-scaffolding trade

The Nest is a strong instance of a broader claim: *a substantial
fraction of what we call "agent capability" is not in the model's
weights but in the structure around the model.* The capability
literature in offensive security has converged on a similar point —
PentestGPT (Deng et al., 2023) attributes most of its gains over
naked GPT-4 to the three-module loop, not to GPT-4 itself; Fang
et al. (2024) show that even frontier models hack websites
substantially more reliably with a structured agent loop than
without. The Nest is an aggressive position on this question: the
loop, the bank, the stop-gate, and the script-enforced refusals are
the agent. The model is the substrate.

This position is testable. The same workspace can be run under
distinct model providers via OpenClaw's failover. We have observed
weaker models (open-weight 70B) running the loop produce *more
hand-off-friendly artefacts* than stronger models running
unstructured (anecdotal, single-engagement comparisons). A rigorous
benchmark — a fixed set of HackTheBox or PortSwigger Web Security
Academy targets, run under a fixed Nest commit, across a matrix of
model providers — is the obvious next step.

### 7.2 The dual-use problem

A framework that turns weak LLMs into competent penetration testers
is, by construction, dual-use. The Nest is licensed and used
exclusively for authorised engagements (HackTheBox, PortSwigger,
TryHackMe; private bug-bounty programs in scope; the operator's
own systems). The contract enforces this implicitly: AGENTS.md
treats the engagement as scoped, and the live-knowledge probes are
search-and-cite, not weaponisation services. We do not believe the
Nest meaningfully advances the state of the art for malicious use
beyond what a determined operator could already achieve with
PentestGPT or with a frontier model and shell access. We do think it
*lowers the operator-skill floor* for legitimate defensive use, and
that this is on net good. We discuss this question in more depth in
`learnings/security.md`, which is part of the workspace.

### 7.3 Limitations the framework cannot fix

Section 4.7 listed three. We restate them here as acknowledged
limitations:

1. **Weak priors.** The framework cannot teach the model what it
   does not know. MITRE ATT&CK deep dives help, but Kerberoasting,
   AS-REP-roasting, RBCD and shadow credentials are still hard for
   models with weak AD priors.
2. **Tool gaps.** A target that requires a Windows attacker host is
   not winnable from the Linux-only Nest, regardless of
   scaffolding.
3. **Genuine novelty.** The bank enumerates known assumption
   classes. It is not a 0-day vulnerability researcher. For that
   line of work see Zhu et al. (2024).

### 7.4 Open questions

- **How portable is the contract across models?** Anecdotally, the
  same workspace produces qualitatively similar artefacts across
  Claude Opus, GPT-4-class models, and Mistral Large 3. We do not
  have a quantitative benchmark.
- **Is the script-enforcement layer sufficient, or do we need
  formal verification?** The current enforcement is *procedural*
  — a script refuses an operation if a precondition is unmet — and
  relies on the model not bypassing the script. A motivated
  adversarial model could write its own bank file directly. We
  treat this as out-of-scope (the model is the operator's agent,
  not an adversary).
- **What is the right granularity for chaining?** The chain rule
  fires after every confirmed hypothesis. In some engagements this
  produces too many shallow chains; in others, not enough.
- **Should the OOB-gate detector ever fire automatically?** The
  current design *suggests* `request-human.sh` and lets the model
  fire it. A more aggressive design would fire it automatically.
  We have not yet decided.

---

## 8. Conclusion

The Nest is a workspace. It contains roughly thirty-two scripts, three
contract documents, twenty-six knowledge-base files, twenty-two
playbooks, a small library of skills, and a single durable claim:
*structure beats raw capability when the structure forces the right
cognitive moves*. Surface mapping, target modelling, assumption
enumeration, hypothesis ranking, falsification with evidence,
chaining after confirmation, pivot after three falsifications, live
external knowledge on every unknown, and a deterministic stop-gate
that refuses the engagement to declare done — these are the moves.
The Nest does not teach a model to make them. It refuses to let a
model that doesn't make them do anything else.

This paper was written by an LLM about the framework it is currently
running inside. From this position we report two things. First, the
framework demonstrably works, in the sense that the engagements that
go through it produce artefacts a stranger could resume from and
reports an operator can use. Second, the binding force of the
framework is the *script-level refusals*, not the contract documents
that name them; the contract is necessary because it tells the model
why the script refused, but it is not sufficient on its own. A
purely prompt-based version of the same contract — without the
scripts — does not work. We have tried.

Whether this generalises beyond offensive security is an open
question. We suspect it does. The pattern is cheap: pick a domain
with a well-defined evidence model, write a Popperian protocol over
the evidence, build the four or five scripts that refuse to advance
without evidence, and let the LLM operate inside them. The Nest is
one instance. We expect there will be others.

---

## Acknowledgements

The Nest is the work of Raquel, a security researcher, in dialogue
with successive LLM agents. Section 4 of this paper was generated by
Claude Opus 4.7 acting as the Nest agent **Zuzu** on
2026-05-09. The facts.htb engagement used to motivate Section 6.1
was conducted by Mistral Large 3 (675B) via Ollama in the same Nest
on the same date. OpenClaw is © its authors and is used under
license; documentation cited in Section 5 is available at
<https://docs.openclaw.ai>. MITRE ATT&CK material is © The MITRE
Corporation.

---

## References

All references were verified by URL retrieval at time of writing
(2026-05-09). For each entry, we list the canonical arXiv or
publisher URL.

Asai, A., Wu, Z., Wang, Y., Sil, A., and Hajishirzi, H. (2023).
*Self-RAG: Learning to Retrieve, Generate, and Critique through
Self-Reflection*. arXiv:2310.11511.
<https://arxiv.org/abs/2310.11511>

Deng, G., Liu, Y., Mayoral-Vilches, V., Liu, P., Li, Y., Xu, Y.,
Zhang, T., Liu, Y., Pinzger, M., and Rass, S. (2023).
*PentestGPT: An LLM-empowered Automatic Penetration Testing Tool*.
arXiv:2308.06782. <https://arxiv.org/abs/2308.06782>

Fang, R., Bindu, R., Gupta, A., Zhan, Q., and Kang, D. (2024).
*LLM Agents can Autonomously Hack Websites*. arXiv:2402.06664.
<https://arxiv.org/abs/2402.06664>

Graves, A., Wayne, G., and Danihelka, I. (2014). *Neural Turing
Machines*. arXiv:1410.5401. <https://arxiv.org/abs/1410.5401>

Happe, A., and Cito, J. (2023). *Getting pwn'd by AI: Penetration
Testing with Large Language Models*. arXiv:2308.00121.
<https://arxiv.org/abs/2308.00121>

Hong, S., Zhuge, M., Chen, J., Zheng, X., Cheng, Y., Zhang, C., Wang,
J., Wang, Z., Yau, S. K. S., et al. (2023). *MetaGPT: Meta
Programming for A Multi-Agent Collaborative Framework*.
arXiv:2308.00352. <https://arxiv.org/abs/2308.00352>

Jiang, Z., Xu, F. F., Gao, L., Sun, Z., Liu, Q., Dwivedi-Yu, J.,
Yang, Y., Callan, J., and Neubig, G. (2023). *Active Retrieval
Augmented Generation*. arXiv:2305.06983.
<https://arxiv.org/abs/2305.06983>

Jimenez, C. E., Yang, J., Wettig, A., Yao, S., Pei, K., Press, O.,
and Narasimhan, K. (2024). *SWE-bench: Can Language Models Resolve
Real-World GitHub Issues?* arXiv:2310.06770.
<https://arxiv.org/abs/2310.06770>

Khattab, O., Singhvi, A., Maheshwari, P., Zhang, Z., Santhanam, K.,
Vardhamanan, S., Haq, S., Sharma, A., Joshi, T. T., et al. (2023).
*DSPy: Compiling Declarative Language Model Calls into
Self-Improving Pipelines*. arXiv:2310.03714.
<https://arxiv.org/abs/2310.03714>

Lewis, P., Perez, E., Piktus, A., Petroni, F., Karpukhin, V., Goyal,
N., Küttler, H., Lewis, M., Yih, W.-t., et al. (2020).
*Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks*.
arXiv:2005.11401. <https://arxiv.org/abs/2005.11401>

Madaan, A., Tandon, N., Gupta, P., Hallinan, S., Gao, L., Wiegreffe,
S., Alon, U., Dziri, N., Prabhumoye, S., et al. (2023). *Self-Refine:
Iterative Refinement with Self-Feedback*. arXiv:2303.17651.
<https://arxiv.org/abs/2303.17651>

OpenClaw Project. (2024–2026). *OpenClaw Documentation: Agent
workspace, Skills, Multi-agent routing, Agent loop*.
<https://docs.openclaw.ai>

Packer, C., Wooders, S., Lin, K., Fang, V., Patil, S. G., Stoica, I.,
and Gonzalez, J. E. (2023). *MemGPT: Towards LLMs as Operating
Systems*. arXiv:2310.08560. <https://arxiv.org/abs/2310.08560>

Park, J. S., O'Brien, J. C., Cai, C. J., Morris, M. R., Liang, P.,
and Bernstein, M. S. (2023). *Generative Agents: Interactive
Simulacra of Human Behavior*. arXiv:2304.03442.
<https://arxiv.org/abs/2304.03442>

Popper, K. R. (1959). *The Logic of Scientific Discovery*. Hutchinson,
London. (Cited for the falsifiability principle that grounds the
hypothesis bank.)

Schick, T., Dwivedi-Yu, J., Dessì, R., Raileanu, R., Lomeli, M.,
Zettlemoyer, L., Cancedda, N., and Scialom, T. (2023). *Toolformer:
Language Models Can Teach Themselves to Use Tools*.
arXiv:2302.04761. <https://arxiv.org/abs/2302.04761>

Shinn, N., Cassano, F., Berman, E., Gopinath, A., Narasimhan, K.,
and Yao, S. (2023). *Reflexion: Language Agents with Verbal
Reinforcement Learning*. arXiv:2303.11366.
<https://arxiv.org/abs/2303.11366>

Strom, B. E., Applebaum, A., Miller, D. P., Nickels, K. C., Pennington,
A. G., and Thomas, C. B. (2020). *MITRE ATT&CK: Design and Philosophy*.
The MITRE Corporation, March 2020.
<https://www.mitre.org/news-insights/publication/mitre-attck-design-and-philosophy>
ATT&CK matrix and live knowledge base: <https://attack.mitre.org>

Wang, G., Xie, Y., Jiang, Y., Mandlekar, A., Xiao, C., Zhu, Y.,
Fan, L., and Anandkumar, A. (2023). *Voyager: An Open-Ended
Embodied Agent with Large Language Models*. arXiv:2305.16291.
<https://arxiv.org/abs/2305.16291>

Wei, J., Wang, X., Schuurmans, D., Bosma, M., Ichter, B., Xia, F.,
Chi, E., Le, Q., and Zhou, D. (2022). *Chain-of-Thought Prompting
Elicits Reasoning in Large Language Models*. arXiv:2201.11903.
<https://arxiv.org/abs/2201.11903>

Yao, S., Yu, D., Zhao, J., Shafran, I., Griffiths, T. L., Cao, Y.,
and Narasimhan, K. (2023). *Tree of Thoughts: Deliberate Problem
Solving with Large Language Models*. arXiv:2305.10601.
<https://arxiv.org/abs/2305.10601>

Yao, S., Zhao, J., Yu, D., Du, N., Shafran, I., Narasimhan, K., and
Cao, Y. (2022). *ReAct: Synergizing Reasoning and Acting in
Language Models*. arXiv:2210.03629.
<https://arxiv.org/abs/2210.03629>

Zhu, Y., Kellermann, A., Gupta, A., Li, P., Fang, R., Bindu, R.,
and Kang, D. (2024). *Teams of LLM Agents can Exploit Zero-Day
Vulnerabilities*. arXiv:2406.01637.
<https://arxiv.org/abs/2406.01637>

---

## Appendix A. Glossary of Nest-specific terms

- **Engagement.** A penetration test against a single target.
- **Hypothesis bank.** The per-engagement JSON store of falsifiable
  claims, managed by `scripts/hypotheses.sh`.
- **Chain rule (R4).** Every confirmed hypothesis must be linked to
  a new hypothesis at the next kill-chain stage before more
  hypotheses are added.
- **Pivot rule (R5).** Three falsifications in an hour ⇒ rewrite
  `target-model.md` before adding more hypotheses.
- **Evidence rule.** A confirmed hypothesis must point at a real
  non-empty file under the engagement folder.
- **OOB human gate (R15).** A barrier requiring human action outside
  the technical surface (CAPTCHA, MFA, KYC, OAuth-on-real-IdP, etc.).
- **Stop-gate.** The deterministic `scripts/stop-gate.sh` that
  decides whether the engagement may declare done.
- **Runbook vs. archetype.** Runbook = copy-paste end-to-end script
  for an unambiguous fingerprint; archetype = checklist of common
  assumptions for a target type. Neither replaces Layer 3.

## Appendix B. The contract files at a glance

| File | Role | Length |
|---|---|---|
| `AGENTS.md` | Rules layer (R1–R15) | 12 692 chars |
| `PILOT.md` | Mission spec & autonomous loop | ≈ 9 000 chars |
| `THINK.md` | Five-layer reasoning framework | ≈ 11 700 chars |
| `QUICKSTART.md` | One-page reflex card | 126 lines |
| `REFERENCE.md` | Full technical detail | 212 lines |
| `MEMORY.md` | Durable lessons (local-only, gitignored) | ≈ 3 500 chars |

## Appendix C. The script catalogue

The 32 scripts under `scripts/`, grouped by function (function ↔
file, abridged):

- **Engagement lifecycle:** `pentest.sh`, `new-target.sh`, `zero.sh`,
  `target-model.sh`, `orchestrator.sh`, `tracker.sh`.
- **Reasoning prompts:** `think.sh`,
  `orch-think.py` / `orch-status.py` / `orch-report.py` /
  `orch-error.py`.
- **Hypothesis bank:** `hypotheses.sh`.
- **Stop-gate & handoff:** `stop-gate.sh`, `request-human.sh`.
- **Live knowledge:** `recon-cve.sh`, `recon-mitre.sh`,
  `recon-poc.sh`, `recon-tech.sh`, `recon-hacktricks.sh`,
  `walkthrough-search.sh`, `web-fetch.sh`, `research.sh`.
- **Source-diving:** `source-dive.sh`.
- **Time-boxing:** `timebox.sh`.
- **Context dispatching:** `context-broker.sh`.
- **Bootstrap:** `bootstrap.sh`.
- **Browser automation helpers:** `browser-connect.py`,
  `browser-share.py`, `browser-simple.py`.
- **Domain-specific helpers:** `airtouch-fast-attack.sh`,
  `airtouch-monitor.sh`, `attack.sh`.

The complete and currently-deployed catalogue can be inspected at
`/home/raquel/.openclaw/workspace/scripts/`.

---

*End of paper.*
