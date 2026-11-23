#!/usr/bin/env bash
# 7c, EVAL_PLAN 4.2 full run (owner-approved after the pilot): the 550 runs, then the
# decision 7 countOnly sizes. Resumable: start it again after a stop.
cd "$(dirname "$0")/.."
python3 Test/eval_driver.py run eval/specs_scaling.jsonl eval/scaling_full >> eval/scaling_full_driver.log 2>&1
rc=$?
echo "driver exit $rc $(date '+%F %T')" >> eval/scaling_full_driver.log
[ $rc -eq 0 ] || exit $rc
python3 Test/eval_sizes.py eval/specs_scaling.jsonl eval/scaling_full/sizes.jsonl >> eval/scaling_full_driver.log 2>&1
echo "sizes exit $? $(date '+%F %T')" >> eval/scaling_full_driver.log
