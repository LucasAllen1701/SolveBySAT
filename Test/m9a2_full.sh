#!/usr/bin/env bash
# 9a-2 (M9_PLAN 3.3): the whole measurement, detached: `setsid nohup Test/m9a2_full.sh > eval/m9a2/full_driver.log 2>&1 &`.
# Sizes at N = 5 and N = 10 (settings none, rw, rwnt), then the N = 5 diagnostics in rw and rwnt; each phase
# publishes eval/m9a2 (STATUS.md included) after every chunk. Resumable: run it again.
cd "$(dirname "$0")/.."
python3 Test/m9a2_run.py sizes 5 --publish || exit $?
python3 Test/m9a2_run.py sizes 10 --publish || exit $?
python3 Test/m9a2_run.py diag 5 rw --publish || exit $?
python3 Test/m9a2_run.py diag 5 rwnt --publish || exit $?
python3 Test/m9a2_run.py publish "eval/m9a2: the measurement is complete"
echo "m9a2_full: done"
