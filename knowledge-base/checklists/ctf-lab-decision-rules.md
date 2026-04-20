# CTF and Lab Decision Rules

Use this for HTB-style boxes, labs, and deliberately vulnerable environments where speed, pivot recognition, and exploit timing matter more than conservative enterprise scoping.

This is not for uncontrolled real-world targets.

---

## Core Rule

In labs and CTF-style targets, prioritize the shortest credible path to user/root over exhaustive coverage.

The goal is solve speed with reproducibility, not perfect enterprise reporting depth during the live path.

---

## What to Prioritize

### 1. Clear pivots over broad coverage
If one service or file stands out, follow it hard before running every generic checklist.

Examples:
- anonymous SMB share with one custom tool
- backup endpoint with suspicious output
- admin panel on uncommon version
- internal binary among common public tools

### 2. Trust-boundary breaks
Labs often reward:
- default creds
- password reuse
- internal tool leakage
- insecure backup/restore
- ACL abuse
- obvious privilege boundary flaws

### 3. Attack chain momentum
Once you have a strong lead, keep momentum.
Do not over-reset into broad enum unless the lead really dies.

---

## Good Lab Heuristics

### If you get a user credential
Immediately test:
- SMB
- WinRM
- SSH
- LDAP
- app login

### If you get an AD user
Immediately think:
- LDAP secrets
- BloodHound
- group memberships
- ACL abuse
- RBCD / shadow creds / DCSync

### If you find a custom binary
Immediately think:
- hardcoded creds
- LDAP path
- API token
- decrypt routine
- config sidecar

### If a shell client glitches but auth worked
Switch tools quickly instead of wasting time debugging the UI.

---

## When to Go Fast

Go fast when:
- the target is obviously a lab/CTF box
- you already have a short exploit path
- the next step is a known abuse primitive
- extra enumeration is unlikely to change the path

---

## When to Slow Down

Slow down when:
- the exploit path is still ambiguous
- the target behavior contradicts your hypothesis
- the path depends on a subtle ACL or trust-boundary assumption
- you need to preserve evidence cleanly for later writeup

---

## Minimal Solve Loop

```text
1. classify target
2. identify the standout pivot
3. validate the pivot quickly
4. push the shortest credible chain
5. verify user/root
6. backfill report evidence
```

---

## Anti-Waste Rules

Do not waste time on:
- endless default NSE spam after a strong foothold path exists
- full-spectrum wordlists before checking obvious leaks
- repeated shell-client debugging when another tool works
- broad scans after BloodHound already revealed the shortest path

---

## Reminder

Fast does not mean sloppy.
It means:
- decisive
- hypothesis-driven
- exploit-oriented
- documented enough to reproduce after the solve
