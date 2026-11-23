#!/bin/bash
# The 7b full run (EVAL_PLAN 10.5). Start it detached so it outlives the shell:
#   setsid nohup Test/eval_full.sh > /dev/null 2>&1 &
# Resume by starting it again. Results under eval/full/; log eval/full/driver.log.
set -u
cd "$(dirname "$0")/.."
OUT=eval/full
mkdir -p $OUT
echo "=== driver start $(date '+%F %T')" >> $OUT/driver.log
python3 Test/eval_driver.py run eval/specs_full.jsonl $OUT \
  --after-shard 'Test/eval_publish.sh "$1" "eval/full: shard done"' >> $OUT/driver.log 2>&1
RC=$?
echo "=== driver exit $RC $(date '+%F %T')" >> $OUT/driver.log
python3 Test/eval_status.py $OUT --rc $RC
if [ $RC -ne 0 ]; then
  {
    echo "- **Full run stopped (recorded automatically by \`Test/eval_full.sh\`, $(date '+%F %T')).**"
    echo "  Driver exit $RC: $(grep -o 'Driver ended: [^*]*' $OUT/STATUS.md)."
    echo "  Last driver output:"
    echo '  ```'
    tail -5 $OUT/driver.log | sed 's/^/  /'
    echo '  ```'
    echo "  $(grep -E '^- (Goals done|Crashes)' $OUT/STATUS.md | tr '\n' ' ')"
  } >> NOTES.md
  Test/eval_publish.sh $OUT "eval/full: run stopped (exit $RC)" --rc $RC --with-notes
else
  {
    echo "- **Full run finished (recorded automatically by \`Test/eval_full.sh\`, $(date '+%F %T')); tables to be checked.**"
    echo
    python3 Test/eval_status.py $OUT --notes | sed 's/^/  /'
    echo
  } >> NOTES.md
  Test/eval_publish.sh $OUT "eval/full: run finished" --rc 0 --with-notes
fi
