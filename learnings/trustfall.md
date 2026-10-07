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
