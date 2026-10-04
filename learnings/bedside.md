# Learning: bedside (medium) — 2026-10-04
tags: pdfminer,upload-pipeline,container,nextjs,python,deserialization

## Signal → vuln class (when you see X, pursue Y)
- X-Powered-By: pdfminer.six on an upload endpoint -> pickle-deserialization RCE in the converter worker (CVE-2025-64512 class); any upload->worker pipeline -> look for the deserializer gadget

## What worked (the insight, generalized — NOT box-specific steps)
- foothold lands in a CONTAINER as a service acct; user.txt is NOT there -> map shared netns + writable bind-mounts, pivot via a host-local service (the real user/root live on the host)

## Dead-ends (don't waste time here next time)
- SSH brute-force (rate-limited), blind route-fuzzing a static Next.js page, kernel-exploit hunting from the container

## CVE / technique refs
- CVE-2025-64512 pdfminer pickle, container-foothold.md, upload-pipeline-deserialization.md
