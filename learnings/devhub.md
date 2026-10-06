# Learning: devhub — 2026-10-06
tags: mcp,ssrf,rce,jupyter,lateral-movement,egress-filtered,credentials,webapp

## Signal → vuln class (when you see X, pursue Y)
- Static 'services overview' page advertising an internal dev tool on a NON-STANDARD HIGH PORT (6274) -> go straight at that port for an unauthenticated dev-tool RCE (inspector/proxy/debug consoles bind 0.0.0.0 by default)

## What worked (the insight, generalized — NOT box-specific steps)
- MCPJam-style inspector RCE gave stdio spawn; when target->attacker egress is FILTERED (no reverse shells), the app's OWN caller-directed proxy endpoint (/api/mcp/oauth/proxy) becomes the output channel: RCE writes command output to a file, proxy reads it back. Key detail: such proxies often only populate the response body for Content-Type: application/json -- so wrap the command output as JSON before reading. Chain: unauth RCE as svc user -> secrets leak via 'ps auxww' / /proc/PID/cmdline (Jupyter --ServerApp.token) -> drive that user's own service via its kernel WebSocket (node>=22 has built-in WebSocket, no pip/internet needed) to become a MORE privileged user -> read root-owned-but-readable service source -> hardcoded API key + hidden credential-dump tool -> root SSH key -> ssh root@localhost

## Dead-ends (don't waste time here next time)
- Reverse shells (curl / bash /dev/tcp / nc) are a TOTAL waste when target egress is filtered -- test egress in ONE cheap probe before building any shell infra; use the app's own SSRF/proxy as read-back instead. 'sudo -S' with a dumped password fails because sudo needs a real TTY. Directly reaching ports the target itself opens (8000/8001) is useless -- the firewall only exposes the originally-scanned ports. Guessing API keys wasted a probe; read the server source first (it was readable as the pivoted user).

## CVE / technique refs
- CVE-2026-23744; itsC1SCO/mcpjam-to-root
