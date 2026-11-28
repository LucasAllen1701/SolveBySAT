#!/usr/bin/env bash
# 9a-3 (M9_PLAN 4.4): the driver's 9a-3 stop rules, by hand-made cases and end to end.
#   1. `eval_driver.py m9a3-selftest`: each stop rule flags its hand-made case, and the agreements pass.
#   2. One real run (a control goal of eval/m9a3/specs.jsonl that milestone 7 proved at N = 2, with the 9a-3
#      settings): with its true expectation the driver exits 0; with a hand-made expectation that says the earlier
#      proof is at N = 1 (so the proof at N = 2 is a lost proof) the driver must stop with exit 10.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
python3 Test/eval_driver.py m9a3-selftest || status=1
lake build eval_run >/dev/null || exit 1
key="main:B/UInt16.toFin_ofNatTruncate_of_le/0"
tmp=$(mktemp -d "$PWD/eval/.m9a3stop.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
grep -F "\"key\": \"$key\"" eval/m9a3/specs.jsonl > "$tmp/specs.jsonl"
grep -F "\"key\": \"$key\"" eval/m9a3/expect.jsonl > "$tmp/expect_true.jsonl"
sed 's/"earlier_N": 2/"earlier_N": 1/' "$tmp/expect_true.jsonl" > "$tmp/expect_lost.jsonl"
if [ "$(wc -l < "$tmp/specs.jsonl")" != 1 ] || ! grep -q '"earlier_N": 1' "$tmp/expect_lost.jsonl"; then
  echo "FAIL 9a-3 stop check: $key not found as expected in eval/m9a3/"; exit 1
fi
export SOLVE_BY_SAT_EVAL_FLAGS=nodeBounds,exclusivePairs,iffEq,rewrite
SOLVE_BY_SAT_EVAL_M9A3="$tmp/expect_true.jsonl" python3 Test/eval_driver.py run "$tmp/specs.jsonl" "$tmp/ok" > "$tmp/ok.log" 2>&1
rc=$?
out=$(python3 -c "import json,sys; r=json.loads(open(sys.argv[1]).readline()); print(r['outcome'], r.get('N'))" "$tmp/ok/results.jsonl" 2>/dev/null)
if [ $rc -eq 0 ] && [ "$out" = "proved 2" ]; then echo "PASS 9a-3 driver, true expectation: exit 0 ($out)"
else echo "FAIL 9a-3 driver, true expectation: exit $rc ($out)"; tail -5 "$tmp/ok.log"; status=1; fi
SOLVE_BY_SAT_EVAL_M9A3="$tmp/expect_lost.jsonl" python3 Test/eval_driver.py run "$tmp/specs.jsonl" "$tmp/lost" > "$tmp/lost.log" 2>&1
rc=$?
if [ $rc -eq 10 ] && grep -q "a lost proof" "$tmp/lost.log"; then echo "PASS 9a-3 driver, hand-made lost proof: exit 10: $(grep STOP "$tmp/lost.log")"
else echo "FAIL 9a-3 driver, hand-made lost proof: exit $rc"; tail -5 "$tmp/lost.log"; status=1; fi
[ $status -eq 0 ] && echo "PASS 9a-3 stop rules (M9_PLAN 4.4)" || echo "FAIL 9a-3 stop rules"
exit $status
