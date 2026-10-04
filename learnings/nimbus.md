# Learning: nimbus (hard) — 2026-10-04
tags: ssrf,aws,localstack,emulator,yaml,url-filter-bypass,container-escape

## Signal → vuln class (when you see X, pursue Y)
- an AWS/LocalStack emulator (aws-* vhost, ~50 services) behind a GET-only SSRF fetcher with a URL-string blocklist -> bypass with integer-decimal IP (2130706433), and ext check runs BEFORE fetch so a .yaml suffix passes

## What worked (the insight, generalized — NOT box-specific steps)
- (partial — user only) IMDS via decimal IP -> web-role creds; SQS SendMessage -> worker.py unsafe yaml.Loader RCE into a container

## Dead-ends (don't waste time here next time)
- blind route-fuzzing the static Next.js page; SSH brute; kernel-exploit hunt; the UNTESTED root path is docker.sock INSIDE the worker-container (POST /containers/create Binds:[/:/h])

## CVE / technique refs
- ssrf-filter-bypass-aws-emulator, container-to-host-escalation
