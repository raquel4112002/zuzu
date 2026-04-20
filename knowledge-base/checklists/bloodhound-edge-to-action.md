# BloodHound Edge to Action

Use this after collecting BloodHound data. The goal is not just to list edges, but to turn them into the next concrete attack action.

---

## Core Rule

Do not stop at “interesting edge found”.

For every high-value edge, answer:
- what object do I control?
- what target object does that reach?
- what exact abuse does that permit?
- what command sequence should I try next?

---

## High-Value Edge Mapping

### GenericAll on user

Meaning:
- full control over the target user object

Likely actions:
- reset password
- add shadow credentials if supported
- modify service principal names in niche cases

Think next:
- does the user have WinRM, admin, delegation, or DCSync-related value?

---

### GenericAll on group

Meaning:
- full control over the group object

Likely actions:
- add yourself to the group
- wait for group membership to grant admin or privileged rights

Best when:
- target group is local admins, remote management, helpdesk with useful reach, or domain-admin-adjacent

---

### GenericAll on computer

Meaning:
- full control over the computer object

Likely actions:
- RBCD / delegation abuse
- attribute abuse on the computer object
- sometimes shadow credentials depending on environment and rights

Priority thought:
- if this is `DC$` or another high-value server, evaluate RBCD first

---

### GenericWrite on user

Meaning:
- you can write some attributes on the user object

Likely actions:
- set login script or abuse writable attributes in specific cases
- add SPN for Kerberoasting if appropriate
- add shadow credentials in some environments if allowed by attribute access

Need care:
- `GenericWrite` is useful, but not as simple as `GenericAll`
- inspect which attributes matter most

---

### WriteDacl on object

Meaning:
- you can rewrite permissions on the object

Likely actions:
- grant yourself `GenericAll`
- grant yourself password reset or delegation-relevant rights
- then perform the follow-on abuse

Rule:
- `WriteDacl` is usually an intermediate edge, not the final exploit itself

---

### WriteOwner on object

Meaning:
- you may be able to take ownership, then rewrite DACLs

Likely actions:
- take ownership
- grant yourself stronger rights
- abuse object as above

---

### ForceChangePassword on user

Meaning:
- you can reset the target user’s password without knowing the old one

Likely actions:
- reset password
- authenticate as that user
- move into WinRM/SMB/RDP/LDAP/service abuse

---

### AddKeyCredentialLink

Meaning:
- shadow credentials path may be possible

Likely actions:
- add key credential
- authenticate using PKINIT / certificate-based flow

Priority:
- very strong when available against privileged users/computers

---

### AllowedToAct / RBCD-related control

Meaning:
- delegation path is available or can be established

Likely actions:
- add machine account if needed
- write `msDS-AllowedToActOnBehalfOfOtherIdentity`
- request service ticket as privileged user
- execute remotely

---

### DCSync rights

Usually seen as:
- `GetChanges`
- `GetChangesAll`
- `GetChangesInFilteredSet`

Meaning:
- you may be able to replicate secrets from the domain

Likely action:
- `secretsdump.py`

Priority:
- one of the strongest direct paths to domain compromise

---

## Object Prioritization

Prefer edges that land on:
- `DC$`
- Domain Admins / Enterprise Admins / Administrators
- certificate authorities and AD CS-related hosts
- management servers
- file servers with privileged sessions
- accounts with WinRM or local admin rights

Lower priority:
- random user objects with no meaningful access path afterward

---

## Action Conversion Templates

### If you see `GenericAll` on `DC$`
Think:
- add machine account
- write RBCD
- impersonate Administrator
- execute with Kerberos ticket

### If you see `ForceChangePassword` on useful user
Think:
- reset password
- validate via WinRM/SMB/RDP/LDAP
- continue from that principal

### If you see `WriteDacl` on useful object
Think:
- grant self stronger rights first
- then exploit that new right

### If you see `GenericAll` on privileged group
Think:
- add self to group
- refresh token / reauthenticate
- validate resulting access

### If you see `AddKeyCredentialLink`
Think:
- shadow credentials
- PKINIT
- pivot to ticket-based access

---

## Stuck Questions After BloodHound

If you have edges but no plan, answer these:

- which edge gives the shortest path to code execution or secret access?
- which edge lands on a computer object instead of a user?
- which edge is exploitable with tools I already have?
- do I need to change ACLs first or can I abuse the edge directly?
- can I turn this edge into valid creds, a Kerberos ticket, or remote execution?

---

## Minimal Operator Workflow

1. collect BloodHound data
2. identify the shortest high-value path
3. classify edge type
4. map edge to abuse primitive
5. choose the exact tool sequence
6. execute and verify
7. document the edge and the abuse

---

## Quick Reminders

- BloodHound gives graph logic, not the final command syntax
- `GenericAll` on a computer is often more valuable than it first looks
- `WriteDacl` is power, but only after you translate it into a stronger right
- do not enumerate forever once a clear abuse path exists
