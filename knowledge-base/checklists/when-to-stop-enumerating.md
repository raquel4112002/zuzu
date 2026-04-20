# When to Stop Enumerating and Exploit

Use this when the model keeps collecting more data even though a real attack path already exists.

This file exists because many weaker models fail by over-enumerating after they already have enough to move.

---

## Core Rule

Enumeration is not the goal.

Stop broad enumeration when you already have a short, credible path to:
- valid credentials
- remote execution
- privilege escalation
- object control
- ticket abuse
- secret dumping

---

## Exploit Now Conditions

Move from enumeration to exploitation when any of these are true:

### 1. You recovered valid credentials with likely service value
Examples:
- domain user with WinRM rights
- LDAP account that can read useful attributes
- service account likely reusable across protocols

### 2. You found a clear AD object-control edge
Examples:
- `GenericAll` on user, group, or computer
- `WriteDacl`
- `ForceChangePassword`
- `AddKeyCredentialLink`
- DCSync rights

### 3. You have a proven trust-boundary pivot
Examples:
- writable config consumed by higher privilege process
- restore/import path likely executed with elevated privileges
- backup/secret export path with strong exploitability

### 4. You have enough for a known abuse primitive
Examples:
- RBCD prerequisites met
- Kerberoasting target identified
- shadow credentials path identified
- local admin access on a sensitive host

---

## Keep Enumerating Conditions

Continue enumeration only when:
- the current finding is interesting but not yet actionable
- you cannot explain the exploit path clearly
- you still do not know the target object, principal, or service needed for the attack
- your current hypothesis depends on unvalidated assumptions
- the path failed and you do not yet know why

---

## Ask These Questions Before Running More Enum

- what exact new decision will this enumeration answer?
- what is the current best attack path already on the table?
- does this next command reduce uncertainty, or is it just stalling?
- if I had to attack in the next 5 minutes, what would I try now?

If you cannot justify the next enumeration step, stop and exploit.

---

## Anti-Loop Triggers

You are probably over-enumerating if:
- you already have valid creds but are still running broad scans
- BloodHound already gave a short path but you keep collecting more nodes
- you have a writable high-value object and are still looking for unrelated vulns
- you keep listing tools instead of choosing a path
- you already know the abuse primitive but are avoiding execution

---

## Good Examples

### Good stop point
- found `support` password in LDAP
- confirmed WinRM access
- BloodHound shows `GenericAll` on `DC$`
- stop broad enumeration and run RBCD path

### Good continue point
- found `GenericWrite` on an object but still unclear whether it leads to actionable attribute abuse
- do focused follow-up on that exact object, not broad enum everywhere else

---

## Minimal Decision Template

```text
Current best path:
What I need to execute it:
What is still unknown:
Next exploit step:
Fallback if it fails:
```

If you can fill this out cleanly, exploit now.
