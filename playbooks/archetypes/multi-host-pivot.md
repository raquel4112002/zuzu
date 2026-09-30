# Archetype: Multi-Host / Pivot Target

**Match if you see:** A foothold host that is **dual-homed** (second NIC, a
route to a private range you can't reach from Kali), services bound to
`127.0.0.1` only, or config/creds referencing hosts you never scanned. Common
on HTB **Hard** (and many Medium) boxes — the flag is on a host that only the
foothold can reach.

This archetype is the **triage**: decide *"is there more network here?"* and
line up the next moves. The full copy-paste tunneling procedure is the runbook
`playbooks/pivoting-and-tunneling.md`. The terse loop is
`knowledge-base/checklists/pivoting-checklist.md`.

## Fast checks — is this multi-host? (≤ 5 min, on the foothold)

```bash
ip -brief a; ip route              # 2nd NIC / private route Kali can't reach?
cat /etc/hosts; cat /etc/resolv.conf   # named internal hosts / internal DNS domain
ss -tlnp 2>/dev/null || netstat -tlnp  # 127.0.0.1-only listeners (DB, panel, app)
cat ~/.ssh/known_hosts /home/*/.ssh/known_hosts 2>/dev/null   # hosts it SSHes to
arp -a 2>/dev/null; ip neigh       # neighbours it has talked to
```
```cmd
:: Windows foothold
ipconfig /all & route print & arp -a
type C:\Windows\System32\drivers\etc\hosts
netstat -ano | findstr LISTENING
```

**It's multi-host if ANY of these is true:**
- A second interface / a route to `10/8`, `172.16/12`, `192.168/16` not = your
  tun0 segment.
- Services listening only on loopback.
- `hosts` / `known_hosts` / `resolv.conf` name hosts that aren't the foothold.
- App or DB config points at a non-foothold IP/hostname.

## What to enumerate from the first foothold

```bash
# Subnet math: 2nd NIC 172.16.5.15/24 → segment 172.16.5.0/24
# Live-host sweep WITHOUT nmap (rarely installed on the box):
for i in $(seq 1 254); do (ping -c1 -W1 172.16.5.$i >/dev/null 2>&1 && echo "172.16.5.$i UP") & done; wait
# Quick TCP check on a live host (bash /dev/tcp):
for p in 22 80 135 139 443 445 1433 3306 3389 5985 8080; do (echo >/dev/tcp/172.16.5.20/$p) >/dev/null 2>&1 && echo "$p open"; done
```
Then build a **real** port/service picture *from Kali through the tunnel* —
never a full nmap on the foothold.

## Credentials / config files that reveal internal hosts

Loot these on the foothold — they name the next host **and** often hand you the
creds to log into it (credential reuse is the whole point of a pivot):

- `~/.ssh/` — `id_rsa`, `config`, `known_hosts`, `authorized_keys`.
- Web/app configs: `wp-config.php`, `.env`, `appsettings.json`,
  `config.php`, `application.properties`, `web.config`, `settings.py`,
  `docker-compose.yml` (service hostnames + DB creds).
- DB connection strings (grep `/var/www /opt /home` for `host=`, `server=`,
  `password`, `connectionstring`).
- `~/.bash_history`, `~/.mysql_history`, `~/.psql_history` — real commands to
  real internal hosts.
- Password managers / vaults, backup archives, cron scripts that curl/ssh out.
- Windows: `cmdkey /list`, saved RDP `.rdp` files, `runas` history, DPAPI
  creds, `Groups.xml` (GPP).

```bash
grep -rIniE 'password|passwd|secret|connectionstring|host=|server=' \
  /var/www /opt /home /etc 2>/dev/null | grep -v Binary | head -40
```

## Ordered next steps once a second host is visible

1. **Establish a tunnel** — `playbooks/pivoting-and-tunneling.md`. Prefer
   ligolo-ng (native route); chisel `R:socks` + proxychains as fallback;
   `ssh -D` / sshuttle if you have SSH creds.
2. **Verify reach:** `proxychains4 -q nmap -sT -Pn -n -p <ports> <internal-ip>`
   (or native nmap if ligolo/sshuttle routed it).
3. **Try credential reuse first** — the foothold creds/keys/hashes against the
   internal host (`nxc smb`, `evil-winrm`, `ssh`, `mssqlclient`) before any
   fresh exploitation.
4. **Treat the internal host as a new target:** match it to its own archetype
   (AD, webapp, DB, etc.) and enumerate it through the tunnel.
5. **Feed the hypothesis bank:** add one hypothesis per internal host, update
   `reports/<target>/target-model.md` with the internal segment and a bold
   **"PIVOTING REQUIRED"** note, and `orchestrator.sh report` the discovery.
6. **Watch for a third segment** — the second host may itself be dual-homed →
   **double pivot** (ligolo agent → pivot1's internal IP).

## Common pitfalls

1. **Rooting the foothold before checking for a 2nd NIC.** Do Step 0 detection
   immediately on landing.
2. **Assuming Kali can reach the internal host.** It can't route there — the
   tunnel is mandatory, and reverse shells must target the pivot's internal IP.
3. **Not reusing foothold creds** on the next host before exploiting it.
4. **Trying full nmap from the foothold** instead of pivoting the scan to Kali.
5. **proxychains SYN scans** — must be `nmap -sT -Pn -n` through SOCKS.

## Routing

- **Set up the tunnel** → `playbooks/pivoting-and-tunneling.md`
- **Terse operator loop** → `knowledge-base/checklists/pivoting-checklist.md`
- **Lateral movement / remote exec** → `knowledge-base/mitre-attack/techniques/lateral-movement-deep.md`
- **Internal host is Windows/AD** → `playbooks/archetypes/ad-windows-target.md`
- **Credential reuse across hosts** → `knowledge-base/checklists/ad-attack-checklist.md`
