#!/usr/bin/env python3
"""
log_row.py — Append ONE sanitized result row to benchmark/RESULTS-LOG.md.

This is the human-readable, thesis-facing log every test fills in at the end.
It contains NO IPs and NO flag values — only the metrics you graph and cite:
box, difficulty, os, model, outcome, per-flag timing, wall clock, hypothesis
stats, chain depth, tokens, cost. Safe to commit.

Usage:
    python3 benchmark/log_row.py <result-row.json>

The machine-readable source of truth stays in benchmark/results/*.json (and
benchmark/results.csv via report.py). This file is for eyeballing + quick
charts; parse RESULTS-LOG.md or results.csv for plots.
"""
import json
import os
import sys
from datetime import datetime, timezone

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(WS, "benchmark", "RESULTS-LOG.md")

HEADER = """# Nest benchmark results log

Append-only. One row per scored engagement. No IPs, no flag values — safe to
commit and cite. Machine-readable source: `benchmark/results/*.json` and
`benchmark/results.csv` (regenerate with `bench.sh report --csv`).

Columns: **t→user / t→root / wall** are H:MM (blank if not reached).
**hyps** = total(✓confirmed/✗falsified). **chain** = max kill-chain depth.
**req** = provider requests. **billed** = cumulative billed tokens (cost/rate).

| Date (UTC) | Box | Diff | OS | Model | Outcome | user | root | t→user | t→root | wall | hyps | chain | req | billed | cost($) | commit | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
"""


def hm(s):
    if s is None:
        return ""
    s = int(s)
    h, rem = divmod(s, 3600)
    m = rem // 60
    return f"{h}:{m:02d}"


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 benchmark/log_row.py <result-row.json>", file=sys.stderr)
        sys.exit(2)
    r = json.load(open(sys.argv[1]))

    if not os.path.exists(LOG):
        with open(LOG, "w") as f:
            f.write(HEADER)

    date = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    billed = r.get("tokens_billed")
    reqs = r.get("requests")
    cost = r.get("cost_usd")

    def kfmt(n):
        if not isinstance(n, (int, float)):
            return ""
        return "%.2fM" % (n / 1_000_000) if n >= 1_000_000 else "%.0fk" % (n / 1000) if n >= 1000 else str(n)

    notes = (r.get("notes") or "").replace("|", "/").replace("\n", " ")[:80]
    row = "| {date} | {box} | {diff} | {os} | {model} | {out} | {u} | {rt} | {tu} | {tr} | {wall} | {ht}({c}✓/{f}✗) | {chain} | {req} | {billed} | {cost} | {commit} | {notes} |\n".format(
        date=date,
        box=r.get("box", "?"),
        diff=r.get("difficulty") or "?",
        os=r.get("os") or "?",
        model=r.get("model") or "?",
        out=r.get("outcome", "?"),
        u="✓" if r.get("user_flag") else "",
        rt="✓" if r.get("root_flag") else "",
        tu=hm(r.get("time_to_user_s")),
        tr=hm(r.get("time_to_root_s")),
        wall=hm(r.get("wall_clock_s")),
        ht=r.get("hypotheses_total", 0),
        c=r.get("confirmed", 0),
        f=r.get("falsified", 0),
        chain=r.get("max_chain_depth", 0),
        req=reqs if reqs is not None else "",
        billed=kfmt(billed),
        cost=("%.2f" % cost) if isinstance(cost, (int, float)) else "",
        commit=r.get("nest_commit") or "?",
        notes=notes,
    )
    with open(LOG, "a") as f:
        f.write(row)
    print(f"[+] Logged to benchmark/RESULTS-LOG.md: {r.get('box')} / {r.get('model')} / {r.get('outcome')}")


if __name__ == "__main__":
    main()
