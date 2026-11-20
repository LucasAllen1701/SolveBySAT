# 7b full run: status

Updated 2026-11-21 02:48 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 116 of 126 (shard size 50)
- Goals done: 5845 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 73
- Crashes by cause: oom 1300
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 455 goals, projected 2.4 h → finish about 2026-11-21 05:11; observed throughput 24.8 s per goal → about 2026-11-21 05:56

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2845 | 481 | 261 | 1300 | 788 | 15 |

Proved at N: 1: 518, 2: 186, 3: 110, 4: 47, 5: 33, 6: 12, 7: 12, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2845 goals with baselines):
  - sbe_like: closed 1967, failed 453, heartbeats 421, max_rec_depth 4
  - sbe_default: closed 1887, heartbeats 606, failed 348, max_rec_depth 4
  - exact: closed_other 1299, none 1224, closed_self 311, heartbeats 6, max_rec_depth 5
  - apply: closed_other 1299, partial 1224, closed_self 311, heartbeats 6, max_rec_depth 5
