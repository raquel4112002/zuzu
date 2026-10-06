# Learning: scaffold (hard) — 2026-10-05
tags: active-directory,windows,kerberos,asrep,coercer,ntlm-relay,glm-weak

## Signal → vuln class (when you see X, pursue Y)
- AD/DC box (asrep-roastable users, Coercer/PetitPotam surface) -> AS-REP roast + coercion->relay chain; but glm-5.3-flash struggles on AD/Kerberos (strong on Linux web, weak here)

## What worked (the insight, generalized — NOT box-specific steps)
- (unsolved by glm) — for hard AD prefer deepseek-v4.1-flash (solved garfield AD for $1.65); map ACLs with BloodHound before spraying

## Dead-ends (don't waste time here next time)
- glm burned $11.79/1346 reqs on AS-REP + Coercer with no DA chain; context exploded to 306M cacheRead (no R18 hygiene)

## CVE / technique refs
- active-directory-attack-chain, ntlm-relay-coercion, garfield.md
