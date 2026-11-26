#!/bin/bash
# 8d (M8_PLAN 4.6): the runs. Start it detached so it outlives the shell:
#   setsid nohup Test/m8d_full.sh pilot > /dev/null 2>&1 &     the 20 pilot runs (5 per group)
#   setsid nohup Test/m8d_full.sh full  > /dev/null 2>&1 &     the 300 runs (the pilot's count if nothing changed)
# Resume by starting it again. Both write to eval/m8d/runs; log eval/m8d/driver.log. A non-zero exit
# (exit 9 an exactness stop, 3 decoder bug or solver error, 4 harness error, ...) stops it and is published.
set -u
cd "$(dirname "$0")/.."
D=eval/m8d; OUT=$D/runs; PHASE=${1:?pilot or full}
case $PHASE in pilot) SPECS=$D/specs_pilot.jsonl ;; full) SPECS=$D/specs.jsonl ;; *) echo "pilot or full"; exit 2 ;; esac
log() { echo "=== $1 $(date '+%F %T')" >> $D/driver.log; }
log "start $PHASE"
python3 Test/m8d_run.py run $SPECS $OUT \
  --after-shard "python3 Test/m8d_run.py publish \"\$1\" $PHASE 'eval/m8d: $PHASE, shard done'" >> $D/driver.log 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  log "STOPPED in $PHASE (exit $rc)"
  python3 Test/m8d_run.py publish $OUT "$PHASE (STOPPED, exit $rc)" "eval/m8d: STOPPED in $PHASE (exit $rc)"
  exit $rc
fi
[ $PHASE = pilot ] && cp $OUT/timing.json $D/timing_pilot.json
log "$PHASE done"
python3 Test/m8d_run.py publish $OUT "$PHASE finished" "eval/m8d: $PHASE finished (runs and sizes)"
log finished
