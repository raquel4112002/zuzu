#!/usr/bin/env python3
"""Orchestrator status viewer."""
import json, sys, os

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'

with open(state_file) as f:
    s = json.load(f)

print("╔══════════════════════════════════════════════════════════════╗")
print("║  📊 ORCHESTRATOR STATUS                                     ║")
print("╚══════════════════════════════════════════════════════════════╝")
print()
print(f"  Target:    {s['target']}")
print(f"  Phase:     {s['phase']} → {s['sub_phase']}")
print(f"  Attempts:  {s.get('attempt', 0)}")
print()
print("  ── Open Ports ──")
for port, info in s.get('services', {}).items():
    print(f"    {port}: {info.get('service','')} {info.get('version','')}")
if not s.get('services'):
    print("    (none yet)")
print()
print("  ── Hostnames ──")
for h in s.get('hostnames', []):
    print(f"    {h}")
if not s.get('hostnames'):
    print("    (none)")
print()
print("  ── Credentials ──")
for c in s.get('credentials', []):
    if isinstance(c, dict):
        print(f"    🔑 {c.get('user','?')}:{c.get('pass','?')} ({c.get('source','')})")
    else:
        print(f"    🔑 {c}")
if not s.get('credentials'):
    print("    (none)")
print()
print("  ── Shells ──")
for sh in s.get('shells', []):
    print(f"    💀 {sh}")
if not s.get('shells'):
    print("    (none)")
print()
print("  ── Flags ──")
for k, v in s.get('flags', {}).items():
    print(f"    🏴 {k}: {v}")
if not s.get('flags'):
    print("    (none)")
print()
print("  ── Findings ──")
for f_item in s.get('findings', []):
    print(f"    📝 {f_item}")
if not s.get('findings'):
    print("    (none)")
print()
print("  ── Errors ──")
for e in s.get('errors', []):
    if isinstance(e, dict):
        print(f"    ❌ [{e.get('phase','')}/{e.get('sub','')}] {e.get('error','')[:100]}")
    else:
        print(f"    ❌ {e}")
if not s.get('errors'):
    print("    (none)")
print()
print("  ── Phase History (last 10) ──")
for h in s.get('phase_history', [])[-10:]:
    print(f"    {h.get('phase','')}/{h.get('sub','')} → {h.get('result','')[:80]}")
if not s.get('phase_history'):
    print("    (none)")
