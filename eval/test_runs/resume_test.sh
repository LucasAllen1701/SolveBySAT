#!/bin/bash
# Resume acceptance test (7b): (a) SIGKILL the shard only; (b) SIGKILL the driver (its shard
# dies with it), then rerun. PIDs are matched with anchored patterns, never this script.
cd "$(dirname "$0")/../.." && ROOT=$PWD
T=eval/test_runs; R=$T/resume; rm -rf $R
shard_pid() { pgrep -f "^$ROOT/.lake/build/bin/eval_run run $R/"; }
python3 Test/eval_driver.py run $T/resume_specs.jsonl $R --shard-size 5 > $T/resume_a.log 2>&1 &
DRV=$!
alive() { kill -0 $DRV 2>/dev/null || { echo "driver ended early:"; grep -v '^/home\|libc\|backtrace\|PANIC' $T/resume_a.log; exit 1; }; }
until [ -f $R/started.jsonl ] && [ "$(wc -l < $R/started.jsonl)" -ge 3 ]; do alive; sleep 0.5; done
echo "(a) at kill: results $(cat $R/results.jsonl 2>/dev/null | wc -l), started $(wc -l < $R/started.jsonl), running $(tail -1 $R/started.jsonl)"
P=$(shard_pid); kill -KILL $P && echo "(a) SIGKILL sent to the shard process $P only"
until [ "$(wc -l < $R/started.jsonl)" -ge 8 ]; do alive; sleep 0.5; done
P=$(shard_pid); kill -KILL $DRV
echo "(b) SIGKILL sent to the driver $DRV: results $(wc -l < $R/results.jsonl), started $(wc -l < $R/started.jsonl), running $(tail -1 $R/started.jsonl)"
sleep 2; echo "shard $P still alive after the driver died? $(kill -0 $P 2>/dev/null && echo YES || echo no)"
echo "--- driver log up to (b):"; grep -v '^/home\|libc\|backtrace\|PANIC' $T/resume_a.log
echo "--- rerun of the driver:"; python3 Test/eval_driver.py run $T/resume_specs.jsonl $R --shard-size 5 2>&1 | grep -v '^/home\|libc\|backtrace\|PANIC'
python3 - <<'PY'
import json,collections
R='eval/test_runs/resume'
spec=[json.loads(l)['key'] for l in open('eval/test_runs/resume_specs.jsonl')]
res=[json.loads(l) for l in open(f'{R}/results.jsonl')]
st=[json.loads(l)['key'] for l in open(f'{R}/started.jsonl')]
c=collections.Counter(r['key'] for r in res)
print(f"specs {len(spec)}, started markers {len(st)} ({len(set(st))} distinct), result lines {len(res)}, distinct keys {len(c)}")
print(f"missing {[k for k in spec if k not in c]}, duplicated {[k for k,v in c.items() if v>1]}, extra {[k for k in c if k not in spec]}")
for r in res: print('  ', r['key'], r['outcome'], r.get('cause',''), r.get('found',''), r.get('N',''), r.get('memout_kind',''))
PY
