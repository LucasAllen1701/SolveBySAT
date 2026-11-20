# 7b full run: status

Updated 2026-11-20 12:34 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 73 of 126 (shard size 50)
- Goals done: 3673 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 62
- Crashes by cause: oom 927
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2627 goals, projected 12.2 h → finish about 2026-11-21 00:49; observed throughput 25.5 s per goal → about 2026-11-21 07:13

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 673 | 108 | 39 | 328 | 194 | 4 |

Proved at N: 1: 173, 2: 44, 3: 45, 4: 26, 5: 23, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (673 goals with baselines):
  - sbe_like: closed 475, heartbeats 125, failed 73
  - sbe_default: closed 447, heartbeats 175, failed 51
  - exact: closed_other 304, none 290, closed_self 79
  - apply: closed_other 304, partial 290, closed_self 79
