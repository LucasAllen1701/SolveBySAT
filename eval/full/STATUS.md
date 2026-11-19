# 7b full run: status

Updated 2026-11-20 06:47 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 54 of 126 (shard size 50)
- Goals done: 2723 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 49
- Crashes by cause: oom 745
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3577 goals, projected 17.7 h → finish about 2026-11-21 00:28; observed throughput 26.8 s per goal → about 2026-11-21 09:26

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2723 | 745 | 261 | 1540 | 128 | 49 |

Proved at N: 1: 15, 2: 22, 3: 34, 4: 19, 5: 20, 6: 6, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2723 goals with baselines):
  - sbe_like: failed 1082, closed 878, heartbeats 756, max_rec_depth 7
  - sbe_default: failed 1029, closed 845, heartbeats 843, max_rec_depth 6
  - exact: closed_self 2450, closed_other 139, none 133, heartbeats 1
  - apply: closed_self 2450, closed_other 139, partial 133, heartbeats 1
