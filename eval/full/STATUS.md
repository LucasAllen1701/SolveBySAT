# 7b full run: status

Updated 2026-11-19 18:36 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 16 of 126 (shard size 50)
- Goals done: 823 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 23
- Crashes by cause: oom 249
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5477 goals, projected 29.7 h → finish about 2026-11-21 00:21; observed throughput 36.0 s per goal → about 2026-11-22 01:26

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 823 | 249 | 25 | 459 | 67 | 23 |

Proved at N: 1: 7, 2: 14, 3: 17, 4: 8, 5: 10, 6: 3, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (823 goals with baselines):
  - sbe_like: heartbeats 355, failed 247, closed 217, max_rec_depth 4
  - sbe_default: heartbeats 393, failed 231, closed 196, max_rec_depth 3
  - exact: closed_self 668, none 95, closed_other 60
  - apply: closed_self 668, partial 95, closed_other 60
