# 2million HTB - Quick Reference

**Target:** 10.129.229.66  
**Flags:** User: `f62f0e217ed2fb956d5962173028da77` | Root: `b819ec0c9850d32e2991122841185124`

## Attack Chain:
1. **Web:** `/api/v1/admin/settings/update` (PUT) → `is_admin=1`
2. **Web:** `/api/v1/admin/vpn/generate` (POST) → cmd injection
3. **Creds:** `.env` → `SuperDuperPass123`
4. **SSH:** `admin@target`
5. **Privesc:** CVE-2023-0386 (kernel 5.15.70)

## Key Techniques:
- API parameter manipulation for privilege escalation
- Command injection in admin VPN endpoint
- Password reuse from web to SSH
- Kernel overlayfs exploit

## Reusable Payloads:
```json
// Admin escalation
{"email":"user@domain","is_admin":1}

// Command injection
{"username":"test;command;"}
```

## Exploit Repo:
- Kernel: github.com/xkaneiki/CVE-2023-0386
