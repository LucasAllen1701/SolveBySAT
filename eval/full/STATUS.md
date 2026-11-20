# 7b full run: status

Updated 2026-11-21 03:24 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 119 of 126 (shard size 50)
- Goals done: 5995 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 74
- Crashes by cause: oom 1314
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 305 goals, projected 1.3 h → finish about 2026-11-21 04:44; observed throughput 24.6 s per goal → about 2026-11-21 05:29

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2995 | 495 | 297 | 1359 | 828 | 16 |

Proved at N: 1: 546, 2: 192, 3: 115, 4: 47, 5: 34, 6: 12, 7: 12, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2995 goals with baselines):
  - sbe_like: closed 2065, failed 476, heartbeats 446, max_rec_depth 8
  - sbe_default: closed 1984, heartbeats 640, failed 363, max_rec_depth 8
  - exact: closed_other 1370, none 1281, closed_self 327, max_rec_depth 9, heartbeats 8
  - apply: closed_other 1370, partial 1281, closed_self 327, max_rec_depth 9, heartbeats 8
