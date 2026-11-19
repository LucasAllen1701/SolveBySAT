# 7b full run: status

Updated 2026-11-20 01:11 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 37 of 126 (shard size 50)
- Goals done: 1873 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 544
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4427 goals, projected 22.6 h → finish about 2026-11-20 23:47; observed throughput 28.3 s per goal → about 2026-11-21 11:57

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1873 | 544 | 205 | 983 | 104 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 13, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1873 goals with baselines):
  - sbe_like: failed 785, heartbeats 561, closed 523, max_rec_depth 4
  - sbe_default: failed 748, heartbeats 621, closed 501, max_rec_depth 3
  - exact: closed_self 1675, closed_other 100, none 98
  - apply: closed_self 1675, closed_other 100, partial 98
