# 7b full run: status

Updated 2026-11-20 07:24 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 56 of 126 (shard size 50)
- Goals done: 2823 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 53
- Crashes by cause: oom 752
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3477 goals, projected 17.0 h → finish about 2026-11-21 00:22; observed throughput 26.7 s per goal → about 2026-11-21 09:08

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2823 | 752 | 261 | 1625 | 132 | 53 |

Proved at N: 1: 16, 2: 23, 3: 34, 4: 19, 5: 20, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (2823 goals with baselines):
  - sbe_like: failed 1097, closed 931, heartbeats 786, max_rec_depth 9
  - sbe_default: failed 1043, closed 896, heartbeats 876, max_rec_depth 8
  - exact: closed_self 2548, closed_other 141, none 133, heartbeats 1
  - apply: closed_self 2548, closed_other 141, partial 133, heartbeats 1
