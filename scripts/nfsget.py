#!/usr/bin/env python3
"""Minimal userspace NFSv3 client: list + download files from an export."""
import sys, logging
from pyNfsClient import Portmap, Mount, NFSv3, AUTH_SYS

logging.disable(logging.CRITICAL)

host = sys.argv[1]
export = sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else "ls"
target = sys.argv[4] if len(sys.argv) > 4 else ""

auth = {"flavor": AUTH_SYS, "machine_name": "kali", "uid": 0, "gid": 0, "aux_gid": [0]}

pm = Portmap(host); pm.connect()
mnt_port = pm.getport(100005, 3, 6)
nfs_port = pm.getport(100003, 3, 6)

mnt = Mount(host, mnt_port, 10000, auth); mnt.connect()
res = mnt.mnt(export)
fh = res["mountinfo"]["fhandle"]

nfs = NFSv3(host, nfs_port, 10000, auth); nfs.connect()

def flatten(entries):
    out = []
    for e in entries:
        nxt = e.get("nextentry")
        e = {k: v for k, v in e.items() if k != "nextentry"}
        out.append(e)
        if nxt:
            out.extend(flatten(nxt))
    return out

def readdir(fh):
    out = []
    cookie = 0
    while True:
        r = nfs.readdir(fh, cookie=cookie, count=8192)
        if r["status"] != 0:
            break
        ents = flatten(r["resok"]["reply"]["entries"])
        out.extend(ents)
        if r["resok"]["reply"]["eof"]:
            break
        cookie = out[-1]["cookie"]
    return out

if mode == "ls":
    for e in readdir(fh):
        name = e["name"].decode(errors="replace")
        print(f"{e['fileid']:>8}  {name}")
elif mode == "get":
    # walk path
    parts = [p for p in target.split("/") if p]
    cur = fh
    for p in parts[:-1]:
        lk = nfs.lookup(cur, p)
        if lk["status"] != 0:
            print("[!] lookup failed for", p, lk); sys.exit(1)
        cur = lk["resok"]["object"]["data"]
    last = parts[-1]
    lk = nfs.lookup(cur, last)
    if lk["status"] != 0:
        print("[!] lookup failed:", lk); sys.exit(1)
    obj = lk["resok"]["object"]["data"]
    attr = nfs.getattr(obj)["attributes"]
    size = attr["size"]
    data = b""
    off = 0
    while off < size:
        r = nfs.read(obj, offset=off, chunk_count=1024*512)
        if r.get("status") != 0:
            print("[!] read failed", r); break
        chunk = r.get("data") or r.get("resok", {}).get("data")
        if not chunk: break
        data += chunk
        off += len(chunk)
    out = sys.argv[5] if len(sys.argv) > 5 else last
    open(out, "wb").write(data)
    print(f"[+] wrote {out} ({len(data)} bytes)")
