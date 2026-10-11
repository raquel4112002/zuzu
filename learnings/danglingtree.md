# Learning: DanglingTree (Medium) — 2026-10-11
tags: AD,ADCS,ESC1,WAC,SmarterMail,DPAPI,kerberos-clock-skew

## Signal → vuln class (when you see X, pursue Y)
- CA publishes cert templates that don't exist as AD objects (dangling refs) -> pursue CreateChild on the Certificate Templates container (Template_Editors) to make one live and requestable

## What worked (the insight, generalized — NOT box-specific steps)
- five-identity chain: guest SMB -> RoE PDF creds -> WAC (6600) RCE -> SmarterMail unauth force-reset (loopback 17017) + connect-to-hub CommandMount RCE -> mailbox .bak settings.json password_encrypted decrypted with hardcoded DES-CBC keymap2 key -> noah.b -> cmdkey/DPAPI -> alex.o -> SAMR force-change-password on jake.h -> Template_Editors CreateChild -> dangling template ESC1 -> Administrator cert -> NT hash

## Dead-ends (don't waste time here next time)
- Kerberos blocked by ~7h clock skew (use faketime -f +25206s); certipy needs -dc-host + real IP (dangling DNS misdirects); LDAP password resets fail on this box (use SAMR net rpc password); WAC readback via cmd /c type breaks (use [IO.File]::ReadAllText)

## CVE / technique refs
- CVE-2026-26119 WAC RCE; CVE-2026-23760 SmarterMail connect-to-hub; ESC1 ADCS; SmarterMail DES-CBC keymap2 hardcoded key
