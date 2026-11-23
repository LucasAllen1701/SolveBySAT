#!/bin/bash
# The 10.7 rerun (EVAL_PLAN 10.7 decision 6): the goals whose compiled forest changed with the
# type-template fix, plus 100 spot-check goals, SAT phase only (specs have baselines: false).
# Start it detached so it outlives the shell:
#   setsid nohup Test/eval_rerun.sh > /dev/null 2>&1 &
# Resume by starting it again. Results under eval/rerun/; log eval/rerun/driver.log.
# Same driver, limits and P = 1 as the full run (Test/eval_full.sh).
set -u
cd "$(dirname "$0")/.."
OUT=eval/rerun
SPECS=eval/specs_rerun.jsonl
export EVAL_SPECS=$SPECS
mkdir -p $OUT
echo "=== driver start $(date '+%F %T')" >> $OUT/driver.log
python3 Test/eval_driver.py run $SPECS $OUT \
  --after-shard 'Test/eval_publish.sh "$1" "eval/rerun: shard done"' >> $OUT/driver.log 2>&1
RC=$?
echo "=== driver exit $RC $(date '+%F %T')" >> $OUT/driver.log
python3 Test/eval_status.py $OUT --specs $SPECS --rc $RC
if [ $RC -ne 0 ]; then
  {
    echo "- **Rerun stopped (recorded automatically by \`Test/eval_rerun.sh\`, $(date '+%F %T')).**"
    echo "  Driver exit $RC: $(grep -o 'Driver ended: [^*]*' $OUT/STATUS.md)."
    echo "  Last driver output:"
    echo '  ```'
    tail -5 $OUT/driver.log | sed 's/^/  /'
    echo '  ```'
    echo "  $(grep -E '^- (Goals done|Crashes)' $OUT/STATUS.md | tr '\n' ' ')"
  } >> NOTES.md
  Test/eval_publish.sh $OUT "eval/rerun: run stopped (exit $RC)" --rc $RC --with-notes
else
  {
    echo "- **Rerun finished (recorded automatically by \`Test/eval_rerun.sh\`, $(date '+%F %T')); tables to be checked.**"
    echo
    python3 Test/eval_status.py $OUT --specs $SPECS --notes | sed 's/^/  /'
    echo
  } >> NOTES.md
  Test/eval_publish.sh $OUT "eval/rerun: run finished" --rc 0 --with-notes
fi
