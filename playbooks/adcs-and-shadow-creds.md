# Playbook: AD CS and Shadow Credentials

Use this when you already have a domain user and see signs of:
- `AddKeyCredentialLink`
- certificate services exposure
- ESC-style AD CS abuse paths
- certificate-based authentication opportunities

This playbook is for converting object control or certificate misconfiguration into stronger identity or domain compromise.

---

## High-Priority Triggers

Load this playbook when any of these are true:
- BloodHound shows `AddKeyCredentialLink`
- Certipy or LDAP enumeration reveals AD CS
- target hosts expose certificate authority services
- privileged users/computers can be attacked through certificate enrollment or key credential injection

---

## Part 1: Shadow Credentials

### What it means

If you can write `msDS-KeyCredentialLink` on a user or computer object, you may be able to add a key credential and authenticate as that object without knowing its password.

This is often one of the shortest paths from object control to identity takeover.

---

### When to prioritize it

Prioritize shadow credentials when:
- you have `AddKeyCredentialLink` on a useful user or computer
- password reset is noisier or riskier
- the target principal is more valuable than your current foothold
- you want cleaner identity abuse than host-based exploitation

---

### Typical workflow

1. confirm the right exists on the target object
2. use Certipy to add shadow credentials
3. authenticate as the target principal
4. pivot into WinRM, SMB, Kerberos, or further AD abuse

Example template:

```bash
certipy shadow auto \
  -u 'USER@domain.tld' -p 'PASS' \
  -account TARGETUSER \
  -dc-ip DC_IP
```

Then validate the resulting identity on useful services.

---

### Good targets

- privileged users
- service accounts with broad access
- computer accounts on high-value hosts
- accounts that unlock further ACL or delegation paths

---

## Part 2: AD CS Thinking

### Why it matters

AD CS often turns small auth/control mistakes into full compromise.

Common outcomes:
- certificate-based auth as another user
- domain escalation without password theft
- long-lived credential material

---

### First questions to ask

- does the environment have certificate services?
- which templates are enabled?
- can my current user enroll in dangerous templates?
- do templates allow subject alternative name abuse or client auth?
- do I control a user/computer that can be abused through certificate enrollment?

---

### Quick discovery mindset

Look for:
- enterprise CA presence
- vulnerable templates
- enrollment rights
- ESC-style paths
- client authentication templates
- enrollment agent or SAN abuse opportunities

Use Certipy or equivalent enumeration.

---

### Typical Certipy discovery flow

```bash
certipy find \
  -u 'USER@domain.tld' -p 'PASS' \
  -dc-ip DC_IP -vulnerable
```

This is discovery, not the exploit by itself.

Interpret the results in terms of:
- can I request a cert as a more privileged user?
- can I authenticate with that cert?
- what exact identity do I gain if this works?

---

## Part 3: Exploit Prioritization

### If you have `AddKeyCredentialLink`
Prioritize:
- shadow credentials first

### If you have dangerous AD CS template enrollment
Prioritize:
- certificate request path
- auth as target user
- immediate validation of gained identity

### If you have both AD CS and ACL abuse paths
Choose the shorter path to:
- DA / DC compromise
- DCSync
- admin on a high-value host

Do not do both just because both are interesting.

---

## Part 4: Common Failure Modes

### Certipy syntax or auth drift
Fix by:
- checking username format
- checking domain FQDN vs NetBIOS usage
- verifying DC IP and hostname resolution

### Noisy discovery without exploit value
If Certipy finds a CA but no actionable template path:
- do not sink too much time there
- return to ACL/BloodHound/object-control paths

### Wrong target for shadow creds
If you can shadow a low-value user but it changes nothing:
- reassess target value first
- do not waste time on identity takeover that gives no better reach

---

## Part 5: Minimal Decision Tree

### Shadow creds
If:
- `AddKeyCredentialLink` on valuable principal
Then:
- run shadow creds path
- validate resulting identity immediately

### AD CS
If:
- vulnerable template + your user can enroll + privileged identity can be requested
Then:
- request cert
- authenticate as target
- verify high-value access immediately

### Otherwise
If:
- path is not obviously actionable
Then:
- return to BloodHound edge interpretation or ACL abuse

---

## Minimal Evidence to Save

- proof of `AddKeyCredentialLink` or vulnerable template
- commands used
- resulting certificate or auth proof
- exact identity obtained
- what privilege boundary that identity crossed

---

## One-Screen Checklist

- [ ] Confirm `AddKeyCredentialLink` or AD CS trigger
- [ ] Check if the target principal is actually high value
- [ ] Prefer shortest path to stronger identity
- [ ] Validate certificate-based or shadow-based auth immediately
- [ ] Do not get trapped in CA enumeration if no exploit path exists
