# 7b full run: status

Updated 2026-11-19 11:33 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 2 of 126 (shard size 50)
- Goals done: 100 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 0
- Crashes by cause: oom 59
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 6200 goals, projected 39.2 h → finish about 2026-11-21 02:44; observed throughput 49.0 s per goal → about 2026-11-22 23:58

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 100 | 59 | 5 | 34 | 2 |

Proved at N: 2: 1, 4: 1

## Baselines so far

- Tier A (100 goals with baselines):
  - sbe_like: heartbeats 67, failed 18, closed 15
  - sbe_default: heartbeats 69, failed 18, closed 13
  - exact: closed_self 95, closed_other 5
  - apply: closed_self 95, closed_other 5
