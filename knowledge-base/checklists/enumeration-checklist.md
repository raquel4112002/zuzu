# Enumeration Checklist — By Port/Service

> Run this checklist against every open port/service found during scanning.

## Port 21 — FTP

- [ ] `nmap --script ftp-anon,ftp-bounce,ftp-vuln* -p21 TARGET`
- [ ] Anonymous login: `ftp TARGET` → user: anonymous, pass: (blank)
- [ ] Check version: `nmap -sV -p21 TARGET` → searchsploit
- [ ] Browse and download all files if accessible
- [ ] Check for upload permissions (put a test file)
- [ ] Look for credentials, config files, backups

## Port 22 — SSH

- [ ] `nmap -sV -p22 TARGET` → check version for vulns
- [ ] `nmap --script ssh2-enum-algos -p22 TARGET`
- [ ] Try default/common creds
- [ ] Brute force: `hydra -l root -P wordlist ssh://TARGET -t 4`
- [ ] Check for authorized_keys if you have read access elsewhere

## Port 23 — Telnet

- [ ] Connect: `telnet TARGET`
- [ ] Check for banner/version info
- [ ] Try default credentials
- [ ] Brute force: `hydra -l admin -P wordlist telnet://TARGET`

## Port 25/465/587 — SMTP

- [ ] `nmap --script smtp-commands,smtp-enum-users,smtp-vuln* -p25 TARGET`
- [ ] `smtp-user-enum -M VRFY -U users.txt -t TARGET`
- [ ] User enumeration via RCPT TO
- [ ] Open relay test: `nmap --script smtp-open-relay -p25 TARGET`

## Port 53 — DNS

- [ ] Zone transfer: `dig axfr @TARGET DOMAIN`
- [ ] `dnsrecon -d DOMAIN -t std`
- [ ] `dnsenum DOMAIN`
- [ ] Reverse lookup: `dnsrecon -r RANGE/24`

## Port 80/443 — HTTP/HTTPS

- [ ] `whatweb -a 3 http://TARGET`
- [ ] `nikto -h http://TARGET`
- [ ] `gobuster dir -u http://TARGET -w directory-list-2.3-medium.txt -x php,html,txt,bak`
- [ ] `nuclei -u http://TARGET`
- [ ] Check robots.txt, sitemap.xml
- [ ] Check source code comments
- [ ] Check SSL/TLS: `sslscan TARGET`, `testssl.sh TARGET`
- [ ] Check security headers
- [ ] Check for WAF: `wafw00f http://TARGET`
- [ ] CMS detection → specific scanner (wpscan, joomscan, droopescan)
- [ ] → Follow web-app-pentest playbook

## Port 88 — Kerberos

- [ ] `kerbrute userenum --dc TARGET -d DOMAIN users.txt`
- [ ] AS-REP Roasting: `impacket-GetNPUsers DOMAIN/ -dc-ip TARGET -usersfile users.txt -no-pass`
- [ ] → Follow AD attack checklist

## Port 110/995 — POP3

- [ ] `nmap --script pop3-capabilities -p110 TARGET`
- [ ] Try default creds
- [ ] Brute force: `hydra -l user -P wordlist pop3://TARGET`

## Port 111 — RPCBind

- [ ] `rpcinfo -p TARGET`
- [ ] Check for NFS: `showmount -e TARGET`

## Port 135 — MSRPC

- [ ] `rpcclient -U "" -N TARGET`
- [ ] `impacket-rpcdump TARGET`
- [ ] Enumerate users, groups, shares

## Port 139/445 — SMB

- [ ] `enum4linux -a TARGET`
- [ ] `smbclient -L //TARGET -N`
- [ ] `smbmap -H TARGET`
- [ ] `crackmapexec smb TARGET --shares`
- [ ] `nmap --script smb-enum-shares,smb-enum-users,smb-vuln* -p445 TARGET`
- [ ] Check for EternalBlue: `nmap --script smb-vuln-ms17-010 -p445 TARGET`
- [ ] Null session access to shares?
- [ ] Download interesting files from accessible shares

## Port 143/993 — IMAP

- [ ] `nmap --script imap-capabilities -p143 TARGET`
- [ ] Try default creds
- [ ] Brute force: `hydra -l user -P wordlist imap://TARGET`

## Port 161 — SNMP

- [ ] `snmpwalk -v2c -c public TARGET`
- [ ] `snmp-check TARGET`
- [ ] `onesixtyone -c community-strings.txt TARGET`
- [ ] Extract: usernames, processes, network info, installed software

## Port 389/636 — LDAP

- [ ] `ldapsearch -x -H ldap://TARGET -b "" -s base`
- [ ] `ldapsearch -x -H ldap://TARGET -b "dc=domain,dc=com"`
- [ ] `nmap --script ldap-search,ldap-rootdse -p389 TARGET`
- [ ] Anonymous bind? Dump everything.

## Port 443 — HTTPS

- [ ] Same as HTTP +
- [ ] `sslscan TARGET`
- [ ] `testssl.sh TARGET`
- [ ] Check certificate for hostnames, emails
- [ ] Heartbleed: `nmap --script ssl-heartbleed -p443 TARGET`

## Port 1433 — MSSQL

- [ ] `nmap --script ms-sql-info,ms-sql-config -p1433 TARGET`
- [ ] `impacket-mssqlclient user:pass@TARGET`
- [ ] Try `sa` with blank password
- [ ] `xp_cmdshell` for RCE if admin

## Port 1521 — Oracle

- [ ] `odat all -s TARGET`
- [ ] `tnscmd10g status -h TARGET`

## Port 2049 — NFS

- [ ] `showmount -e TARGET`
- [ ] Mount: `mount -t nfs TARGET:/share /mnt`
- [ ] Check for no_root_squash (privesc path)

## Port 3306 — MySQL

- [ ] `nmap --script mysql-info,mysql-enum -p3306 TARGET`
- [ ] `mysql -u root -h TARGET` (no password)
- [ ] Try default creds: root/(blank), root/root, root/mysql

## Port 3389 — RDP

- [ ] `nmap --script rdp-enum-encryption -p3389 TARGET`
- [ ] BlueKeep: `nmap --script rdp-vuln-ms12-020 -p3389 TARGET`
- [ ] Try common creds
- [ ] Connect: `xfreerdp /v:TARGET /u:user /p:pass /cert-ignore`

## Port 5432 — PostgreSQL

- [ ] `nmap --script pgsql-brute -p5432 TARGET`
- [ ] `psql -h TARGET -U postgres`
- [ ] Default: postgres/(blank)

## Port 5985/5986 — WinRM

- [ ] `crackmapexec winrm TARGET -u user -p pass`
- [ ] `evil-winrm -i TARGET -u user -p pass`

## Port 6379 — Redis

- [ ] `redis-cli -h TARGET`
- [ ] `redis-cli -h TARGET INFO`
- [ ] `redis-cli -h TARGET KEYS *`
- [ ] Check for unauthenticated access
- [ ] RCE via SSH key write or webshell

## Port 8080/8443 — HTTP Alternate

- [ ] Same as HTTP/HTTPS
- [ ] Often: Jenkins, Tomcat, JBoss, WebLogic
- [ ] Check for manager/admin panels with default creds
- [ ] Tomcat: manager/tomcat, admin/admin
- [ ] Jenkins: no auth? Script console → RCE

## Port 27017 — MongoDB

- [ ] `mongosh --host TARGET`
- [ ] Check for no authentication
- [ ] `show dbs; use DB; show collections; db.COLLECTION.find()`
