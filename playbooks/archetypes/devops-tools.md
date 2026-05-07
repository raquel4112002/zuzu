# Archetype: DevOps / CI / Source-Code Hosting Tools

**Match if you see:** Jenkins, GitLab, Gitea, Gogs, Jira, Confluence, TeamCity,
Argo CD, ArgoWorkflows, Drone, Concourse, Bamboo, SonarQube, Nexus, Artifactory.

## Why these are juicy

DevOps tools are jackpots:
- Run scripts as a feature (CI runners → RCE by design)
- Hold credentials for cloud, prod servers, registries
- Often run as privileged users / Docker socket access
- Frequent CVEs, slow patching cadence
- Frequently exposed by mistake to the internet

## Fast checks (≤ 5 min)

### Jenkins
```bash
curl -s http://target:8080/ | grep -i jenkins
curl -s http://target:8080/login
curl -s http://target:8080/script                 # /script = Groovy console (auth bypass = RCE)
curl -s http://target:8080/asynchPeople/api/json  # leaks usernames
curl -s http://target:8080/whoAmI                 # current user
curl -s http://target:8080/manage
# Anonymous read often enabled:
curl -s http://target:8080/job/*/api/json
```
**Default creds:** `admin / admin`, `jenkins / jenkins`, `admin / password`.

### GitLab
```bash
curl -s http://target/api/v4/version
curl -s http://target/users/sign_in
curl -s http://target/explore                     # public projects
curl -s http://target/api/v4/projects?visibility=public
```
**CVEs to try:** CVE-2023-7028 (password reset to attacker email),
CVE-2021-22205 (pre-auth RCE in ExifTool path).

### Gitea / Gogs
```bash
curl -s http://target:3000/api/v1/version
curl -s http://target:3000/explore/repos
curl -s http://target:3000/issues
```

### Jira / Confluence
```bash
curl -s http://target/rest/api/2/serverInfo
curl -s http://target/login.jsp
# Confluence
curl -s http://target/wiki/aboutPage.action
curl -s http://target/aui/aui-version.txt
```
**CVEs:** CVE-2022-26134 (Confluence OGNL → RCE), CVE-2023-22515
(Confluence broken auth), CVE-2022-0540 (Jira Seraph filter bypass).

### TeamCity
```bash
curl -s http://target:8111/app/rest/server
```
**CVEs:** CVE-2023-42793 (auth bypass → RCE).

## Deep checks

### A. Anonymous read across all of them
Most DevOps tools allow anonymous read of *something* by default:
- Jenkins: job configs, build logs (full of secrets)
- GitLab: public projects, snippets, runners
- Gitea: public repos, issues
- Jira: project list, user list

Always pull the full anon-readable surface before anything else:
```bash
curl -s http://target:8080/asynchPeople/api/json | jq          # Jenkins users
curl -s http://target/api/v4/users.json                        # GitLab users (if anon list enabled)
curl -s http://target/rest/api/2/user/picker?query=.           # Jira user picker
```

### B. Source-dive
```bash
bash scripts/source-dive.sh jenkinsci/jenkins <version>
bash scripts/source-dive.sh gitlabhq/gitlabhq <version>
bash scripts/source-dive.sh go-gitea/gitea <version>
```

### C. Once authenticated → RCE everywhere
- **Jenkins** → Manage Jenkins → Script Console → Groovy:
  `"id".execute().text` or `Runtime.getRuntime().exec("...")`
- **GitLab** → CI/CD pipeline trigger with malicious .gitlab-ci.yml
- **TeamCity** → build configurations with shell steps
- **Argo CD / Workflows** → submit workflow with shell exec
- **Confluence** → space admin, attach a malicious template

### D. Pipeline credentials harvest
Once you can read pipelines/jobs → all stored credentials are yours:
- Jenkins: `/credentials/store/system/domain/_/`
- GitLab: project → Settings → CI/CD → Variables (masked but not protected
  from a shell in the runner)
- TeamCity: Project parameters

### E. Runner / agent abuse
CI runners typically have:
- Docker socket mounted (`/var/run/docker.sock`) → host takeover
- Cloud IAM credentials
- Network access to internal infra

If you can run a single CI job, you usually own the runner host.

## Common pitfalls

1. **Targeting just the login page** — anonymous endpoints often expose more
   than authenticated ones do for low-priv users.
2. **Not enumerating users** — every DevOps tool leaks usernames somewhere.
3. **Stopping at "low privilege user"** — low-priv users on Jenkins/GitLab
   can often still trigger builds, which run on runners as a different
   identity entirely.
4. **Ignoring runners** — the *real* attack surface is rarely the controller;
   it's the runners/agents that execute jobs.

## Pivot targets

- Cloud IAM creds (AWS metadata service from runners)
- SSH keys in `~/.ssh/` of the build user
- Docker socket → host root
- Internal git repos with .env, secrets, infra-as-code
- Slack/Discord webhooks for further phishing
