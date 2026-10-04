# Archetype: Container Foothold (you landed inside a container)

**Match if you see:** `/.dockerenv` exists · `/proc/1/cgroup` shows
`docker/containerd/kubepods` · your user is a service account
(`datawrangler`, `app`, `node`, uid ≥ 900, odd gid) · minimal image
(python-slim, alpine) · a converter/worker/queue process is PID 1.

**The mindset shift (this is the whole archetype):**
A shell in a container is **code-exec, not USER access**. `user.txt` and
`root.txt` almost never live in the container. Your job now is to find the
**bridge to the host** (or to a real user). Do not start a kernel/root
hunt inside the container — map the escape surface first.

> bedside.htb (medium) lesson: got RCE as `datawrangler` in a converter
> container, then burned ~4h blind-fuzzing a 404-ing host root API and
> re-listing empty bind-mount dirs — never located `user.txt`. The escape
> surface (shared netns + writable bind-mount feeding a root host service)
> was the intended path and was under-attacked.

## Fast map (one shot — `postfoothold.sh` now captures all of this)

```bash
bash scripts/postfoothold.sh --emit     # run on target; read loot/
```
Then read these sections of the loot in order:

1. **FLAG HUNT / USER MAP** — is `user.txt` reachable from here? Who are
   the real login users? (pivot targets)
2. **CONTAINER / NAMESPACES / BIND-MOUNTS** — the escape surface:
   - **Writable bind-mounts** shared with the host (`/datastore`, `/data`,
     `/mnt`, `/opt/app`…). If a **host root process** reads/executes what
     you write there → write a payload it consumes → host RCE/root.
   - **Shared network namespace** (`/proc/net/unix` lists host sockets like
     `containerd.sock`; host loopback services visible). Host `127.0.0.1`
     services become reachable.
   - **Docker socket** (`/var/run/docker.sock`) → trivial host root.
   - Dangerous caps (`CAP_SYS_ADMIN`, `CAP_SYS_PTRACE`), privileged mode,
     host PID (`/proc/1` is not the container init).
3. **loopback listeners** — HOST services (if netns shared). These are
   pivots, but **reverse the service, don't blind-fuzz it** (see below).

## Escape / pivot hypotheses (ranked)

| EV | Vector | Falsifier |
|----|--------|-----------|
| HIGH | `docker.sock` reachable → `docker run -v /:/host` → host root | `ls -l /var/run/docker.sock; curl --unix-socket /var/run/docker.sock http://x/version` |
| HIGH | Writable bind-mount consumed by a **root host process** (watcher/cron/queue) → plant payload | map what reads the shared dir; write a benign marker, watch for root-owned side effects |
| HIGH | Shared netns → host **root loopback service** with an app-specific bug | find its binary/source/config; derive routes from app context |
| MED | Dangerous capability / privileged → mount host disk, `nsenter`, release_agent cgroup escape | `capsh --print; cat /proc/self/status | grep Cap` |
| MED | Harvested creds in container env/config reused for host SSH / a real user | grep env, config, history; try SSH as mapped users |

## Rules that bite hardest here

- **R17 (anti-spin):** empty bind-mount dir or 404 route answered once is
  answered forever. Do not re-list / re-fuzz it. `loop-guard.sh`.
- **Reverse before fuzz:** a Go/Fiber/custom host API has app-specific
  routes. Generic `/api /health /v1` wordlists are near-zero EV. Find the
  binary (if the mount/pid ns lets you) or infer routes from the app theme
  and the data it processes (e.g. a medical-imaging box → image/mask/DICOM
  endpoints), then probe those.
- **user.txt first:** confirm whether the user flag is reachable from the
  container or needs a pivot, before any root work.
