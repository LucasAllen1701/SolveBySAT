# 7b full run: status

Updated 2026-11-21 04:29 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 125 of 126 (shard size 50)
- Goals done: 6295 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 78
- Crashes by cause: oom 1374
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 5 goals, projected 0.0 h → finish about 2026-11-21 04:30; observed throughput 24.0 s per goal → about 2026-11-21 04:31

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 3000 | 496 | 297 | 1363 | 828 | 16 |
| r1b | B | 295 | 59 | 28 | 118 | 86 | 4 |

Proved at N: 1: 598, 2: 212, 3: 122, 4: 52, 5: 35, 6: 12, 7: 12, 8: 7, 9: 4

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (3000 goals with baselines):
  - sbe_like: closed 2069, failed 476, heartbeats 447, max_rec_depth 8
  - sbe_default: closed 1987, heartbeats 642, failed 363, max_rec_depth 8
  - exact: closed_other 1371, none 1285, closed_self 327, max_rec_depth 9, heartbeats 8
  - apply: closed_other 1371, partial 1285, closed_self 327, max_rec_depth 9, heartbeats 8
