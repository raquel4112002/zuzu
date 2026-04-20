# Playbook: Active Directory Foothold to Domain Admin

Use this when you already have a valid domain user, service account, WinRM foothold, LDAP bind, or any authenticated AD access and need to turn it into meaningful privilege escalation.

This playbook is not about enumeration for its own sake. It is about converting authenticated AD access into the shortest credible path to higher privilege.

---

## Core Rule

Once you have a valid AD principal, stop thinking like an unauthenticated outsider.

Shift to these questions:
- what does this principal reach?
- what does it read?
- what does it write?
- what groups is it in?
- what objects does it control?
- what can it impersonate, reset, delegate to, or dump?

---

## Phase 1: Validate and Expand the Foothold

Immediately test the credential across likely services:

```bash
crackmapexec smb DC_IP -u USER -p 'PASS'
crackmapexec winrm DC_IP -u USER -p 'PASS'
ldapsearch -H ldap://DC_IP -x -D 'USER@domain.tld' -w 'PASS' -b 'DC=domain,DC=tld' '(objectClass=user)' sAMAccountName
```

If the user lands on a workstation or server, capture:
- `whoami`
- `whoami /groups`
- hostname
- local admin status
- reachable shares

---

## Phase 2: Prioritized Post-Foothold Questions

Answer these in order.

### 1. Is there an obvious secret in LDAP?
Check attributes like:
- `info`
- `description`
- `memberOf`
- `servicePrincipalName`
- delegation-related fields

This is especially high priority for:
- helpdesk accounts
- support accounts
- shared service accounts
- sync or backup identities

### 2. Does the user have remote access?
Check for:
- WinRM
- SMB admin/share access
- RDP-relevant groups
- local admin rights on other hosts

### 3. Does the user or one of its groups control an AD object?
Think:
- `GenericAll`
- `GenericWrite`
- `WriteDacl`
- `WriteOwner`
- `ForceChangePassword`
- `AddKeyCredentialLink`
- DCSync-related rights

### 4. Does the user expose Kerberos attack surface?
Check:
- AS-REP roastable users
- SPNs for Kerberoasting
- delegation
- shadow credentials path

### 5. Does the foothold expose AD CS, backup, sync, or management services?
Those often lead to faster escalation than broader host enumeration.

---

## Phase 3: Best Next-Move Priorities

After foothold, prefer this order unless evidence suggests otherwise:

### Priority 1: Direct secret recovery
Examples:
- LDAP `info`/`description`
- scripts/configs on shares
- plaintext creds in scheduled tasks or tool bundles

### Priority 2: Object control / ACL abuse
Examples:
- group membership changes
- `WriteDacl`
- `GenericAll`
- RBCD
- shadow credentials

### Priority 3: Ticket / identity abuse
Examples:
- Kerberoasting
- AS-REP roasting
- S4U delegation paths
- PKINIT / AD CS abuse

### Priority 4: Lateral movement to admin-rich systems
Examples:
- management servers
- backup hosts
- file servers with privileged sessions

### Priority 5: Generic host privesc
Use this when object/identity paths are weaker than host-based escalation.

---

## BloodHound-Driven Operator Loop

When you have BloodHound data:

1. identify the shortest path to DA / DC compromise
2. ignore pretty graphs, extract the exact edge sequence
3. convert each edge into an abuse primitive
4. choose the shortest viable exploit chain

Typical strong paths:
- user → ForceChangePassword → privileged user
- user → GenericAll on group → add self → privileged group
- user/group → GenericAll on computer → RBCD
- user → AddKeyCredentialLink → shadow creds
- user → DCSync rights → `secretsdump.py`

If a path ends on `DC$`, certificate authority, Domain Admins, or Administrators, treat it as high priority.

---

## High-Value LDAP Checks

When you have authenticated LDAP, look for:

- users with suspicious `info` or `description`
- shared support or service accounts
- members of `Remote Management Users`
- members of backup/helpdesk/admin-adjacent groups
- delegation flags
- certificate services artifacts
- privileged groups with writable members or ACLs

Useful pattern:

```bash
ldapsearch -H ldap://DC_IP -x -D 'USER@domain.tld' -w 'PASS' \
  -b 'DC=domain,DC=tld' '(sAMAccountName=*)' \
  sAMAccountName info description memberOf servicePrincipalName
```

---

## Pivot Rules

### If the user is in a support/helpdesk/shared group
Then:
- inspect LDAP attributes first
- inspect BloodHound next
- suspect object-control paths before brute force

### If the user has WinRM but no admin
Then:
- use shell for local situational awareness
- but do not get trapped in host-only thinking
- keep object-control and identity-abuse paths in focus

### If the user reaches a computer object ACL
Then:
- evaluate RBCD early
- do not waste time on generic local enumeration first

### If the user reaches `WriteDacl`
Then:
- grant a more directly abusable right
- then perform the follow-on exploitation

### If the user reaches `AddKeyCredentialLink`
Then:
- prioritize shadow credentials

### If you have DCSync rights
Then:
- stop wandering and dump secrets

---

## When to Stop Enumerating and Exploit

This is critical.

Stop broad enumeration and move to exploitation when:
- you have a clear BloodHound edge to high-value control
- you recovered a real credential with remote-access value
- you identified an object-control path that plausibly yields admin or DA
- you have a ticket/identity abuse path with known commands

Do **not** keep scanning randomly once a short path exists.

---

## When to Continue Enumerating Instead

Keep enumerating when:
- the current path is only interesting, not actionable
- you do not yet know what the object-control edge actually permits
- you have a credential but no service or privilege value from it
- the path depends on assumptions you have not validated

---

## Fallback Thinking

If your first exploit plan fails, classify why:
- syntax/tool failure
- name resolution / Kerberos issue
- wrong object or wrong principal
- rights are weaker than expected
- exploitation path valid but tool unstable

Then switch method, not just tool spam.

Examples:
- WinRM unstable → `wmiexec.py` / `psexec.py`
- Kerberos hostname issue → fix `/etc/hosts`
- BloodHound edge unclear → inspect ACL/object details directly
- `GenericWrite` not enough → look for `WriteDacl` or different target

---

## Minimal Working Foothold-to-DA Workflow

```text
1. validate creds
2. inspect LDAP for secrets and group memberships
3. collect BloodHound
4. identify shortest high-value edge
5. map edge to abuse primitive
6. execute with syntax-safe templates
7. verify higher privilege
8. document exact chain
```

---

## Common AD Escalation Primitives to Keep in Mind

- plaintext secret in LDAP attribute
- password reset via rights
- add self to group
- Kerberoasting / AS-REP roasting
- RBCD
- shadow credentials
- DCSync
- AD CS abuse
- local admin reuse / lateral movement

---

## One-Screen Checklist

- [ ] Validate SMB / WinRM / LDAP
- [ ] Dump useful LDAP attributes
- [ ] Check `memberOf`
- [ ] Collect BloodHound
- [ ] Identify shortest actionable edge
- [ ] Prefer ACL/object abuse over endless generic enum
- [ ] Stop enumerating when a short exploit path is confirmed
- [ ] Use exact command templates to reduce syntax drift
- [ ] Verify privilege gain immediately
