#!/usr/bin/env bash
# 9a-3 (M9_PLAN 4.3 to 4.5): the full run, detached: `setsid nohup Test/m9a3_full.sh > eval/m9a3/full_driver.log 2>&1 &`.
# The N loop for all 400 runs (resuming past the pilot's), then the sizes at N = 5 and at each run's last N, then the
# rules made per spec; each phase publishes eval/m9a3 (STATUS.md included). A stop rule (exit 3 or 10) ends it.
# Resumable: run it again.
cd "$(dirname "$0")/.."
python3 Test/m9a3_run.py runs full --publish || { echo "m9a3_full: STOP (runs exited $?)"; exit 1; }
python3 Test/m9a3_run.py sizes full --publish || { echo "m9a3_full: STOP (sizes exited $?)"; exit 1; }
python3 Test/m9a3_run.py rules --publish || { echo "m9a3_full: STOP (rules exited $?)"; exit 1; }
python3 Test/m9a3_run.py publish "eval/m9a3: the runs and sizes are complete"
echo "m9a3_full: done"
