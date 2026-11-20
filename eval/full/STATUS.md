# 7b full run: status

Updated 2026-11-21 03:12 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 118 of 126 (shard size 50)
- Goals done: 5945 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 73
- Crashes by cause: oom 1313
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 355 goals, projected 1.6 h → finish about 2026-11-21 04:50; observed throughput 24.6 s per goal → about 2026-11-21 05:38

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2945 | 494 | 294 | 1333 | 809 | 15 |

Proved at N: 1: 533, 2: 189, 3: 113, 4: 47, 5: 33, 6: 12, 7: 12, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2945 goals with baselines):
  - sbe_like: closed 2034, failed 467, heartbeats 436, max_rec_depth 8
  - sbe_default: closed 1952, heartbeats 628, failed 357, max_rec_depth 8
  - exact: closed_other 1349, none 1261, closed_self 318, max_rec_depth 9, heartbeats 8
  - apply: closed_other 1349, partial 1261, closed_self 318, max_rec_depth 9, heartbeats 8
