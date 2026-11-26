#!/bin/bash
# 8c-1 measurements and rerun (M8_PLAN 4.4). Start it detached so it outlives the shell:
#   setsid nohup Test/m8c1_full.sh > /dev/null 2>&1 &
# Resume by starting it again (every phase skips what is done). Log: eval/m8c1/driver.log.
# Phases, in order, each stopping the script on a non-zero exit (a stop rule or a harness error):
#   1. sizes at N = 5 on the 400 points, settings off, r1, r1r2 (with the checks of 4.4)
#   2. M1 to M7 at N = 5 with R1 and R2 on (M6 to M8)
#   3. the rerun of 8a's 200 runs with R1 and R2 on, its stop rules (4.4, 2.5) and its sizes
#   4. sizes at N = 10 on the 400 points, settings off, r1, r1r2
set -u
cd "$(dirname "$0")/.."
OUT=eval/m8c1; PTS=eval/m8b/specs_points.jsonl
mkdir -p $OUT
log() { echo "=== $1 $(date '+%F %T')" >> $OUT/driver.log; }
stop() { log "STOPPED in $1 (exit $2)"; python3 Test/m8c1_run.py publish "eval/m8c1: STOPPED in $1 (exit $2)"; exit $2; }
log start
python3 Test/m8c1_run.py sizes $PTS $OUT/sizes_N5 5 --publish >> $OUT/driver.log 2>&1 || stop "sizes N=5" $?
log "sizes N=5 done"
python3 Test/m8c1_run.py diag $PTS $OUT/diag_N5 5 r1r2 --publish >> $OUT/driver.log 2>&1 || stop "diag N=5" $?
log "diag N=5 done"
SOLVE_BY_SAT_EVAL_FLAGS=nodeBounds,exclusivePairs SOLVE_BY_SAT_EVAL_COMPARE=eval/m8a/full/results.jsonl \
  python3 Test/m8a_run.py run eval/m8a/specs.jsonl $OUT/rerun \
  --after-shard "Test/m8a_publish.sh \"\$1\" eval/m8a/specs.jsonl runs 'eval/m8c1/rerun: shard done'" \
  >> $OUT/driver.log 2>&1 || stop "rerun of 8a" $?
log "rerun done"
python3 Test/m8c1_run.py publish "eval/m8c1: rerun of 8a finished (runs and sizes)"
python3 Test/m8c1_run.py sizes $PTS $OUT/sizes_N10 10 --publish >> $OUT/driver.log 2>&1 || stop "sizes N=10" $?
log "sizes N=10 done"
python3 Test/m8c1_run.py publish "eval/m8c1: all phases finished"
log finished
