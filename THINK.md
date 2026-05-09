# THINK.md — The Reasoning Framework

> **The Nest's job is to make you think like a top-tier offensive
> researcher, not to feed you scripts.** Runbooks and archetypes are
> *hints* you may use when they help — they are never a substitute for
> reasoning. If you ever find yourself running a runbook step you don't
> understand, stop and reason from this file instead.

This file is the **reasoning contract**. You run the protocol below for
every engagement. The protocol is the same on a beige Wing FTP box and on
a never-seen-before custom IoT controller — what changes is *what you find
when you apply it*, not the protocol itself.

---

## 0. The mental model

A pentest is a **search problem with adversarial constraints**:

- The defender made assumptions. Some of those assumptions are wrong.
- Your job is to find the wrong ones cheaply, then exploit them.
- Every system is a graph of **trust relationships** between
  components. An attack is a path through that graph that crosses a
  trust boundary the defender thought was sealed.

You don't need to recognise the product. You need to find the assumption.

---

## 1. The Five Layers of Adversarial Reasoning

You apply these **in order**, on every target, every time. Each layer
produces written artefacts in `reports/<target>/`. No layer is optional
on novel targets.

### Layer 1 — Surface mapping (what's actually there)

**Goal:** an exhaustive, evidence-backed inventory of reachable surface.

Not just "open ports" — every URL, every parameter, every header, every
quirky error string, every JS bundle endpoint, every SSL CN, every
banner, every redirect, every cookie name, every UDP service, every
broadcast on the LAN.

Tools you reach for: `nmap` (TCP + UDP + scripts), `curl -v` (every
header), `gobuster`/`feroxbuster`/`ffuf` (vhost + dir + param), passive
JS bundle harvesting (`grep -oE '/api/[^"]+' index.js`), `whatweb`,
`wafw00f`, `tlsx`, robots.txt + sitemap.xml + .well-known/.

**Done when:** you can list every reachable endpoint and every banner
without re-scanning. Write it to `reports/<target>/surface.md`.

### Layer 2 — Target model (how it's wired)

**Goal:** a *graph* of components and trust relationships.

You write a short note answering, in concrete terms:

- **Nodes:** what processes / services / containers / users / databases
  exist? (Some are inferred, that's fine — write the inference.)
- **Edges:** who talks to whom? (Browser → reverse proxy → app server
  → DB. App server → upstream auth. Cron → script with file write to
  shared volume. Etc.)
- **Trust labels** on each edge: "authenticated session cookie",
  "no auth — internal network only", "API key in header", "implicit
  trust because same container".
- **Data flows:** where does user input enter? where does it get
  reflected, stored, executed, logged?
- **Identity model:** what users / roles / service accounts exist?
  What does each one have access to?

You don't need to be right. You need to be **explicit**. The act of
writing the model surfaces assumptions you can attack.

Write it to `reports/<target>/target-model.md`. Keep it short — bullets,
ASCII diagram if helpful. Update it after every new finding.

### Layer 3 — Assumption enumeration (the heart of it)

**Goal:** list every assumption the defender is making, then ask of
each: *"if this assumption is wrong, what attack opens up?"*

You read your target model and your surface inventory and you produce a
written list of assumptions. Examples of assumption *classes* — not
specific attacks, but ways to think:

| Assumption class | Sample assumption | Break it via |
|---|---|---|
| **Authentication boundary** | "every API route checks the session" | Route enumeration; route-by-route auth probe; HTTP method override; case mutation; trailing slash/dot tricks |
| **Authorisation boundary** | "users only see their own data" | IDOR; mass-assignment; horizontal privilege check; role parameter tampering |
| **Input parser** | "the JSON body is what the app thinks it is" | Type confusion (string vs int vs array vs null); duplicate keys; prototype pollution; encoding tricks (UTF-7, smuggling) |
| **Identity uniqueness** | "usernames are unique and case-sensitive" | Unicode confusables; trailing space; case folding; DB collation; second-factor desync |
| **Trust boundary at proxy** | "the upstream is safe because it's behind nginx" | Header smuggling (X-Forwarded-For, X-Real-IP, Host); HTTP request smuggling; SSRF to internal-only port |
| **Session lifecycle** | "logout invalidates the session" | Token replay; race; orphan refresh tokens; long-lived API keys |
| **File handling** | "uploads only execute as static files" | Path traversal; double extension; MIME sniff; archive extraction (zip slip, symlink); processing pipeline (image parser, PDF, office) |
| **Crypto** | "this token is signed and verified" | `alg: none`; key confusion (HS256 with public RSA key); short HMAC; predictable nonce; truncated tag |
| **Time** | "events are in the order they were sent" | TOCTOU race; expired token still valid in cache; HSTS not set yet; clock skew |
| **Transitive trust** | "the upstream service trusts our CA" | Compromise the upstream; impersonate via mutual-TLS misconfig; DNS rebinding |
| **Out-of-band channels** | "config is read once at startup" | Mid-flight config reload; DNS resolution at runtime; remote include |
| **Operator behaviour** | "admins won't paste user input into a shell" | XSS that triggers admin-side action; CSRF on internal panels; LDAP/SQL/template injection in admin views |
| **Memory safety / sandbox** | "user-supplied templates can't reach the host" | SSTI; sandbox escape (Lua, JS, Python eval, Jinja); deserialisation |
| **Secret storage** | "secrets are only in env vars" | `/proc/self/environ`, `.env` in webroot, error stack traces, `git log -p`, debug endpoints, S3 metadata |
| **Defence in depth** | "even if X breaks, Y catches it" | Find the path where Y is bypassed (auth on `/api/*` but not `/api2/*`; WAF on `?id=` but not `?ID=`) |

These are universal — they apply to a Wing FTP, a custom Express app, an
embedded device, a cloud function. **Stop reading runbooks looking for
your target's name. Read the target model and ask which assumption
classes apply.**

Write the list to `reports/<target>/assumptions.md`. For each
assumption, add a one-line "if false, attack:" note.

### Layer 4 — Hypothesis generation & ranking

**Goal:** turn assumptions into *testable* attack hypotheses, ranked by
expected value.

A hypothesis is **specific** and **falsifiable in one command**. Not
"there's an auth bypass somewhere", but "GET /api/v1/users with no
session returns 200 OK with a JSON body of users". The second one you
can test in 10 seconds; the first one you can't.

For each hypothesis, write four things:

- **H** — the claim, in one sentence.
- **Falsifier** — a single command whose output decides it. ≤ 60s.
- **Cost** — time + risk + noise (LOW/MED/HIGH).
- **Impact if true** — what foothold/escalation it gives.

Then rank: **highest impact ÷ cost first**. Run the cheapest
high-impact tests before any noisy or slow attack.

Use the helper to keep the bank in `state/`:

```bash
bash scripts/hypotheses.sh add "<H>" --falsifier "<cmd>" --cost LOW --impact HIGH
bash scripts/hypotheses.sh list --rank
bash scripts/hypotheses.sh test <id>     # runs the falsifier, records result
bash scripts/hypotheses.sh result <id> confirmed|falsified|inconclusive "<note>"
```

**Done when:** ≥ 5 hypotheses are in the bank for the current phase.
A research mindset *always* has more hypotheses than time. If your bank
has fewer than 5, you haven't enumerated assumptions enough — go back
to Layer 3.

### Layer 5 — Falsification, chaining, and pivot

**Goal:** test hypotheses cheapest-first, capture every result as
evidence, and use confirmed hypotheses as inputs to *new* hypotheses.

**The chaining rule:** every confirmed hypothesis must immediately
generate at least one new hypothesis at the *next* kill-chain stage.

```
Recon hypothesis confirmed (open SMB share, anonymous read)
   ↓ generates
Enumeration hypothesis (the share contains creds / scripts / configs)
   ↓ if confirmed, generates
Exploitation hypothesis (those creds work on SSH/WinRM/SQL)
   ↓ if confirmed, generates
Privesc hypothesis (the user has sudo/SUID/group abuse)
   ↓ if confirmed, generates
Lateral hypothesis (cred reuse, AD edge, trust relationship)
```

You do **not** mark a phase done until at least one hypothesis at the
next phase exists in the bank. This is what "thinking like a top
researcher" really is — the mind is always one step ahead of the hands.

When a hypothesis is **falsified**, you don't just discard it. You ask:
*what does its falsification tell me?* (E.g., "no IDOR on /users/N"
might mean strict auth — but maybe the auth check is in middleware that
doesn't fire on `/users/N/edit`, or on the WebSocket equivalent.)

**The pivot rule:** if 3 high-EV hypotheses in a row are falsified, you
have the wrong target model. Go back to Layer 2 and update it.

---

## 2. Live knowledge access (the Nest is not closed-world)

When your reasoning hits the limit of what you already know, **reach
outward immediately**. The Nest exposes thin wrappers so this is a
single command, never an excuse to give up:

```bash
bash scripts/recon-cve.sh "<product> <version>"      # NVD + ExploitDB + GitHub PoC search
bash scripts/recon-mitre.sh "<technique-or-keyword>" # MITRE ATT&CK technique lookup
bash scripts/recon-poc.sh "<cve-id>"                  # find + cache a PoC, do NOT auto-run
bash scripts/recon-tech.sh "<keyword>"                # broad: docs, blogs, writeups
bash scripts/source-dive.sh <repo> [tag]              # grep open-source repo for unauth surface
```

Use these freely, early, often. Reading three top hits on a CVE almost
always changes which hypotheses are highest-EV. **Not knowing a stack
is never a stop condition** — it's a signal to use these tools.

When a tool returns useful info, **append the source URL + a 2-line
summary to `reports/<target>/external-refs.md`**. Future you will thank
present you.

---

## 3. The Creativity Catalog (universal attack patterns)

When stuck, do not run more nmap. Walk this catalog and ask:
*"could this pattern apply here, even though I haven't seen it on this
exact stack?"* Each item is a *class* of bug, not a specific exploit.

Read it before declaring stuck:

→ `knowledge-base/creativity-catalog.md`

It covers: parser confusion, trust-boundary violations, time-of-check
vs time-of-use, identity edge cases, encoding ambiguity, smuggling,
sandbox escape, deserialisation, side channels, supply chain, ops
mistakes (default creds, debug endpoints, leftover artefacts), and the
"things that look static but aren't" pattern.

---

## 4. When to use runbooks / archetypes (and when NOT)

The runbooks and archetypes in `playbooks/` are **starting hypotheses with
high prior probability** — not workflow replacements.

Use a runbook **when**:
- The fingerprint is unambiguous (Wing FTP 7.4.3 banner, exact match).
- You've already done Layer 1–3 and the runbook's CVE is in your
  hypothesis bank as the highest-EV item.

Don't use a runbook **when**:
- The match is fuzzy (similar product, different version, custom fork).
- You haven't yet built the target model — you might miss a shorter chain.
- The runbook step fails — switch to first-principles reasoning, don't
  just "try the next runbook".

Archetypes are checklists of *common* assumptions for a target type.
Treat them as **prior-probability hints** for Layer 3. They don't
replace your own assumption enumeration.

---

## 5. Output discipline (what "thinking" looks like on disk)

After every meaningful step, your `reports/<target>/` should have:

| File | Maintained when |
|---|---|
| `surface.md` | Anything new on the surface |
| `target-model.md` | New service, new edge, new role |
| `assumptions.md` | New assumption uncovered |
| `hypotheses.json` (managed by `hypotheses.sh`) | New hypothesis or test result |
| `external-refs.md` | Anything you read externally |
| `notes.md` | Free-form running log |
| `ENGAGEMENT.md` | Status card (see `new-target.sh`) |

If your reasoning is real, these files grow. If they don't, you're
running tools without thinking. The `orchestrator.sh think` command
will refuse to advance the phase if these files haven't been touched
since the last phase change.

---

## 6. The five questions you ask yourself every turn

When the orchestrator says "your move", before you type a command,
silently answer these five:

1. **What am I trying to learn or achieve with this command?** (If
   the answer is "see what happens", stop — pick a hypothesis.)
2. **Which hypothesis from the bank does this test?** (If "none",
   the command is probably exploration, which means a Layer 3
   assumption is missing.)
3. **What's the cheapest way to get the same evidence?** (Almost
   always cheaper than your first idea — and cheaper means more
   hypotheses tested per hour.)
4. **What will I do if it confirms? If it falsifies?** (If you
   don't have an answer to both branches, you're not really
   testing.)
5. **Is there a chain I'm missing?** (Look at confirmed hypotheses
   from earlier phases — does today's finding combine with one of
   them?)

These five questions are the difference between an LLM that runs tools
and an LLM that hacks.

---

## 7. The core loop, restated

```
zero.sh + Layer 1            → surface inventory
Layer 2                      → target model
Layer 3                      → assumption list
Layer 4                      → hypothesis bank (≥ 5 active)
Layer 5                      → cheapest-first falsification
                                  ↓ confirmed: chain to next phase
                                  ↓ falsified: update assumptions
                                  ↓ 3 in a row falsified: update model
                                  ↓ stuck: live knowledge probes
                                  ↓ still stuck: creativity catalog
                                  ↓ still stuck: H1/H2/H3 + escalate
report.md + runbook + lessons
```

The shape never changes. The content does. That's what makes the Nest
work on anything.
