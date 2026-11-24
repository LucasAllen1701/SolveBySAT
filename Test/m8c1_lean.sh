#!/usr/bin/env bash
# 8c-1 (M8_PLAN 3.1, 3.4.5, 4.4): the Lean suite in three settings (both milestone 8 flags off,
# R1 on, R1 and R2 on; every other option at its default), each with the model check on
# (solve_by_sat.checkBounds: every node of every decoded proof satisfies R1's bounds). Every file
# must pass in every setting. The proofs' node counts per setting are compared and any difference
# is printed (a different CNF may give a different proof within the same N; not a failure).
set -uo pipefail
cd "$(dirname "$0")/.."
lake build SolveBySat Test.EvalNamed >/dev/null || exit 1
files="Test/M2.lean Test/M3.lean Test/M4Lean.lean Test/M5Lean.lean Test/M7Lean.lean Test/M8Probe.lean Test/M8C1Lean.lean"
tmp=$(mktemp -d "$PWD/eval/.m8c1lean.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
status=0
for s in off:false:false r1:true:false r1r2:true:true; do
  IFS=: read name b e <<< "$s"
  for f in $files; do
    if lake env lean -Dsolve_by_sat.nodeBounds=$b -Dsolve_by_sat.exclusivePairs=$e \
        -Dsolve_by_sat.checkBounds=true "$f" > "$tmp/$name.$(basename $f).log" 2>&1; then
      echo "PASS $name $f"
    else
      echo "FAIL $name $f"; grep -m5 "error" "$tmp/$name.$(basename $f).log"; status=1
    fi
    grep -o "proof with [0-9]* nodes" "$tmp/$name.$(basename $f).log" > "$tmp/$name.$(basename $f).nodes" || true
  done
done
for f in $files; do
  b=$(basename $f)
  for name in r1 r1r2; do
    if ! cmp -s "$tmp/off.$b.nodes" "$tmp/$name.$b.nodes"; then
      echo "note: $b, $name: proof node counts differ from 'off':"; diff "$tmp/off.$b.nodes" "$tmp/$name.$b.nodes" | head -5
    fi
  done
  echo "$b: $(wc -l < "$tmp/off.$b.nodes") decoded proofs per setting"
done
[ $status -eq 0 ] && echo "PASS Lean suite in three settings, with the model check" || echo "FAIL Lean suite in three settings"
exit $status
