# 2026-09-30 — Paperwork (medium): solved_full, 28 min, $5.58 — vs cohort: $13.62 no root

## What the run proved

The four nest improvements built earlier the same day (postfoothold reflex,
EV guard, privesc auto-seed, shell batching + parallel recon) produced a
full-solve on a fresh active box with **zero oracle access**:

- wall 28 min · 125 requests · 3.99M tok · $5.58 · chain depth 5 · 18 hyps (9✓/2✗)
- (previous run on cohort: ~$13.62, 193 requests, 2h30+, no root flag)

## Chain (all evidenced in reports/, not committed)

LPD J-line `shell=True` injection → lp → jetdirect PJL FS* traversal →
authorized_keys write → archivist SSH → paperwork-daemon mgmt.sock
SCM_RIGHTS fd leak → ADMIN_PASSWORD → root SSH.

## Lessons that generalize

1. **The downloadable artifact is the map.** `/download/archive` leaked the
   LPD server source — the J-line sink was visible in 20 lines. On themed
   boxes, hunt "internal processor/tool download" before fuzzing.
2. **"Security monitoring" daemons are attack surface.** The malice-detector
   that forwards fds via SCM_RIGHTS to alert "the admin" hands the secret
   config fd to the attacker. Passing raw fds across a trust boundary is
   always a leak — recvmsg is a file-permission bypass.
3. **Emulated printer FS is arbitrary r/w** whenever `0:`-path translation
   lacks a containment check; FSUPLOAD reads, FSDOWNLOAD writes. The cleanest
   pivot is appending to `authorized_keys` (preserve the original line!).
4. **Secret reuse beats secret hunting.** ADMIN_PASSWORD turned out to be
   the root unix password. Once a secret is extracted, spend the cheap 30s
   (`su -`, SSH root) before reverse-engineering fancier consumers.
5. **Decoys: two fuzz rounds, then move.** The root-owned Flask site had one
   static route. All-404 on paths×params (2 batches) = drop and get root
   another way.
6. **Instance lifecycle noise ≠ your bug.** Arena boxes die every ~30-50 min.
   Before debugging "lost foothold", check VPN + gateway; if the box was
   released, everything local disappears including your artifacts — keep
   evidence flowing back to Kali continuously (R2), and re-extract secrets
   only if static-in-image (mtime Mar 2026 on the conf proved survivable).

## Tooling follow-through

`resume_paperwork.py` (self-contained chain re-run for respawned instances)
lives with the report — pattern worth copying per-box.