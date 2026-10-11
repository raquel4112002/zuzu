# Learning: htb-airport (medium) — 2026-10-11
tags: spring,heapdump,xxe,kafka,clickhouse,privesc,systemd,timer

## Signal → vuln class (when you see X, pursue Y)
- Java/Spring app exposes /actuator/heapdump -> carve the loaded config class's constant pool for hardcoded creds; service creds in a broker's server.properties are reused for OS accounts -> SSH; a root systemd timer executing a script that lives in a directory writable by a lower-privileged service = root RCE

## What worked (the insight, generalized — NOT box-specific steps)
- Three pivots mattered. (1) /actuator/heapdump returned the gateway's HPROF; the DataSourceConfig.class constant pool sits in the heap verbatim, so carving ~300 bytes around 'setPassword' yielded the HikariConfig creds (svc_events / Yl4aCgh4y2PnU) which authenticated to ClickHouse. (2) The downstream XML parser used lxml with resolve_entities=True; the entity only had to be placed in a field the canonicalizer preserves (LegData/RemarkFreeText) and the resolved file content was exfiltrated IN-BAND through the app's own Kafka->ClickHouse pipeline, readable with the creds we already held -- no egress required. (3) The root DLQ drainer (systemd oneshot, every 2 min) ran 'python3 /var/lib/clickhouse/user_files/aidx_quarantine.py' as root, and that directory is owned by the clickhouse user whose password we had captured from the drainer's own argv (/proc/<pid>/cmdline is world-readable even for root processes) -> plant payload with engine_file_truncate_on_insert=1 -> root. Kafka's server.properties also leaked user_svc_infra='Ny2hdpme$bwT3', and that same string was the OS password for svc-infra -> SSH foothold.

## Dead-ends (don't waste time here next time)
- Long-rockyou brute against ClickHouse (wasted hours, 0 hits) - the password was never guessable, it had to be carved or coaxed out of a root process. OOB-callback XXE tests reported '0 callbacks' and I first read that as a negative: egress from the box was BLOCKED, so those results were INCONCLUSIVE - in-band exfiltration through the app's own data pipeline was the reliable oracle. /tmp on Kali was a full 2GB tmpfs which silently broke every file write and produced empty wordlists/results; verify df before trusting empty output. Fast SSH probing tripped fail2ban and made port 22 unreachable, which again looked like a negative. Header-based host routing and /actuator/gateway/* route injection were dead.

## CVE / technique refs
- CVE-2025-24813?no; lxml resolve_entities XXE; ClickHouse file()/engine_file_truncate_on_insert; Spring Boot actuator heapdump; systemd oneshot timer privesc
