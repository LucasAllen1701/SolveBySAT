#!/bin/bash
# 8a full run (M8_PLAN 2.4-2.6, amendment 4.1). Start it detached so it outlives the shell:
#   setsid nohup Test/m8a_full.sh > /dev/null 2>&1 &
# Resume by starting it again. Results and sizes under eval/m8a/full/; log eval/m8a/full/driver.log.
set -u
cd "$(dirname "$0")/.."
OUT=eval/m8a/full; SPECS=eval/m8a/specs.jsonl
mkdir -p $OUT
echo "=== start $(date '+%F %T')" >> $OUT/driver.log
python3 Test/m8a_run.py run $SPECS $OUT --after-shard "Test/m8a_publish.sh \"\$1\" $SPECS runs 'eval/m8a/full: shard done'" >> $OUT/driver.log 2>&1
RC=$?
echo "=== exit $RC $(date '+%F %T')" >> $OUT/driver.log
if [ $RC -ne 0 ]; then
  Test/m8a_publish.sh $OUT $SPECS "stopped (exit $RC)" "eval/m8a/full: run STOPPED (exit $RC)"
else
  Test/m8a_publish.sh $OUT $SPECS "finished (runs and sizes)" "eval/m8a/full: runs and sizes finished"
fi
