# Archetype: Upload Pipeline → Deserialization (file → worker → gadget)

**Match if you see:** an upload endpoint (image/PDF/CSV/doc/archive/model) ·
a separate **worker/converter/queue** process consuming uploads (thumbnailer,
OCR, PDF text-extract, ML inference, report generator) · a shared upload dir /
bind-mount / message queue between the web tier and the worker · "processing",
"your file is queued", async status polling · a cache dir the parser writes
and later re-reads.

**The mindset shift (this is the whole archetype):**
The upload endpoint is rarely the bug — **the worker that consumes the file is**.
Map `upload → which process reads it → in what format → with which library`,
then pick the gadget for *that* deserializer. Code-exec lands as the **worker's**
user, which is usually a different (often more privileged, often containerised)
identity than the web app. Cross-reference `container-foothold.md` — the worker
frequently runs in its own container with a writable bind-mount back to a root
host process.

## Fast map (do this before any payload)

```bash
# 1) What formats does it accept, and what re-reads them?
#    probe MIME/extension handling; watch for an async "status"/"job" response
curl -sF 'file=@x.png' http://target/upload ; # note: sync 200 vs 202+job_id (=worker)
# 2) Identify the consumer: error strings, stack traces, page copy, /proc on a foothold
#    "pickle", "yaml.load", "Marshal.load", "unserialize", "phar://", library+version in tracebacks
# 3) Find the handoff channel: shared dir, Redis/RabbitMQ queue, DB blob, bind-mount
ls -la /var/uploads /data /tmp/cache ; grep -ri 'queue\|celery\|rq\|sidekiq' /app 2>/dev/null
```

## Format → gadget (pick by the consumer, not the upload)

| Consumer / format | Gadget | Falsifier / trigger |
|---|---|---|
| **Python `pickle.load`** (model files `.pkl`/`.pt`, cache files, session blobs, Celery `pickle` serializer) | class with `__reduce__` returning `(os.system, ("cmd",))` | upload a crafted pickle; worker deserializes → exec as worker user |
| **pdfminer.six CMap pickle cache** — PDF text-extract writes/reads a **pickled CMap cache**; a poisoned cache entry is unpickled on next parse | `__reduce__` in the cache pickle | **CVE-2025-64512** · drop/influence the CMap cache dir, then submit a PDF that loads that CMap |
| **PyYAML `yaml.load`** (no `SafeLoader`) | `!!python/object/apply:os.system ["cmd"]` | upload YAML config/manifest; `!!python/...` tag → exec |
| **Ruby `Marshal.load`** (Rails cache, cookies, job args) | Universal RCE gadget chain (e.g. `Gem::Requirement`) | Marshal blob into the sink; worker loads → exec |
| **PHP `unserialize` / phar** | POP chain via `__wakeup`/`__destruct`; `phar://` metadata deserialization on any file op | upload polyglot phar (valid image + phar), trigger a filesystem function with `phar://uploaded.ext/` |
| **Java `ObjectInputStream`** | ysoserial gadget (CommonsCollections, etc.) | binary blob to a Java worker that readObject's uploads |
| **Node `node-serialize` / unsafe `eval`-ish parsers** | `{"rce":"_$$ND_FUNC$$_function(){require('child_process')...}()"}` | JSON blob into the deserializer |

## Rules that bite hardest here

- **Race the consumer (TOCTOU).** Many workers validate the file, then re-open
  it to process. Write a benign file to pass validation, then swap/append the
  malicious payload before the processing read — or exploit a cache dir the
  parser writes *then* trusts on the next job (the CMap pattern). Symlink/zip-slip
  into the cache dir counts.
- **Chase the worker's identity, not the web user's.** After exec, run
  `scripts/postfoothold.sh` immediately — the worker is often a separate
  container; the escape surface (writable bind-mount feeding a root host
  process, shared netns, docker.sock) is the real path. See
  `container-foothold.md`.
- **Don't blind-fuzz the worker API.** Derive what it consumes from the app
  theme (a report generator eats templates/CSV; an imaging box eats DICOM/pixel
  data). Generic wordlists on an app-specific queue are near-zero EV (R17).
- **Format allow-lists lie.** MIME sniff vs extension vs magic-byte checks
  disagree (creativity-catalog class A). A file that is a valid PNG *and* a
  valid phar/pickle/zip slips past one check and is deserialized by another.

## Matching skills

`container-escape-techniques` / `sandbox-escape-techniques` (worker→host after
code-exec) · `xxe-xml-external-entity` (OOXML/SVG/SOAP upload parsers that
resolve entities) · `reverse-shell-techniques` + `single-exec-listener-lifecycle`
(stage the callback from the worker). Cross-link: `container-foothold.md`,
`medical-imaging-dicom.md`.
