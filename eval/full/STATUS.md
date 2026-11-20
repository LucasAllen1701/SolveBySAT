# 7b full run: status

Updated 2026-11-21 00:54 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 107 of 126 (shard size 50)
- Goals done: 5395 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1252
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 905 goals, projected 4.8 h → finish about 2026-11-21 05:44; observed throughput 25.6 s per goal → about 2026-11-21 07:20

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2395 | 433 | 227 | 1064 | 658 | 13 |

Proved at N: 1: 424, 2: 168, 3: 99, 4: 44, 5: 33, 6: 11, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2395 goals with baselines):
  - sbe_like: closed 1629, failed 401, heartbeats 361, max_rec_depth 4
  - sbe_default: closed 1553, heartbeats 520, failed 318, max_rec_depth 4
  - exact: none 1072, closed_other 1057, closed_self 260, max_rec_depth 4, heartbeats 2
  - apply: partial 1072, closed_other 1057, closed_self 260, max_rec_depth 4, heartbeats 2
