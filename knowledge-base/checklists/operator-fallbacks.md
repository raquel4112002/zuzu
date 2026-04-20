# Operator Fallbacks

Use this when the attack path seems valid but execution is failing. The point is to separate a dead path from a broken tool, syntax issue, or environment problem.

---

## Core Rule

Do not abandon a good attack path just because the first tool failed.

First classify the failure.

---

## Failure Classes

### 1. Tooling failure
Examples:
- client crashes
- shell UI breaks
- parser errors
- dependency mismatch
- unsupported runtime

Question:
- is the path bad, or just this tool instance?

### 2. Name resolution / Kerberos failure
Examples:
- host not found
- KDC lookup fails
- SPN-related weirdness
- Kerberos works by IP poorly or not at all

Question:
- does `/etc/hosts` need fixing?

### 3. Syntax / format failure
Examples:
- wrong username format
- wrong domain format
- wrong ticket filename
- quoting bugs

Question:
- is this really auth failure, or just bad command shape?

### 4. Rights mismatch
Examples:
- BloodHound edge interpreted too optimistically
- right exists, but not the one needed for this abuse
- object control is weaker than expected

Question:
- do I need a different abuse primitive for the same object?

### 5. Environmental blocking
Examples:
- port blocked
- service disabled
- remote shell allowed only through another protocol
- endpoint exists but execution path differs from expectation

Question:
- can the same identity be used through another service?

---

## Practical Fallback Matrix

### WinRM auth works but shell is unstable
Try:
- `wmiexec.py`
- `psexec.py`
- `smbexec.py`

### Kerberos fails on hostname resolution
Fix:

```bash
echo 'DC_IP dc.domain.tld domain.tld' | sudo tee -a /etc/hosts >/dev/null
```

Then retry with hostname-based SPNs.

### GUI decompiler unavailable
Fallback to:
- `strings`
- config inspection
- class/function name triage
- adjacent resource files

### BloodHound edge exists but abuse failed
Check:
- right type
- target object
- principal really in the controlling group?
- need `WriteDacl` first before `GenericAll` style abuse?

### `getST.py` worked but exec fails
Check:
- exact ccache filename
- `KRB5CCNAME`
- SPN choice
- whether `wmiexec.py` works better than `psexec.py`

### Credential works on LDAP but not WinRM
Try:
- SMB
- RDP
- MSSQL
- app login
- other hosts

Do not assume a credential is useless because one protocol failed.

---

## Minimal Retry Logic

If a path fails, retry only after changing one of these:
- tool
- username format
- target hostname vs IP
- auth method
- target object
- abuse primitive

Do not rerun the same broken command repeatedly.

---

## Questions to Ask Before Pivoting Away

- what evidence says the path is wrong?
- what evidence says only the implementation was wrong?
- is there a lower-noise fallback using the same principal?
- is this a command bug, environment bug, or reasoning bug?

---

## One-Screen Template

```text
Path I believe in:
What failed:
Failure class:
Best fallback:
What changes on retry:
What would prove the path is actually dead:
```

---

## Anti-Panic Rule

A lot of failures are not strategic failures.
They are:
- naming problems
- quoting problems
- unstable clients
- wrong protocol choice
- wrong file path

Fix the execution layer before throwing away the attack idea.
