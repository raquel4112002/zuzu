# Target Archetypes

Pre-built playbooks for common target types. Match your target to one of these
**before** falling back to the generic playbooks. They're more concrete, list
real CVEs, exact commands, and the most common pitfalls.

## How to pick one

Look at what the target is running (banner / version / page title / favicon
hash / robots.txt / package.json). Match it to one of these:

| Archetype | Match if you see |
|---|---|
| [`ai-orchestration.md`](ai-orchestration.md) | Flowise, LangChain Server, AnythingLLM, Dify, n8n, Langflow, marimo, ChatBot UIs, anything LLM-flavoured |
| [`modern-web-js-framework.md`](modern-web-js-framework.md) | `X-Powered-By: Next.js`, `/_next/static/`, RSC flight data, a static-looking SPA dashboard, Vite dev server (`/@vite/client`, `/@fs/`) |
| [`upload-pipeline-deserialization.md`](upload-pipeline-deserialization.md) | Upload endpoint + a separate worker/converter/queue that consumes files (thumbnail, OCR, PDF extract, ML inference, report gen), shared dir/bind-mount |
| [`medical-imaging-dicom.md`](medical-imaging-dicom.md) | DICOM ports 104/11112, `/dicom-web/`, `/studies`, Orthanc/DCM4CHEE/OHIF, "studies/series/modality/PACS" copy |
| [`custom-ftp-or-file-server.md`](custom-ftp-or-file-server.md) | Wing FTP, FileZilla Server, ProFTPD, Pure-FTPd, custom file shares |
| [`webapp-with-login.md`](webapp-with-login.md) | Generic web login form, no obvious framework hits |
| [`cms-and-plugins.md`](cms-and-plugins.md) | WordPress, Joomla, Drupal, Ghost, custom CMS |
| [`ad-windows-target.md`](ad-windows-target.md) | Ports 88/389/445/3268/5985, Windows banners |
| [`linux-snmp-host.md`](linux-snmp-host.md) | UDP 161 open (SNMP), Linux host |
| [`devops-tools.md`](devops-tools.md) | Jenkins, GitLab, Gitea, Jira, Confluence, TeamCity, Argo |
| [`api-only-target.md`](api-only-target.md) | JSON-only responses, Swagger/OpenAPI exposed, no HTML UI |
| [`multi-host-pivot.md`](multi-host-pivot.md) | Second NIC/subnet, internal-only service, configs naming hosts you can't reach — the box is bigger than the foothold |

> **Hard / insane target?** Archetypes still apply, but first read
> [`knowledge-base/checklists/hard-box-playbook.md`](../../knowledge-base/checklists/hard-box-playbook.md):
> it sets the enumeration depth floor and chain-depth expectation that
> separate a real Hard blocker from stopping one stage too early.

## Workflow

1. Pick archetype → read its file end-to-end (they're short).
2. Run the **fast checks** section first (≤ 5 min total).
3. If fast checks miss, run the **deep checks** with `timebox.sh`.
4. If both miss, fall back to `playbooks/web-app-pentest.md` (generic).

## Matching skills per archetype

Installed AgentSkills carry exact exploit recipes. Pull the skill once the
archetype's CVE/pattern is your highest-EV hypothesis — the archetype is the
prior, the skill is the payload.

| Archetype | Matching skills |
|---|---|
| `ai-orchestration.md` | `langflow-rce` (CVE-2026-33017), `marimo-terminal-rce` (CVE-2026-39987), `container-escape-techniques`, `sandbox-escape-techniques`, `node-inspector-privesc` |
| `modern-web-js-framework.md` | `react2shell-rce` (CVE-2025-55182/66478), `node-inspector-privesc`, `obfuscator-io-js-deobfuscation`, `single-exec-listener-lifecycle` |
| `upload-pipeline-deserialization.md` | `container-escape-techniques`, `sandbox-escape-techniques`, `xxe-xml-external-entity`, `reverse-shell-techniques` |
| `medical-imaging-dicom.md` | `upload-pipeline-deserialization.md`, `container-foothold.md`, `container-escape-techniques`, `xxe-xml-external-entity` |
| `container-foothold.md` | `container-escape-techniques`, `kubelet-exec-via-sa-token`, `linux-security-bypass`, `linux-lateral-movement` |
| `ad-windows-target.md` | `ntlm-relay-coercion`, `windows-privilege-escalation`, `windows-lateral-movement`, `jwt-oauth-token-attacks` |
| `devops-tools.md` | `kubelet-exec-via-sa-token`, `container-escape-techniques`, `unauthorized-access-common-services`, `node-inspector-privesc` |
| `webapp-with-login.md` | `authbypass-authentication-flaws`, `jwt-oauth-token-attacks`, `sqli-sql-injection`, `xxe-xml-external-entity` |
| `api-only-target.md` | `authbypass-authentication-flaws`, `jwt-oauth-token-attacks`, `sqli-sql-injection` |
| `cms-and-plugins.md` | `sqli-sql-injection`, `xxe-xml-external-entity`, `reverse-shell-techniques` |
| `custom-ftp-or-file-server.md` | `unauthorized-access-common-services`, `reverse-shell-techniques` |
| `multi-host-pivot.md` | `tunneling-and-pivoting`, `linux-lateral-movement`, `windows-lateral-movement`, `ntlm-relay-coercion` |
| `linux-snmp-host.md` | `unauthorized-access-common-services`, `linux-lateral-movement` |
| `network-printer-lpd-pjl.md` | `reverse-shell-techniques`, `linux-lateral-movement` |

Cross-cutting (any archetype after a foothold): `reverse-shell-techniques`,
`single-exec-listener-lifecycle`, `tunneling-and-pivoting`,
`linux-security-bypass`.

## Common rule for ALL archetypes

If the live app needs auth, **always run `scripts/source-dive.sh <github-repo> <version>`**
before declaring stuck. The actual unauth attack surface is in the source, not
in the running app.
