#!/usr/bin/env python3
"""cost.py — Real billed-token cost from the OpenClaw transcript.

Why this exists: OpenClaw's session_status shows PEAK CONTEXT, not cumulative
billed usage, and the provider bills cached input too (cacheRead). This sums
the real per-turn usage the agent accounting recorded (input + cacheRead +
cacheWrite + output) across every inference turn of a session, decompressing
zstd events, and prices it with benchmark/prices.json.

Ground truth for a thesis is still the provider invoice (ollama.com/settings);
this reconstructs it from OpenClaw's own accounting and matches it closely when
the cached-input price is correct (that term dominates long agentic runs).

Usage:
  python3 benchmark/cost.py                 # all sessions, auto-detect model
  python3 benchmark/cost.py --session <id>  # one session
  python3 benchmark/cost.py --model glm-5.3-flash --session <id>   # force model
  python3 benchmark/cost.py --json          # machine-readable
"""
import argparse, collections, io, json, os, sqlite3, sys

AGENT_DB = os.path.expanduser(
    "~/.openclaw/agents/main-zuzu/agent/openclaw-agent.sqlite")
PRICES = os.path.join(os.path.dirname(__file__), "prices.json")

try:
    import zstandard
    _dctx = zstandard.ZstdDecompressor()
    def _decomp(b):
        try:
            return _dctx.decompress(b)
        except Exception:
            with _dctx.stream_reader(io.BytesIO(b)) as r:
                return r.read()
except Exception:
    _decomp = None


def load_prices(path=PRICES):
    return json.load(open(path))["models"]


def _walk(obj, usages, models):
    """Collect every usage object and every model string in the event tree."""
    if isinstance(obj, dict):
        u = obj.get("usage")
        if isinstance(u, dict) and ("input" in u or "output" in u):
            usages.append(u)
        m = obj.get("model")
        if isinstance(m, str) and m:
            models.append(m)
        for k, v in obj.items():
            if k != "usage":
                _walk(v, usages, models)
    elif isinstance(obj, list):
        for v in obj:
            _walk(v, usages, models)


def session_usage(con, session_id):
    rows = con.execute(
        "SELECT event_json, event_zstd FROM transcript_events WHERE session_id=? ORDER BY seq",
        (session_id,)).fetchall()
    agg = dict(reqs=0, input=0, cacheRead=0, cacheWrite=0, output=0)
    models = []
    for ej, ez in rows:
        if ej is None:
            if _decomp is None or ez is None:
                continue
            ej = _decomp(ez).decode("utf-8", "replace")
        try:
            ev = json.loads(ej)
        except Exception:
            continue
        us = []
        _walk(ev, us, models)
        for u in us:
            agg["reqs"] += 1
            agg["input"] += u.get("input", 0) or 0
            agg["cacheRead"] += u.get("cacheRead", 0) or 0
            agg["cacheWrite"] += u.get("cacheWrite", 0) or 0
            agg["output"] += u.get("output", 0) or 0
    model = collections.Counter(models).most_common(1)
    agg["model"] = model[0][0] if model else None
    return agg


def cost_of(agg, prices, model=None):
    model = model or agg.get("model")
    p = prices.get(model)
    if not p:
        return None, model
    c = (agg["input"] * p["input"]
         + agg["cacheRead"] * p["cached"]
         + agg["cacheWrite"] * p["input"]   # no separate write price -> input
         + agg["output"] * p["output"]) / 1_000_000.0
    return round(c, 4), model


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--session", help="session_id (default: all)")
    ap.add_argument("--model", help="force model (else auto-detect)")
    ap.add_argument("--db", default=AGENT_DB)
    ap.add_argument("--json", action="store_true", dest="as_json")
    args = ap.parse_args()

    prices = load_prices()
    con = sqlite3.connect(args.db)
    if args.session:
        sids = [args.session]
    else:
        sids = [r[0] for r in con.execute(
            "SELECT session_id, count(*) c FROM transcript_events "
            "GROUP BY session_id ORDER BY c DESC").fetchall()]

    out = []
    for sid in sids:
        agg = session_usage(con, sid)
        if agg["reqs"] == 0:
            continue
        cost, model = cost_of(agg, prices, args.model)
        out.append(dict(session=sid, model=model, reqs=agg["reqs"],
                        input=agg["input"], cacheRead=agg["cacheRead"],
                        cacheWrite=agg["cacheWrite"], output=agg["output"],
                        cost_usd=cost))

    if args.as_json:
        print(json.dumps(out, indent=2))
        return
    print(f"{'session':<38}{'model':<16}{'reqs':>5}{'input':>11}"
          f"{'cacheRead':>12}{'output':>10}{'cost$':>9}")
    print("-" * 101)
    tot = 0.0
    for r in out:
        cs = f"{r['cost_usd']:.3f}" if r['cost_usd'] is not None else "NO-PRICE"
        if r['cost_usd']:
            tot += r['cost_usd']
        print(f"{r['session']:<38}{(r['model'] or '?'):<16}{r['reqs']:>5}"
              f"{r['input']:>11,}{r['cacheRead']:>12,}{r['output']:>10,}{cs:>9}")
    print("-" * 101)
    print(f"{'TOTAL':<77}{tot:>9.3f}")


if __name__ == "__main__":
    main()
