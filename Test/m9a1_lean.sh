#!/usr/bin/env bash
# 9a-1 (M9_PLAN 2.2): the Lean suite with `iffEq` off and on (every other option at its default, so
# node bounds and exclusive pairs on), each with the bounds model check (solve_by_sat.checkBounds).
# Every file must pass in both settings. The number of decoded proofs per file (the "proof with K
# nodes" lines of `verbose`) must be the same in both, except in M9Lean.lean; any difference in
# their node counts is printed (adding clauses cannot remove a proof, but may give another one).
set -uo pipefail
cd "$(dirname "$0")/.."
lake build SolveBySat Test.EvalNamed >/dev/null || exit 1
files="Test/M2.lean Test/M3.lean Test/M4Lean.lean Test/M5Lean.lean Test/M7Lean.lean Test/M8Probe.lean Test/M8C1Lean.lean Test/M9Lean.lean"
tmp=$(mktemp -d "$PWD/eval/.m9a1lean.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
status=0
for s in off:false on:true; do
  IFS=: read name v <<< "$s"
  for f in $files; do
    if lake env lean -Dsolve_by_sat.iffEq=$v -Dsolve_by_sat.checkBounds=true "$f" > "$tmp/$name.$(basename $f).log" 2>&1; then
      echo "PASS iffEq $name $f"
    else
      echo "FAIL iffEq $name $f"; grep -m5 "error" "$tmp/$name.$(basename $f).log"; status=1
    fi
    grep -o "proof with [0-9]* nodes" "$tmp/$name.$(basename $f).log" > "$tmp/$name.$(basename $f).nodes" || true
  done
done
for f in $files; do
  b=$(basename $f)
  off=$(wc -l < "$tmp/off.$b.nodes"); on=$(wc -l < "$tmp/on.$b.nodes")
  echo "$b: $off decoded proofs with iffEq off, $on with iffEq on"
  if [ "$off" != "$on" ] && [ "$b" != "M9Lean.lean" ]; then
    echo "FAIL $b: the number of decoded proofs differs"; status=1
  fi
  if ! cmp -s "$tmp/off.$b.nodes" "$tmp/on.$b.nodes"; then
    echo "note: $b: proof node counts differ between iffEq off and on:"; diff "$tmp/off.$b.nodes" "$tmp/on.$b.nodes" | head -5
  fi
done
[ $status -eq 0 ] && echo "PASS Lean suite with iffEq off and on, with the model check" || echo "FAIL Lean suite with iffEq off and on"
exit $status
