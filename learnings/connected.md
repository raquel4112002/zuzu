# Learning: connected (easy) — 2026-10-04
tags: freepbx,asterisk,sqli,cve-2025-57819,cron,incron

## Signal → vuln class (when you see X, pursue Y)
- /admin -> FreePBX Administration; pin the exact FreePBX version from asset query strings -> CVE-2025-57819 unauthenticated error-based SQLi in /admin/ajax.php

## What worked (the insight, generalized — NOT box-specific steps)
- extractvalue + length/mid chunked extractor (SLEEP/stacked probes lie); DB write -> asterisk-uid RCE via cron_jobs table driven by an HTTP pull-loop; root via incrond -> sysadmin_ha require()ing a PHP file from the asterisk webroot

## Dead-ends (don't waste time here next time)
- SLEEP-based blind SQLi timing (unreliable here); the GPG-gated sysadmin_manager hook

## CVE / technique refs
- freepbx-unauth-sqli-rce, CVE-2025-57819
