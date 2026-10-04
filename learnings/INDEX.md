# Learnings index — transferable priors (grep me during recon)
# format: tags | signal→class | file

- [untagged] ? — `2million.md`
- [pdfminer,upload-pipeline,container,nextjs,python,deserialization] X-Powered-By: pdfminer.six on an upload endpoint -> pickle-deserialization RCE in the converter worker (CVE-2025-64512 class); any upload->worker pipeline -> look for the deserializer gadget — `bedside.md`
- [cohort,nginx,models-limit,failed] cohort.htb (nginx -> cohort.htb analytics app) DEFEATED both minimax-m3 ($13.8) and nemotron-3-super ($1.17, 14 falsified H) — a models-capability ceiling data point, not yet a known vector — `cohort.md`
- [freepbx,asterisk,sqli,cve-2025-57819,cron,incron] /admin -> FreePBX Administration; pin the exact FreePBX version from asset query strings -> CVE-2025-57819 unauthenticated error-based SQLi in /admin/ajax.php — `connected.md`
- [nfs,creds-leak,webmail,olivetin,command-injection,bcrypt] anonymous NFS export (showmount -e) -> onboarding/HR docs that leak first creds; an OliveTin dashboard -> StartAction shell-string argument injection as the service user — `enigma.md`
- [active-directory,windows,kerberos,rodc,ldap,smb,bloodhound] DC ports (88/389/445/464/636/3268/5985) + a Read-Only DC (RODC) in a second segment -> AD ACL/delegation chain, and the RODC is the DA path — `garfield.md`
- [rdp,lxd-container,wifi,craft-cms,cve-2026-28695,cups,cve-2026-34990] RDP-only foothold in an LXD container + an open WiFi iface (mac80211_hwsim) -> sniff cleartext creds in monitor mode; Craft CMS <=5.9.8 -> CVE-2026-28695 Yii2 behavior-injection blind RCE; CUPS <=2.4.16 -> CVE-2026-34990 local-token LPE — `layover.md`
- [ssrf,aws,localstack,emulator,yaml,url-filter-bypass,container-escape] an AWS/LocalStack emulator (aws-* vhost, ~50 services) behind a GET-only SSRF fetcher with a URL-string blocklist -> bypass with integer-decimal IP (2130706433), and ext check runs BEFORE fetch so a .yaml suffix passes — `nimbus.md`
- [untagged] ? — `oob-gates.md`
- [untagged] ? — `paperwork-lpd-pjl.md`
- [untagged] ? — `reactor.md`
- [untagged] ? — `security.md`
