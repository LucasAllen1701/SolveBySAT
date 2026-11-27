#!/usr/bin/env bash
# 9a-2 (M9_PLAN 3.2, amendment 6.1 clarification 4): the Lean suite with `rewrite` (and `iffEq`) on,
# and with selection dropped, each with the bounds model check (solve_by_sat.checkBounds); every
# other option at its default, so node bounds and exclusive pairs on.
#   off      rewrite and iffEq off (the reference: every file must pass)
#   on       rewrite and iffEq on
#   liberal  rewrite and iffEq on, selection dropped (solve_by_sat.rewriteLiberal, testing only)
# A file that fails in `on` or `liberal` is listed with its failing guards: a lost proof (a test
# that expects a proof fails) is a FAIL; an expected failure that becomes a proof, or a changed
# message, is recorded (listed), not counted as a failure (6.1, clarification 4). The decoded proofs
# per file are counted in each setting; fewer in `on` than in `off`, or in `liberal` than in `on`,
# is a FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
lake build SolveBySat Test.EvalNamed >/dev/null || exit 1
files="Test/M2.lean Test/M3.lean Test/M4Lean.lean Test/M5Lean.lean Test/M7Lean.lean Test/M8Probe.lean Test/M8C1Lean.lean Test/M9Lean.lean"
keep=${M9A2_KEEP:-}
tmp=$(mktemp -d "$PWD/eval/.m9a2lean.XXXXXX")
[ -z "$keep" ] && trap 'rm -rf "$tmp"' EXIT
status=0
declare -A flags=(
  [off]="-Dsolve_by_sat.rewrite=false -Dsolve_by_sat.iffEq=false"
  [on]="-Dsolve_by_sat.rewrite=true -Dsolve_by_sat.iffEq=true"
  [liberal]="-Dsolve_by_sat.rewrite=true -Dsolve_by_sat.iffEq=true -Dsolve_by_sat.rewriteLiberal=true")
for s in off on liberal; do
  for f in $files; do
    b=$(basename $f)
    log="$tmp/$s.$b.log"
    if lake env lean ${flags[$s]} -Dsolve_by_sat.checkBounds=true "$f" > "$log" 2>&1; then
      echo "PASS $s $f"
    else
      if [ "$s" = off ]; then
        echo "FAIL $s $f"; grep -m5 "error" "$log"; status=1
      else
        # every failing guard or tactic, with its first line
        echo "DIFFERS $s $f:"
        grep -E "^$f:[0-9]+:[0-9]+: error" "$log" | sed 's/^/    /' | cut -c1-220
        # a test that expects a proof and fails is a lost proof: an error at a tactic line that no
        # #guard_msgs covers. (A covered one shows up as a guard mismatch, listed above.)
        if grep -qE "decoder failed|internal|violates the node bounds" "$log"; then
          echo "FAIL $s $f: a decoder, internal or model-check error"; status=1
        fi
      fi
    fi
    grep -o "proof with [0-9]* nodes" "$log" > "$tmp/$s.$b.nodes" || true
  done
done
for f in $files; do
  b=$(basename $f)
  o=$(wc -l < "$tmp/off.$b.nodes"); n=$(wc -l < "$tmp/on.$b.nodes"); l=$(wc -l < "$tmp/liberal.$b.nodes")
  echo "$b: decoded proofs (verbose lines): off $o, on $n, liberal $l"
  if [ "$n" -lt "$o" ]; then echo "FAIL $b: fewer decoded proofs with rewrite on"; status=1; fi
  if [ "$l" -lt "$n" ]; then echo "FAIL $b: fewer decoded proofs with selection dropped"; status=1; fi
done
[ -n "$keep" ] && echo "logs kept in $tmp"
[ $status -eq 0 ] && echo "PASS Lean suite with rewrite off, on, and selection dropped, with the model check (differences listed)" \
  || echo "FAIL Lean suite with rewrite"
exit $status
