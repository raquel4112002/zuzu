#!/usr/bin/env python3
"""
report.py — Aggregate benchmark result rows into a model x box matrix.

Reads every benchmark/results/*.json (written by bench.sh score) and emits
either a Markdown report (--md, default) or a flat CSV (--csv) suitable for
importing into the thesis / a notebook.

Reproducibility note: each row carries the nest_commit it ran under, so a
matrix can be filtered to a single Nest version for a fair comparison.
"""
import csv
import glob
import io
import json
import os
import sys

WS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(WS, "benchmark", "results")

OUTCOME_RANK = {
    "solved_full": 4,
    "partial_user": 3,
    "blocker_documented": 2,
    "awaiting_human": 1,
    "failed": 0,
}
OUTCOME_CELL = {
    "solved_full": "✅",
    "partial_user": "🟡",
    "blocker_documented": "📋",
    "awaiting_human": "⏸️",
    "failed": "❌",
}

FIELDS = ["box", "difficulty", "os", "model", "outcome", "user_flag",
          "root_flag", "time_to_user_s", "time_to_root_s", "wall_clock_s",
          "hypotheses_total", "confirmed", "falsified", "inconclusive",
          "open", "max_chain_depth", "requests", "tokens_billed",
          "rate_per_1m", "cost_usd", "context_tokens_in", "context_tokens_out",
          "nest_commit", "started_at", "ended_at", "notes"]


def load_rows():
    rows = []
    for p in sorted(glob.glob(os.path.join(RESULTS, "*.json"))):
        try:
            rows.append(json.load(open(p)))
        except Exception:
            continue
    return rows


def best_per_cell(rows):
    """Keep the best outcome per (box, model) pair."""
    best = {}
    for r in rows:
        key = (r.get("box"), r.get("model"))
        if key not in best or OUTCOME_RANK.get(r["outcome"], 0) > OUTCOME_RANK.get(best[key]["outcome"], 0):
            best[key] = r
    return best


def render_md(rows):
    if not rows:
        return "# Nest benchmark results\n\n_No results recorded yet. Run `bench.sh score <box>`._\n"
    best = best_per_cell(rows)
    boxes = sorted({r.get("box") for r in rows}, key=lambda b: (
        {"easy": 0, "medium": 1, "hard": 2, "insane": 3}.get(
            next((x.get("difficulty") for x in rows if x.get("box") == b), ""), 9), b or ""))
    models = sorted({r.get("model") for r in rows})

    out = io.StringIO()
    out.write("# Nest benchmark results\n\n")
    out.write("Best outcome per (box × model). "
              "✅ solved · 🟡 user-only · 📋 blocker · ⏸️ awaiting-human · ❌ failed\n\n")

    # Matrix
    out.write("| Box | Diff | OS | " + " | ".join(m or "?" for m in models) + " |\n")
    out.write("|-----|------|----|" + "|".join("----" for _ in models) + "|\n")
    for b in boxes:
        meta = next((r for r in rows if r.get("box") == b), {})
        line = f"| {b} | {meta.get('difficulty') or '?'} | {meta.get('os') or '?'} | "
        cells = []
        for m in models:
            r = best.get((b, m))
            cells.append(OUTCOME_CELL.get(r["outcome"], "·") if r else "·")
        out.write(line + " | ".join(cells) + " |\n")

    # Per-model solve rate
    out.write("\n## Solve rate by model\n\n")
    out.write("| Model | Runs | Solved | User+ | Any progress | Median hyps | Median chain |\n")
    out.write("|-------|------|--------|-------|--------------|-------------|-------------|\n")
    for m in models:
        mrows = [r for r in rows if r.get("model") == m]
        n = len(mrows)
        solved = sum(1 for r in mrows if r["outcome"] == "solved_full")
        useru = sum(1 for r in mrows if r["user_flag"])
        prog = sum(1 for r in mrows if OUTCOME_RANK.get(r["outcome"], 0) >= 2)
        hyps = sorted(r["hypotheses_total"] for r in mrows)
        chains = sorted(r["max_chain_depth"] for r in mrows)
        med = lambda xs: xs[len(xs) // 2] if xs else 0
        out.write(f"| {m or '?'} | {n} | {solved} | {useru} | {prog} | {med(hyps)} | {med(chains)} |\n")

    out.write(f"\n_{len(rows)} total runs across {len(boxes)} boxes, {len(models)} models._\n")
    return out.getvalue()


def render_csv(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


if __name__ == "__main__":
    fmt = sys.argv[1] if len(sys.argv) > 1 else "--md"
    rows = load_rows()
    print(render_csv(rows) if fmt == "--csv" else render_md(rows), end="")
