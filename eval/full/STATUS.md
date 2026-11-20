# 7b full run: status

Updated 2026-11-20 21:01 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 90 of 126 (shard size 50)
- Goals done: 4545 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1089
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1755 goals, projected 8.1 h → finish about 2026-11-21 05:06; observed throughput 27.4 s per goal → about 2026-11-21 10:22

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1545 | 270 | 109 | 712 | 441 | 13 |

Proved at N: 1: 344, 2: 87, 3: 63, 4: 34, 5: 27, 6: 7, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1545 goals with baselines):
  - sbe_like: closed 1052, heartbeats 287, failed 202, max_rec_depth 4
  - sbe_default: closed 978, heartbeats 413, failed 150, max_rec_depth 4
  - exact: none 708, closed_other 654, closed_self 177, max_rec_depth 4, heartbeats 2
  - apply: partial 708, closed_other 654, closed_self 177, max_rec_depth 4, heartbeats 2
