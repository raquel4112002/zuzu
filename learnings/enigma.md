# Learning: enigma (easy) — 2026-10-04
tags: nfs,creds-leak,webmail,olivetin,command-injection,bcrypt

## Signal → vuln class (when you see X, pursue Y)
- anonymous NFS export (showmount -e) -> onboarding/HR docs that leak first creds; an OliveTin dashboard -> StartAction shell-string argument injection as the service user

## What worked (the insight, generalized — NOT box-specific steps)
- chain the leaked cred across services (webmail->app RCE->bcrypt crack->SSH); for a root-owned localhost-only service, reach it from the low-priv shell and hit its RPC (OliveTin GetDashboard bindingId -> StartAction)

## Dead-ends (don't waste time here next time)
- brute-forcing SSH before reading the NFS docs

## CVE / technique refs
- sandboxed-shell-loopback-privesc (OliveTin), reverse-shell-techniques
