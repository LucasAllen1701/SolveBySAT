#!/bin/bash
# 8c-2a (M8_PLAN 4.5): the model check, then the R3 projection at N = 5 and N = 10 on the 400 points.
# Start detached:  setsid nohup Test/m8c2a_full.sh > /dev/null 2>&1 &
# Resume by starting it again (every phase skips what is done). Log: eval/m8c2a/driver.log.
# A non-zero exit of a phase (a stop rule or a harness error) stops the script.
set -u
cd "$(dirname "$0")/.."
OUT=eval/m8c2a; PTS=eval/m8b/specs_points.jsonl
mkdir -p $OUT
log() { echo "=== $1 $(date '+%F %T')" >> $OUT/driver.log; }
stop() { log "STOPPED in $1 (exit $2)"; python3 Test/m8c2a_run.py publish "eval/m8c2a: STOPPED in $1 (exit $2)"; exit $2; }
log start
python3 Test/m8c2a_run.py models --publish >> $OUT/driver.log 2>&1 || stop "model check" $?
log "model check done"
python3 Test/m8c2a_run.py sim $PTS $OUT/sim_N5 5 --publish >> $OUT/driver.log 2>&1 || stop "sim N=5" $?
log "sim N=5 done"
python3 Test/m8c2a_run.py sim $PTS $OUT/sim_N10 10 --publish >> $OUT/driver.log 2>&1 || stop "sim N=10" $?
log "sim N=10 done"
python3 Test/m8c2a_run.py publish "eval/m8c2a: all phases finished"
log finished
