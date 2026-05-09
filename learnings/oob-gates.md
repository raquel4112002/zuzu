# Out-of-Band human gates

> A barrier that, by design, **cannot** be defeated from the technical
> attack surface alone. Recognising one is a skill; knowing when to
> stop attacking it is a bigger skill.

## What counts as an OOB gate

| Gate | Why it's OOB | Common bypasses to try first |
|---|---|---|
| CAPTCHA | Designed to require a human | OCR + preprocess, audio variant, token replay, weak generator (predictable seed / reused image hash), source-dive the gem (e.g. `simple_captcha2`), alt endpoint (mobile API, /v2/, /admin), parameter pollution |
| Email verification | Inbox is out of scope | Catch-all on a domain you own, header injection in verify request, predictable token (timestamp / sequence / weak random), race on verify endpoint, alternate signup flow |
| SMS / phone verification | Phone is out of scope | Same as email + SS7-style attacks (rare in scope), SIM swap (out of scope) |
| MFA (TOTP / push) | Second device | Backup codes (look in dumps / repos), recovery flow, MFA bypass CVEs in the IdP, session token reuse |
| OAuth on an external real IdP | We don't own the account | Open-redirect → code theft, local-account fallback, dev/staging copy without OAuth, misconfigured `redirect_uri` / `state` |
| KYC / identity verification | Real-world identity check | Out of scope to bypass; ask for a verified test account |
| Payment | Real money | Stripe test cards, sandbox env, dev coupon codes leaked in JS |
| Physical-access requirement | Hardware key, on-prem console | Ask for the artefact |

## The 3-bypass rule (AGENTS.md R15)

A gate is a **fact about the world** only after you've falsified ≥ 3
independent technical bypasses with evidence. Before that, it's just
another hypothesis target. CTF-grade CAPTCHAs are frequently solvable;
real-world reCAPTCHA v3 with risk scoring usually isn't.

When in doubt, try the cheapest bypass first:
1. **Source-dive** the gem / library. (`scripts/source-dive.sh`)
2. **Token replay**. Save a solved token, fire it again 5 seconds later.
3. **Alt endpoint**. Mobile API, `/v2/`, `/admin/api/`, `/internal/`.

If those fail, tesseract + preprocessing on the image is ~10 LOC of
Python. Audio variant is a one-line `curl`. Don't write off the gate
without those four.

## When to hand off

After 3 falsified bypasses with evidence in `hypotheses.sh`:

```bash
bash scripts/request-human.sh \
  --target  <target> \
  --gate    captcha \
  --tried   "OCR (tesseract+preprocess); token replay rotates; source-dive simple_captcha2 image-only; alt /api/login 404" \
  --need    "Valid account on http://target/admin/login. Register manually and paste creds." \
  --resume-with "Fire H6 (mass-assignment privesc) once authenticated, then read CVE-XYZ to grab service creds."
```

The script:
- Writes `reports/<target>/HUMAN-HELP-REQUESTED.md` with `Status: awaiting_human`.
- Updates `state/orchestrator.json` so the orchestrator sees the pause.
- Emits a clean four-field handoff message to chat.
- Refuses to fire if `--tried` lists fewer than 3 bypasses (use `--force` only when genuinely impossible — e.g. legally out of scope).

`stop-gate.sh` recognises `awaiting_human` as a legitimate **pause**
(not "done"). The engagement resumes the moment Raquel pastes the
artefact.

## Anti-patterns

- ❌ Bailing the moment a CAPTCHA appears with 0 bypasses tried. R15
  rejects this; `request-human.sh` will refuse without `--force`.
- ❌ Generating "OCR variant #4 with different threshold" after #1, #2,
  #3 all failed. That's one bypass repeated, not three independent ones.
- ❌ Writing "CAPTCHA blocks me" in `target-model.md` and continuing to
  thrash without invoking the handoff.
- ❌ Treating `awaiting_human` as "done" and writing a final report.
  It's a pause; the report comes after the human handoff completes the
  chain.

## Source

facts.htb (HTB Easy), 2026-05-09. Mistral Large 3 ran a clean
hypothesis-driven attack — found CVE-2025-2304, MinIO creds,
CVE-2024-46987 path traversal, user.txt — but lost hours looping on the
admin login CAPTCHA. The model literally wrote in
`reports/10.129.51.119/target-model.md`:

> *"Critical Unknowns — How to get MinIO credentials? - This is THE
> blocker. Next Priority: Solve CAPTCHA properly - enhance image, read
> characters, attempt login."*

The Nest's rules at the time told the model to **never** ask for human
help — only stop conditions were flags or 3 falsified Hs. So it kept
grinding. R15 + `request-human.sh` are the structural fix.
