#!/usr/bin/env python3
import sys, socket
from pyNfsClient import Portmap, Mount, NFSv3

host = sys.argv[1]
path = sys.argv[2]

# Portmap discovery
pm = Portmap(host)
print("[*] portmap dump:")
for p in pm.dump():
    print("   ", p)

# Mount
mnt = Mount(host)
print(f"[*] mounting {path} ...")
try:
    res = mnt.mount(path)
    print("[*] mount returned:", res)
except Exception as e:
    print("[!] mount err:", e)
    sys.exit(1)

# Get mount port
try:
    mp = pm.getport(100005, 3, "tcp")
    print("[*] mountd tcp port:", mp)
except Exception as e:
    mp = 0

nfs_port = pm.getport(100003, 3, "tcp")
print("[*] nfs tcp port:", nfs_port)

nfs = NFSv3(host, nfs_port, path)
print("[*] READDIR:", path)
try:
    entries = nfs.readdir(path)
    for e in entries:
        print("   ", e)
except Exception as e:
    print("[!] readdir err:", repr(e))
