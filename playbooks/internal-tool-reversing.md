# Playbook: Internal Tool Reversing and Secret Extraction

Use this when you find a custom binary, script, or internal utility on a target, especially in SMB shares, backup archives, admin panels, internal portals, or support tool bundles.

---

## Why this matters

Internal tools often contain:
- hardcoded usernames or passwords
- API tokens
- LDAP paths
- crypto keys
- domain names
- internal URLs
- service account logic
- insecure assumptions about trust

If you find a custom internal tool, prioritize it before brute force or broad spraying.

---

## Priority Triggers

Treat internal tools as high-priority when any of these are true:

- anonymous SMB share exposes custom executables
- internal admin/support bundle contains one non-public tool among public tools
- config/backups contain proprietary utilities
- tool names suggest user lookup, inventory, admin, sync, backup, deploy, or support workflow
- target is AD-heavy and the tool likely talks to LDAP, SMB, WinRM, SQL, or internal APIs

Typical examples:
- `UserInfo.exe`
- `SupportTool.exe`
- `BackupClient.jar`
- `sync.ps1`
- `inventory.py`

---

## Fast Triage Workflow

### 1. Identify the file type first

```bash
file TOOL
sha256sum TOOL
strings TOOL | head -200
```

Classify the tool:
- .NET PE
- native PE
- ELF
- shell / PowerShell / Python / batch script
- Java JAR
- archive bundle
- Electron / packaged JS app

If bundled archive exists, extract everything and inspect sidecar files:

```bash
7z l archive.zip
7z x archive.zip -o./extracted
find extracted -maxdepth 2 -type f | sed -n '1,200p'
```

Always inspect:
- `.config`
- `.json`
- `.ini`
- `.xml`
- `.ps1`
- `.bat`
- `.dll`
- `.deps.json`
- `.runtimeconfig.json`

---

### 2. Hunt for obvious secrets and trust paths

Search strings and configs for:
- `password`
- `username`
- `token`
- `secret`
- `key`
- `ldap`
- `DirectoryEntry`
- `base64`
- `decrypt`
- `api`
- `Authorization`
- domain names
- URLs
- internal hostnames

```bash
strings TOOL | grep -E -i 'password|username|token|secret|key|ldap|DirectoryEntry|base64|decrypt|api|auth'
find extracted -type f | xargs grep -RniE 'password|username|token|secret|key|ldap|api|auth' 2>/dev/null
```

Record immediately:
- recovered usernames
- domains
- bind strings
- encrypted blobs
- hardcoded keys
- internal endpoints

---

## Type-Specific Guidance

### A. .NET executables

Priority tools:
- ILSpy / ilspycmd
- dnSpy (if GUI available)
- strings as fallback

Look for these first:
- `DirectoryEntry`
- `DirectorySearcher`
- `AuthenticationTypes`
- `FromBase64String`
- `Encoding.ASCII.GetBytes`
- `Protected`
- `getPassword`
- `Decrypt`
- `token`
- `HttpClient`

Useful searches in decompiled output:
- `password`
- `username`
- `LDAP://`
- `DirectoryEntry(`
- `Authorization`
- `Convert.FromBase64String`
- `Xor`
- `AES`
- `key =`

Heuristic:
- if you see `DirectoryEntry("LDAP://...", "DOMAIN\\user", password)` then the binary likely contains either the password, a reversible transform, or the materials needed to derive it

Fallback when GUI decompiler is unavailable:
- use `strings`
- inspect configs
- inspect referenced class/function names
- inspect any blog/writeup only as a clue, not as blind instruction

---

### B. PowerShell / Batch / Shell scripts

Read the source directly first.

Look for:
- plaintext creds
- alternate data sources
- exported environment variables
- API headers
- path assumptions
- service account invocations
- scheduled task or remote execution logic

---

### C. Python / JS / JAR tools

Inspect:
- source files
- embedded config
- package manifests
- environment variable usage
- API clients
- authentication helpers

Search for:
- connection strings
- bearer tokens
- database creds
- LDAP bind credentials
- encryption routines

---

### D. Native binaries

If native and time-sensitive:
- do strings triage first
- inspect adjacent configs/resources
n- prefer dynamic observation if safe

Use:
- `strings`
- `objdump -x`
- `rabin2 -I`
- `ltrace` / `strace` when appropriate and safe

---

## Decision: Static vs Dynamic Analysis

### Prefer static first when:
- configs are present
- strings already reveal secrets or domains
- binary is .NET or script-based
- you only need creds or endpoints

### Consider dynamic next when:
- static shows connection logic but hides the final secret
- you can run the tool safely in a controlled environment
- you need to observe network targets, queries, or runtime decryption

Before dynamic execution, ask:
- am I executing untrusted code from the target?
- do I need user approval under current rules?
- can I isolate it first?

Do not blindly execute random internet code or target-delivered code without considering safety and user rules.

---

## Output Discipline

As soon as you recover anything useful, write it down in the report or notes:
- account names
- domains
- secret material
- query patterns
- API paths
- relevant code snippets

Do not rely on memory.

---

## Pivot Rules

If a tool reveals:

### LDAP path + user context
Then:
- attempt LDAP auth
- enumerate `info`, `description`, `memberOf`, SPNs, delegation flags, and ACL-relevant objects

### Internal API token or secret
Then:
- enumerate exposed endpoints first
- check for admin-only or backup/export functionality

### Backup or restore logic
Then:
- inspect for path traversal, insecure restore, secret leakage, privileged execution, or trust boundary flaws

### Service account creds
Then:
- validate the creds across SMB, WinRM, LDAP, MSSQL, SSH, or app login depending on environment

---

## Minimal Report Evidence

Keep at least:
- where the tool was found
- why it stood out
- file list / hashes if relevant
- strings or decompiled code snippet proving the secret path
- recovered creds or pivots
- exact next action enabled by the tool

---

## One-Screen Checklist

- [ ] Identify type
- [ ] Extract archive and sidecar files
- [ ] Search strings/configs for secrets and domains
- [ ] Classify auth mechanism (LDAP/API/DB/SSH/etc.)
- [ ] If .NET, inspect decompiled logic or class/function names
- [ ] Record recovered materials immediately
- [ ] Validate recovered access on the right services
- [ ] Pivot using the most likely trust path
