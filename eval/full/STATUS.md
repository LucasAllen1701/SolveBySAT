# 7b full run: status

Updated 2026-11-21 00:45 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 106 of 126 (shard size 50)
- Goals done: 5345 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1244
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 955 goals, projected 5.0 h → finish about 2026-11-21 05:44; observed throughput 25.8 s per goal → about 2026-11-21 07:34

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2345 | 425 | 225 | 1044 | 638 | 13 |

Proved at N: 1: 413, 2: 161, 3: 98, 4: 43, 5: 33, 6: 11, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2345 goals with baselines):
  - sbe_like: closed 1586, failed 395, heartbeats 360, max_rec_depth 4
  - sbe_default: closed 1506, heartbeats 519, failed 316, max_rec_depth 4
  - exact: none 1054, closed_other 1033, closed_self 252, max_rec_depth 4, heartbeats 2
  - apply: partial 1054, closed_other 1033, closed_self 252, max_rec_depth 4, heartbeats 2
