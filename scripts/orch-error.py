#!/usr/bin/env python3
"""Orchestrator error handler — suggests fixes and alternatives."""
import json, sys, os

state_file = sys.argv[1] if len(sys.argv) > 1 else 'state/orchestrator.json'
error = sys.argv[2] if len(sys.argv) > 2 else ''

with open(state_file) as f:
    s = json.load(f)

phase = s['phase']
sub = s['sub_phase']
attempt = s.get('attempt', 0) + 1
s['attempt'] = attempt
s['errors'].append({"phase": phase, "sub": sub, "error": error[:300], "attempt": attempt})

print("╔══════════════════════════════════════════════════════════════╗")
print("║  ⚠️  ERROR HANDLER                                          ║")
print("╚══════════════════════════════════════════════════════════════╝")
print()
print(f"  Error: {error[:200]}")
print(f"  Attempt: {attempt}/3")
print()

if attempt >= 3:
    print("  ❌ MAX RETRIES REACHED")
    print("  Options:")
    print(f"    1. Skip this step: bash scripts/orchestrator.sh report 'skipped - {sub}'")
    print("    2. Ask human for help")
    print("    3. Try a completely different approach")
else:
    el = error.lower()
    
    if 'permission denied' in el or 'sudo' in el:
        print("  FIX: Permission issue. Try:")
        print("    - Use current user's privileges instead")
        print("    - Look for writable alternatives (/tmp, /dev/shm)")
        print("    - Use Host header instead of /etc/hosts for web")
        print("    - Check if there's another way to accomplish the same thing")
        
    elif 'not found' in el or 'command not found' in el:
        print("  FIX: Tool not installed. Try:")
        print("    - Install it: apt-get install -y TOOLNAME")
        print("    - Use alternative tool (see knowledge-base/tools/kali-essentials.md)")
        
    elif 'timeout' in el or 'timed out' in el:
        print("  FIX: Connection timed out. Try:")
        print("    - Is the target alive? ping TARGET")
        print("    - Use -Pn flag (skip ping)")
        print("    - Slow down: reduce --min-rate")
        
    elif 'filtered' in el or 'blocked' in el or 'waf' in el:
        print("  FIX: Payload blocked. Try:")
        print("    - Different encoding (URL encode, base64)")
        print("    - Different payload syntax (| instead of ;)")
        print("    - Read: knowledge-base/mitre-attack/techniques/defense-evasion-deep.md")
        
    elif 'refused' in el:
        print("  FIX: Connection refused. Try:")
        print("    - Different port?")
        print("    - Service may have crashed — wait and retry")
        print("    - Check if you need authentication first")
        
    elif 'exploit' in el or 'shell' in el or 'payload' in el:
        print("  FIX: Exploit failed. Try:")
        print("    - DIFFERENT payload (not the same one!)")
        print("    - Different reverse shell method")
        print("    - Read: knowledge-base/checklists/reverse-shells.md")
        print("    - Try a completely different vulnerability")
        
    elif 'compile' in el or 'gcc' in el or 'make' in el:
        print("  FIX: Compilation failed. Try:")
        print("    - Compile on YOUR machine, then transfer to target")
        print("    - python3 -m http.server 8080 → wget on target")
        print("    - scp file USER@TARGET:/tmp/")
        
    else:
        print("  GENERAL FIX:")
        print("    - Read the error carefully — it usually tells you what's wrong")
        print("    - Check: knowledge-base/troubleshooting.md")
        print("    - Check: knowledge-base/error-recovery.md")
        print("    - Try an alternative approach")
    
    print()
    print("  Then retry: bash scripts/orchestrator.sh think")

with open(state_file, 'w') as f:
    json.dump(s, f, indent=2)
