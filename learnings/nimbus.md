# Learning: nimbus — 2026-10-05
tags: ssrf,aws,localstack,codebuild,privileged-container,gosu-bypass,container-escape

## Signal → vuln class (when you see X, pursue Y)
- AWS/LocalStack emulator (aws-* vhost, _localstack/info=floci-always-free) behind GET-only SSRF fetcher with URL-string blocklist -> integer/octal-IP + #.yaml fragment bypass

## What worked (the insight, generalized — NOT box-specific steps)
- SSRF->octal IMDS->nimbus-web-role creds->boto3 gate->SQS SendMessage->worker unsafe yaml.load->container RCE; then floci:4566 unsigned=root account, CodeBuild image floci/floci:latest privilegedMode:True + BASH_FUNC_id%% env var to bypass gosu privilege-drop -> uid0 + CapEff full -> busybox mount /dev/sda4 -> host root.txt

## Dead-ends (don't waste time here next time)
- CodeBuild with any image EXCEPT the local floci/floci:latest FAULTs at DOWNLOAD_SOURCE (no registry egress); the workshop skill wrongly lists CodeBuild as a dead lead — on THIS box it IS the intended root path (skill was written against a different respawn); no docker.sock in worker; docker.sock learning note was wrong; SSH key bruteforce; app-side yaml.load is safe_load

## CVE / technique refs
- —
