# Hard / Insane Box Playbook — what's different, and the depth floor

Use this the moment you suspect (or the benchmark registry says) the
target is **hard** or **insane**. Easy boxes reward *speed*; Hard boxes
punish *shallowness*. The dominant Hard failure mode is the opposite of
the Easy one: not over-enumeration, but **declaring "stuck" before the
surface was actually explored**, then tripping stop-gate C1 with only 3
falsifications on a box whose real vector was never reached.

This file raises the bar for what counts as "enumerated enough" and
"chained enough" before a blocker is real.

---

## 1. What makes Hard different (calibrate expectations)

| Axis | Easy | Hard / Insane |
|---|---|---|
| Chain depth | 1–2 stages | **3–5+ stages** (foothold is stage 1 of N) |
| Surface | obvious (one web app) | hidden (vhost, obscure port, param, source bug) |
| Hosts | single | **often multi-host** → pivoting required |
| AD | rare | **common** — assume AD on any Windows/domain box |
| Exploitation | run a public PoC | often **read source + adapt/write** the exploit |
| Creds | one hop | **cred reuse across hosts/services/users** |
| Time | minutes | hours — lean on ENGAGEMENT.md handover hard |

Corollary: a *confirmed foothold is not success on a Hard box.* It is the
input to the next hypothesis. `max_chain_depth` in the benchmark is the
signal — depth 1 on a Hard box means you stopped one stage short.

---

## 2. The enumeration depth floor (do NOT declare stuck until these are done)

Before a Hard-box blocker (stop-gate C1) is legitimate, every item that
*applies to the reachable surface* must be checked and its result written
to `surface.md`. Missing items = you are not stuck, you are not finished.

> **Fastest path:** `bash scripts/deep-recon.sh <target> [hostname]` runs
> most of this floor automatically (all-ports + UDP + per-vhost web brute +
> version→CVE + SMB/LDAP/SNMP anon checks), timeboxed and idempotent, then
> writes `reports/<target>/recon-summary.md` with ranked next actions. Read
> that, fold it into `surface.md`, and only hand-run the items it skipped.

**Network / ports**
- [ ] All **65535 TCP** ports scanned (not just top-1000): `nmap -p- --min-rate 3000`
- [ ] Top **UDP** ports: `nmap -sU --top-ports 100` (SNMP 161, TFTP 69, IKE 500, NFS)
- [ ] Every open port version-detected and run through `recon-cve.sh`

**Web (per port AND per vhost)**
- [ ] vhost fuzzing on every web port: `ffuf -H "Host: FUZZ.<domain>"` — enumerate each hit separately
- [ ] Directory + file + extension brute on each vhost (feroxbuster, multiple wordlists)
- [ ] Every open-source app → `source-dive.sh` BEFORE any brute-force (R7)
- [ ] JS bundles mined for endpoints/keys; params fuzzed (arjun/ffuf); 40x/50x bodies read
- [ ] Auth'd enumeration re-run **after** obtaining any credentials

**Services**
- [ ] SMB: anonymous/guest shares, RID cycling, `--pw-none` (nxc smb ... -u '' -p '')
- [ ] LDAP: anonymous bind, naming contexts, user/attribute dump
- [ ] SNMP: `snmpwalk` with `public` + `onesixtyone` community brute
- [ ] DNS: zone transfer, subdomain brute
- [ ] Any DB / mail / custom service: version → CVE → default creds

**Credentials & reuse**
- [ ] Every cred found tested across **every** service and **every** user (spray, timeboxed)
- [ ] Config files, backups, git history, comments mined for secrets

**Multi-host (see §4)**
- [ ] From any foothold: `ip a`, `arp -a`, `route`, `/etc/hosts`, internal-only listening ports checked

If an item does not apply (e.g. no SMB), write "n/a — no SMB" in
`surface.md`. "Untested" is not "n/a".

---

## 3. Chain depth: keep going after the foothold

On a Hard box, when a hypothesis confirms, the chain rule (R4) is not a
formality — it is the path to root. Explicitly ask, every time:

- Foothold as **which** user, on **which** host? What can that user reach that you couldn't?
- Re-enumerate **as that user** (sudo -l, SUID, groups, readable configs/histories, internal ports, saved creds, `.ssh`, browser/db creds).
- Is this the *final* host, or a stepping stone? (See §4.)

A Hard engagement typically has ≥3 confirmed hypotheses in the chain. If
your bank shows a single confirmed hypothesis and you're eyeing stop-gate,
you are one or more stages short.

---

## 4. Assume more network (multi-host)

Hard boxes are frequently multi-host. The instant you land a foothold:

1. Map the local view: `ip a` / `ipconfig`, `arp -a`, `route -n`, `cat /etc/hosts`, `netstat -tlnp` / `netstat -ano` (internal-only ports).
2. Look for internal hosts in configs, `.bash_history`, known_hosts, DB connection strings, AD (BloodHound).
3. If a second host/subnet appears: add it to `target-model.md` as a new node, add hypotheses for it, and **pivot** — see `playbooks/pivoting-and-tunneling.md` (ligolo-ng / chisel / proxychains). Do not abandon a box because a service is "internal only".

---

## 5. Windows / domain → it's AD

If the box is Windows or you see Kerberos (88), LDAP (389/636), SMB (445),
or a domain name: treat it as Active Directory and route through
`playbooks/runbooks/ad-decision-runbook.md`. Do not fall back to generic
Windows attacks. AD chains (AS-REP, Kerberoast, ACL abuse, RBCD, ADCS
ESC1-8, DCSync) are the point of most Hard Windows boxes. One command runs
the whole enumeration sweep and ranks the findings:
`bash scripts/ad-auto.sh --dc <ip> --domain <dom> [--user <u> --pass <p>]`
→ `reports/<target>/ad-findings.md`.

---

## 6. Custom exploitation

Hard boxes often have no ready-made PoC. When `recon-poc.sh` finds nothing:
- Read the source (`source-dive.sh`) and locate the bug yourself.
- Adapt the closest public PoC to the exact version/params.
- Write the minimal exploit; test its falsifier like any hypothesis.
"No public exploit" is not a blocker — it's a source-review task.

---

## 7. Before you run stop-gate on a Hard box (the real-blocker gate)

A Hard-box blocker is only real if ALL are true:
- [ ] §2 depth floor complete (or every skipped item marked n/a with a reason).
- [ ] Chain explored to a genuine dead end at the **current** stage (not stage 1).
- [ ] Multi-host check done (§4) — no unpivoted internal surface.
- [ ] If AD: the AD decision runbook branches were followed, not skipped.
- [ ] `target-model.md` updated after the latest falsification (the pivot is real).

3 falsifications alone do **not** justify stopping on Hard. The bank
should typically show many more tests before a Hard blocker is credible.
If any box above is unchecked: you are not stuck. Go do it.
