#!/usr/bin/env bash
# learn.sh — Capture TRANSFERABLE knowledge from an engagement, not a walkthrough.
#
# THE POINT: we don't want "how to do box X" (useless on the next, different box).
# We want the PRIOR it taught: "when you see signal X → pursue vuln class Y",
# the insight that cracked it, and the DEAD-ENDS that wasted time. That transfers.
#
# Every solved (or genuinely-blocked) box should leave one. stop-gate requires it;
# recon surfaces matching priors via `learn.sh lookup`.
#
# Subcommands:
#   save <box> --tags "a,b" --signal "X -> pursue Y" --worked "the insight"
#              [--deadends "what wasted time"] [--refs "CVE-..., technique"]
#              [--diff easy|medium|hard]
#        Writes learnings/<box>.md in the transferable-prior format + indexes it.
#   lookup <keyword...>   Grep the index for priors matching a tech/port/signal.
#   index                 Rebuild learnings/INDEX.md from all learnings/*.md tags.
#   template              Print the format (for writing one by hand).

set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
LDIR="$WS/learnings"; INDEX="$LDIR/INDEX.md"
mkdir -p "$LDIR"

slugify() { echo "$1" | tr '[:upper:] /' '[:lower:]--' | tr -cd 'a-z0-9._-'; }

rebuild_index() {
  { echo "# Learnings index — transferable priors (grep me during recon)"
    echo "# format: tags | signal→class | file"
    echo ""
    for f in "$LDIR"/*.md; do
      [[ "$(basename "$f")" == "INDEX.md" ]] && continue
      [[ -f "$f" ]] || continue
      local tags sig
      tags=$(grep -m1 -iE '^tags:' "$f" 2>/dev/null | sed 's/^[Tt]ags:[[:space:]]*//')
      sig=$(awk '/## Signal/{f=1;next} /^## /{f=0} f && NF{print;exit}' "$f" 2>/dev/null | sed 's/^- *//')
      printf -- "- [%s] %s — \`%s\`\n" "${tags:-untagged}" "${sig:-?}" "$(basename "$f")"
    done
  } > "$INDEX"
}

ACTION="${1:-}"; shift 2>/dev/null || true
case "$ACTION" in
  save)
    BOX="${1:-}"; shift 2>/dev/null || true
    [[ -n "$BOX" ]] || { echo "Usage: learn.sh save <box> --tags .. --signal .. --worked .. [--deadends ..] [--refs ..] [--diff ..]"; exit 2; }
    TAGS=""; SIGNAL=""; WORKED=""; DEADENDS=""; REFS=""; DIFF=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --tags) TAGS="$2"; shift 2;; --signal) SIGNAL="$2"; shift 2;;
      --worked) WORKED="$2"; shift 2;; --deadends) DEADENDS="$2"; shift 2;;
      --refs) REFS="$2"; shift 2;; --diff) DIFF="$2"; shift 2;;
      *) shift;; esac; done
    [[ -n "$SIGNAL" && -n "$WORKED" ]] || { echo "❌ --signal and --worked are required (the transferable core)."; exit 2; }
    f="$LDIR/$(slugify "$BOX").md"
    {
      echo "# Learning: $BOX${DIFF:+ ($DIFF)} — $(date +%Y-%m-%d)"
      echo "tags: $TAGS"
      echo ""
      echo "## Signal → vuln class (when you see X, pursue Y)"
      echo "- $SIGNAL"
      echo ""
      echo "## What worked (the insight, generalized — NOT box-specific steps)"
      echo "- $WORKED"
      echo ""
      echo "## Dead-ends (don't waste time here next time)"
      echo "- ${DEADENDS:-（none recorded）}"
      echo ""
      echo "## CVE / technique refs"
      echo "- ${REFS:-—}"
    } > "$f"
    rebuild_index
    echo "🧠 learning saved -> learnings/$(basename "$f")  (indexed)"
    ;;
  lookup)
    [[ $# -gt 0 ]] || { echo "Usage: learn.sh lookup <keyword...>"; exit 2; }
    [[ -f "$INDEX" ]] || rebuild_index
    pat=$(printf '%s|' "$@"); pat="${pat%|}"
    echo "── priors matching: $* ──"
    grep -iE "$pat" "$INDEX" 2>/dev/null | grep -v '^#' || echo "  (no matching prior yet)"
    ;;
  index) rebuild_index; echo "indexed $(ls "$LDIR"/*.md 2>/dev/null | grep -vc INDEX) learnings -> learnings/INDEX.md";;
  template)
    cat <<'T'
# Learning: <box> (<diff>) — <date>
tags: <tech,port,archetype,cve keywords for retrieval>

## Signal → vuln class (when you see X, pursue Y)
- <fingerprint/banner/version/behaviour> → <what class of vuln / where to go>

## What worked (the insight, generalized — NOT box-specific steps)
- <the pivot/realization that cracked it, phrased to transfer>

## Dead-ends (don't waste time here next time)
- <what looked promising but wasted time>

## CVE / technique refs
- <CVE-id / technique / skill name>
T
    ;;
  *)
    echo "learn.sh — capture transferable priors from an engagement"
    echo "Usage: learn.sh save <box> --signal .. --worked .. [--tags ..][--deadends ..][--refs ..][--diff ..]"
    echo "       learn.sh lookup <keyword...> | index | template"
    exit 2;;
esac
