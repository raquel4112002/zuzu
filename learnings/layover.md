# Learning: layover (medium) — 2026-10-04
tags: rdp,lxd-container,wifi,craft-cms,cve-2026-28695,cups,cve-2026-34990

## Signal → vuln class (when you see X, pursue Y)
- RDP-only foothold in an LXD container + an open WiFi iface (mac80211_hwsim) -> sniff cleartext creds in monitor mode; Craft CMS <=5.9.8 -> CVE-2026-28695 Yii2 behavior-injection blind RCE; CUPS <=2.4.16 -> CVE-2026-34990 local-token LPE

## What worked (the insight, generalized — NOT box-specific steps)
- monitor-mode capture of a cleartext login on the internal WiFi; decrypt a Craft encrypted settings blob with the target's OWN Security.php; CUPS: rogue localhost IPP server captures the Authorization: Local token -> sudoers via a file:// print queue

## Dead-ends (don't waste time here next time)
- assuming RDP box == no other surface (the WiFi + internal portal were the path); SSH as contractor (PasswordAuthentication off by design)

## CVE / technique refs
- craft-cms-behavior-rce, cups-local-token-lpe, rdp-gui-foothold-ops
