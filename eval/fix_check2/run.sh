#!/bin/sh
# Second decoder fix (7b, Nat.pred_eq_self_iff): acceptance and the rerun of every goal
# that reached SAT. Run from the repository root.
D=eval/fix_check2
{
  echo "=== build $(date '+%F %T')"
  lake build SolveBySat eval_corpus eval_run Test.EvalNamed LeanTests || exit 1
  echo "=== run_all $(date '+%F %T')"
  Test/run_all.sh > $D/run_all.log 2>&1; echo "run_all exit $?"
  echo "=== named $(date '+%F %T')"
  rm -rf $D/named; python3 Test/eval_driver.py run eval/specs_named.jsonl $D/named > $D/named_driver.log 2>&1; echo "named exit $?"
  echo "=== sat $(date '+%F %T')"
  rm -rf $D/sat; python3 Test/eval_driver.py run $D/specs.jsonl $D/sat > $D/sat_driver.log 2>&1; echo "sat exit $?"
  echo "=== done $(date '+%F %T')"
} > $D/run.log 2>&1
