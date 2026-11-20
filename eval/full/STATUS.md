# 7b full run: status

Updated 2026-11-21 02:59 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 117 of 126 (shard size 50)
- Goals done: 5895 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 73
- Crashes by cause: oom 1309
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 405 goals, projected 2.0 h → finish about 2026-11-21 04:59; observed throughput 24.7 s per goal → about 2026-11-21 05:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2895 | 490 | 279 | 1312 | 799 | 15 |

Proved at N: 1: 528, 2: 187, 3: 110, 4: 47, 5: 33, 6: 12, 7: 12, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2895 goals with baselines):
  - sbe_like: closed 2003, failed 459, heartbeats 429, max_rec_depth 4
  - sbe_default: closed 1922, heartbeats 616, failed 353, max_rec_depth 4
  - exact: closed_other 1324, none 1244, closed_self 316, heartbeats 6, max_rec_depth 5
  - apply: closed_other 1324, partial 1244, closed_self 316, heartbeats 6, max_rec_depth 5
