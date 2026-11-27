#!/usr/bin/env bash
# Build and run the acceptance tests of every milestone implemented so far.
set -euo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp)
if ! lake build SolveBySat test_m0 test_m1 test_m4 test_m5 bench test_countonly test_m8diag eval_run m8b_dimacs73 Test.EvalNamed test_m9diff >"$log" 2>&1; then
  grep -v '^trace' "$log"; rm -f "$log"; exit 1
fi
grep -v '^trace' "$log" | tail -1; rm -f "$log"
status=0
for t in test_m0 test_m1 test_m4 test_m5 test_countonly test_m8diag; do
  echo "== $t"
  ".lake/build/bin/$t" || status=1
done
for f in Test/M2.lean Test/M3.lean Test/M4Lean.lean Test/M5Lean.lean Test/M7Lean.lean Test/M8Probe.lean Test/M8C1Lean.lean Test/M9Lean.lean; do
  echo "== $f"
  lake env lean "$f" || status=1
done
# 8c-1 (M8_PLAN 3.1, 3.4.5, 3.5, 4.4): the differentials with the milestone 8 flags set (the runs above
# hold the mutation checks), the off-switch, and the Lean suite in three settings with the model check
for cfg in m8off r1 r1r2; do
  echo "== test_m1, test_m5: $cfg"
  .lake/build/bin/test_m1 1500 4 "$cfg" | grep -E "^(FAIL|MISMATCH)|differential|^M1:" || status=1
  .lake/build/bin/test_m5 3000 4 "$cfg" | grep -E "^(FAIL|MISMATCH)|differential|^M5:" || status=1
done
# 8d (M8_PLAN 4.6): the exactness comparison flags a hand-made disagreement in each stop case
echo "== exactness comparison"
# (pipefail: a failing self-test fails the pipeline)
.lake/build/bin/eval_run exactness-selftest | grep -E "^FAIL|^exactness" || status=1
python3 Test/eval_driver.py exactness-selftest | grep -E "^FAIL|^driver exactness" || status=1
# (9a-1, M9_PLAN 2.2: the same off-switch holds with every milestone 9 option off, their default)
echo "== off-switch (milestone 8 flags and milestone 9 options off)"
Test/m8c1_offswitch.sh || status=1
echo "== Lean suite, three settings"
Test/m8c1_lean.sh || status=1
# 9a-1 (M9_PLAN 2.2): the Lean suite with iffEq off and on, with the model check
echo "== Lean suite, iffEq off and on"
Test/m9a1_lean.sh || status=1
# 9a-2 (M9_PLAN 3.2): the differentials with rules made by the tactic's generation code (and the
# selection mutation), and the Lean suite with rewrite off, on, and with selection dropped
echo "== test_m9diff"
.lake/build/bin/test_m9diff 600 4 || status=1
echo "== Lean suite, rewrite off, on, and selection dropped"
M9A2_KEEP=1 Test/m9a2_lean.sh > eval/.m9a2_lean_last.log 2>&1; r=$?
cat eval/.m9a2_lean_last.log
d=$(grep -o "logs kept in .*" eval/.m9a2_lean_last.log | sed 's/logs kept in //')
python3 Test/m9a2_classify.py "$d" || r=1
rm -rf "$d" eval/.m9a2_lean_last.log
[ $r -eq 0 ] || status=1
exit $status
