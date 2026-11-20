# 7b full run: status

Updated 2026-11-20 20:06 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 87 of 126 (shard size 50)
- Goals done: 4395 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1029
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1905 goals, projected 8.4 h → finish about 2026-11-21 04:32; observed throughput 27.5 s per goal → about 2026-11-21 10:41

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1395 | 210 | 88 | 680 | 404 | 13 |

Proved at N: 1: 324, 2: 75, 3: 62, 4: 30, 5: 27, 6: 7, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1395 goals with baselines):
  - sbe_like: closed 941, heartbeats 269, failed 181, max_rec_depth 4
  - sbe_default: closed 873, heartbeats 385, failed 133, max_rec_depth 4
  - exact: none 629, closed_other 596, closed_self 166, max_rec_depth 4
  - apply: partial 629, closed_other 596, closed_self 166, max_rec_depth 4
