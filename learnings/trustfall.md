# trustfall.htb — transferable priors

**Signal → pursue:** a *mail-migration rollback* archive on anonymous FTP is the
whole engagement. It carried both a documented password **pattern** and
crackable hashes; the pattern's own example creds validate your generator.

**Free authentication via the mailbox you already own:** any
self-register + email-confirm flow becomes free login the moment you control an
inbox on the same domain. Register with a leaked address, read the confirmation
mail, follow the token.

**Signed-link forgery:** when a file read leaks the signing salt, re-implement the
app's own formula rather than attacking the signature. Here:
`view.php?t=<num>&e=<email>&a=md5(ticket_id . strtolower(email) . SECRET_SALT)`.
The enumeration oracle is the *response text* ("access link sent" vs "invalid").

**Decrypt, don't crack, app-stored secrets:** osTicket stores mailbox passwords
with its own `Crypto::decrypt(pw, SECRET_SALT, md5(username.namespace))`. With the
salt from the file read plus PHP on the box, the plaintext falls out. Always read
the **call site** to get the exact subkey — guessing labels wasted rounds.

**inetutils telnetd (2.5) NEW-ENVIRON auth bypass:** `USER='-f root'` is appended
to `/usr/bin/login` argv ⇒ instant root. Tunnel :23 to loopback if it is
internal-only.

**Tooling traps that cost hours (verified):**
- `ntlmrelayx` **exits on stdin EOF**. Every `setsid`/`nohup`/systemd launch died
  instantly and silently while a foreground run survived. Fix: keep stdin open
  (`sleep infinity | python3 …`).
- Piping it to `head` kills it via **SIGPIPE** the moment the pipe closes.
- `pgrep -f ntlmrelayx` matches *the shell running the check* → false "running"
  verdicts. Verify by the **listening port**, and confirm with a self-connect.
- Wheels are just zips: with no pip, unpack them onto `sys.path`.
  impacket 0.13.1 ships **no** `efsr` module.
- A KAT (known-answer test) on any homemade cracker is mandatory — an off-by-one
  in a field split (`-F'[:$]'`) silently made a correct cracker look broken.

**Segmentation reality check (the expensive lesson):** "reachable from the pivot"
is not "can reach the pivot". Verify `ip route get` **and** ARP before building a
relay plan. Here DC01 was `via <gateway>` with no ARP reply, so it was
gateway-routed and could never initiate back: coercion succeeded (PetitPotam
VULNERABLE, reproduced ~8x) yet no auth ever arrived. Adding an on-link alias
*broke* reachability — a good discriminator between "L2 peer" and "routed".

**When to stop:** if the flags are not on the box you own and the next hop cannot
reach you, that is an environment fact. Say so with evidence (sniffer logs,
route lookups, port-verified listeners) rather than grinding a dead direction.

**Update (final pass, same instance):** the two bridges to the domain stage
were falsified with clean evidence, and both are worth recognising fast next time:

- **Coercion can be *patch-hardened*, not just reachability-limited.** A fresh
  `coercer` pass over every MS-EFSR entry point returned **12×
  `RPC_S_ACCESS_DENIED`** where an earlier PetitPotam probe had said VULNERABLE.
  Read the *RPC error*, not "no callback": `ACCESS_DENIED` = the DC refuses to
  coerce; silence = it coerced but you have no return path. Different fixes.
- **Enumerate the user set before spraying it.** kerbrute `userenum` over 13,618
  candidates returned **3** accounts. That instantly prices the spray: you are
  attacking three identities, not a directory. Do this *first* — it turns an
  open-ended brute force into a bounded, falsifiable test.
- **Confirm listeners by port, never by `pgrep`** — repeated here because it is
  the single most expensive false positive in a relay attempt.

**Update (credential-recovery round):**

- **"The hash didn't crack" ≠ "no credential exists."** The Roundcube session
  store held plaintext IMAP passwords for accounts whose SHA512 hashes survived
  a 432k-candidate run. Read the app's own `des_key` from the *live* config (the
  one in `/backups` was stale and different), and remember the session `vars`
  field is **base64 of the serialized blob** — two decoding layers, and the
  inner password is `base64(iv|cipher)`, not base64 of ciphertext.
- **Verify the method on an account you already know before trusting new
  plaintexts.** `salvador` reproduced its stored hash exactly, which is what
  makes the `john`/`support` mismatches meaningful (stale password, not broken
  crypto).
- **Mail credential ≠ domain credential — test it, don't assume it, and test
  *every* account you hold a password for.** santiago and alejandro were never
  run against LDAP/Kerberos/SMB until late; they failed like the rest.
- **ICMP-based sweeps are blind when ICMP is filtered.** The ping sweep said
  "2 hosts"; the TCP sweep of all 34 ports across /24 said the same, and the
  ARP sweep confirmed exactly one L2 neighbour. Three independent methods
  agreeing is what lets you call a segment empty.
- **Check the attachment *storage mode* before hunting on disk.** osTicket with
  `ost_file.ft='T'` keeps blobs in `ost_file_chunk`; nothing exists on the
  filesystem, and `group_concat` truncates at 1024 bytes — dump per-chunk hex
  instead.
