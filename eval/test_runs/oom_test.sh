#!/bin/bash
cd "$(dirname "$0")/../.." && ROOT=$PWD
T=eval/test_runs
summ() { python3 -c "
import json,sys
for l in open('$1/results.jsonl'):
    r=json.loads(l); print('  ', r['key'], r['outcome'], 'cause', r.get('cause'), 'last_N', r.get('last_N'), 'N', r.get('N'), 'hwm_mb', r.get('hwm_mb'))
"; }
echo "=== forced OOM: cap 1200 MB"; rm -rf $T/oom_1200
python3 Test/eval_driver.py run $T/oom_specs.jsonl $T/oom_1200 --cap-mb 1200 2>&1 | grep -v '^/home\|libc\|backtrace\|PANIC'
summ $T/oom_1200; cat $T/oom_1200/warmup.jsonl
echo "=== the same goal alone at the real cap, 2500 MB"; rm -rf $T/oom_2500
python3 Test/eval_driver.py run $T/oom_specs.jsonl $T/oom_2500 2>&1 | grep -v '^/home\|libc\|backtrace\|PANIC'
summ $T/oom_2500; grep -c '"N"' $T/oom_2500/started.jsonl
