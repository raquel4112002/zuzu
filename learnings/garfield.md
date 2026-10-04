# Learning: garfield (hard) — 2026-10-04
tags: active-directory,windows,kerberos,rodc,ldap,smb,bloodhound

## Signal → vuln class (when you see X, pursue Y)
- DC ports (88/389/445/464/636/3268/5985) + a Read-Only DC (RODC) in a second segment -> AD ACL/delegation chain, and the RODC is the DA path

## What worked (the insight, generalized — NOT box-specific steps)
- map ACL edges with BloodHound; abuse inherited write (Script-Path/GenericAll/ForceChangePassword) to a shell; recover DA from the RODC via its krbtgt_NNNN key (RODC caches it)

## Dead-ends (don't waste time here next time)
- treating the RODC as a dead secondary host; password-spray before mapping ACLs

## CVE / technique refs
- active-directory-attack-chain, kerberos-clock-skew-shims, internal-network-pivot-relay
