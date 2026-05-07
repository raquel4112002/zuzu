# Archetype: CMS & Plugins

**Match if you see:** WordPress, Joomla, Drupal, Ghost, MediaWiki, custom CMS.

## Fast checks (≤ 5 min)

### WordPress
```bash
curl -s http://target/wp-login.php
curl -s http://target/?author=1                            # leaks admin username
curl -s http://target/wp-json/wp/v2/users                  # all users (often anon)
curl -s http://target/wp-content/uploads/                  # directory listing?
curl -s http://target/readme.html | grep -i "version"
timebox.sh 90 wpscan --url http://target -e u,vp,vt --random-user-agent
```

### Joomla
```bash
curl -s http://target/administrator/manifests/files/joomla.xml | grep version
curl -s http://target/api/index.php/v1/content/articles    # API enum
joomscan -u http://target
```

### Drupal
```bash
curl -sI http://target/CHANGELOG.txt
curl -s http://target/core/CHANGELOG.txt
droopescan scan drupal -u http://target
```

## Deep checks

### Plugin / theme CVEs
The **plugins** are the bug source, not the core. Always enumerate them:
```bash
wpscan --url http://target -e ap,at --plugins-detection aggressive
```
Common winners:
- Any plugin with "Uploader", "Backup", "File", "Import" in the name
- `wp-file-manager` (CVE-2020-25213)
- Slider Revolution (CVE-2014-9734 + many later)
- Elementor flavors (multiple recent CVEs)

### XML-RPC abuse (WordPress)
```bash
curl -s http://target/xmlrpc.php
# pingback.ping for SSRF
# system.multicall for credential brute force amplification
```

### Source dive
```bash
bash scripts/source-dive.sh WordPress/WordPress <version>
# For specific plugins, find the repo and dive
```

## Common pitfalls

1. **Brute-forcing wp-login when xmlrpc.php is open** — XML-RPC has no rate
   limit and `system.multicall` lets you try ~1000 passwords per request.
2. **Ignoring uploaded media** — `/wp-content/uploads/<year>/<month>/` often
   has backup files, .sql dumps, .env, screenshots with creds.
3. **Skipping the theme** — custom themes in HTB-style boxes often have the
   actual vuln (file include, eval).
