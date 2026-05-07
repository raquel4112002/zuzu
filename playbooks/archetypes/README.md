# Target Archetypes

Pre-built playbooks for common target types. Match your target to one of these
**before** falling back to the generic playbooks. They're more concrete, list
real CVEs, exact commands, and the most common pitfalls.

## How to pick one

Look at what the target is running (banner / version / page title / favicon
hash / robots.txt / package.json). Match it to one of these:

| Archetype | Match if you see |
|---|---|
| [`ai-orchestration.md`](ai-orchestration.md) | Flowise, LangChain Server, AnythingLLM, Dify, n8n, ChatBot UIs, anything LLM-flavoured |
| [`custom-ftp-or-file-server.md`](custom-ftp-or-file-server.md) | Wing FTP, FileZilla Server, ProFTPD, Pure-FTPd, custom file shares |
| [`webapp-with-login.md`](webapp-with-login.md) | Generic web login form, no obvious framework hits |
| [`cms-and-plugins.md`](cms-and-plugins.md) | WordPress, Joomla, Drupal, Ghost, custom CMS |
| [`ad-windows-target.md`](ad-windows-target.md) | Ports 88/389/445/3268/5985, Windows banners |
| [`linux-snmp-host.md`](linux-snmp-host.md) | UDP 161 open (SNMP), Linux host |
| [`devops-tools.md`](devops-tools.md) | Jenkins, GitLab, Gitea, Jira, Confluence, TeamCity, Argo |
| [`api-only-target.md`](api-only-target.md) | JSON-only responses, Swagger/OpenAPI exposed, no HTML UI |

## Workflow

1. Pick archetype → read its file end-to-end (they're short).
2. Run the **fast checks** section first (≤ 5 min total).
3. If fast checks miss, run the **deep checks** with `timebox.sh`.
4. If both miss, fall back to `playbooks/web-app-pentest.md` (generic).

## Common rule for ALL archetypes

If the live app needs auth, **always run `scripts/source-dive.sh <github-repo> <version>`**
before declaring stuck. The actual unauth attack surface is in the source, not
in the running app.
