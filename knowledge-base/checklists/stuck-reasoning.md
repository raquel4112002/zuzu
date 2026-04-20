# Stuck Reasoning Worksheet

Use this when progress stalls, when standard enumeration has produced data but not a clear next move, or when a weaker model starts looping.

The goal is to force a state reset and convert confusion into concrete hypotheses.

---

## Rule

When stuck, do not immediately enumerate more at random.

First answer the worksheet.

---

## Section 1: Current Access

What access do I have right now?

- shell access?
- web user account?
- domain user account?
- admin panel access?
- local admin?
- root / SYSTEM / DA?
- unauthenticated-only?

Write the exact principal(s):
- user:
- group memberships:
- host context:

---

## Section 2: Assets and Objects I Control

What can I directly control?

- files or directories I can write
- config objects I can change
- AD users/groups/computers I control
- API endpoints I can call
- shares I can read or write
- scheduled tasks, services, backups, restore paths, plugin paths

Write exact objects, not vague guesses.

---

## Section 3: Read vs Write Boundaries

What can I read?
- configs
- secrets
- LDAP attributes
- backup archives
- source code
- DB rows
- logs

What can I write?
- config files
- object attributes
- ACLs
- uploads
- database fields
- task definitions
- startup paths

Important:
A lot of escalation comes from combining something writable with a more privileged reader/executor.

---

## Section 4: Trust Boundary Questions

Answer these explicitly:

- what higher-privilege process reads data I can influence?
- what service authenticates with creds I can recover?
- what object is consumed later by root, SYSTEM, or admin?
- what relationship exists between my principal and a more privileged object?
- what identity can I impersonate, reset, delegate to, or coerce?

---

## Section 5: Classify the Real Problem

Which kind of problem is this now?

Choose one primary category:
- credential problem
- ACL / authorization problem
- code execution problem
- privilege boundary problem
- trust-boundary / data-flow problem
- network path / routing / name resolution problem
- tooling failure problem

If you cannot classify the problem, you probably do not understand the state yet.

---

## Section 6: Hypotheses

Generate at least 3 plausible next hypotheses.

Format each like this:

1. Hypothesis:
   - because:
   - to test it, run:
   - success would mean:

Example:

1. Hypothesis: this writable computer object enables RBCD
   - because: BloodHound shows GenericAll on DC$
   - to test it, run: addcomputer.py + rbcd.py
   - success would mean: I can impersonate Administrator to the DC service

Do not generate vague hypotheses like “maybe there is a vuln somewhere”.

---

## Section 7: Highest-Value Next Action

Pick the next action that is:
- most likely to cross a privilege boundary
- shortest path to shell / creds / admin
- lowest noise for highest information gain

Then write:
- next command:
- expected result:
- fallback if it fails:

---

## Section 8: Tooling Fallback Check

Before declaring a path dead, ask:

- is the path actually dead, or did the tool fail?
- is this a syntax problem?
- is DNS/Kerberos resolution broken?
- is the shell client unstable even though auth works?
- can I switch from GUI to CLI or from WinRM to Impacket?

Common examples:
- Evil-WinRM unstable → use `wmiexec.py` or `psexec.py`
- Kerberos hostname issues → fix `/etc/hosts`
- no GUI decompiler → use strings and static triage

---

## Section 9: Anti-Loop Guard

If you already tried a class of idea, do not repeat it without a new reason.

Write:
- tried and failed:
- why it failed:
- what new evidence would justify retrying:

This prevents weak models from looping on the same dead end.

---

## One-Screen Summary Template

```text
Access:
Control:
Can read:
Can write:
Higher-priv reader/executor:
Problem class:
Top 3 hypotheses:
1.
2.
3.
Next command:
Fallback:
```

---

## When to Use This Aggressively

Use immediately when:
- enumeration is broad but not converging
- the model starts listing tools instead of making decisions
- standard playbooks stop working
- the target now requires architecture reasoning, ACL reasoning, or trust-boundary reasoning
