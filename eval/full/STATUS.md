# 7b full run: status

Updated 2026-11-21 00:31 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 105 of 126 (shard size 50)
- Goals done: 5295 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1238
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1005 goals, projected 5.2 h → finish about 2026-11-21 05:46; observed throughput 25.8 s per goal → about 2026-11-21 07:44

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2295 | 419 | 219 | 1023 | 621 | 13 |

Proved at N: 1: 399, 2: 161, 3: 96, 4: 43, 5: 33, 6: 10, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2295 goals with baselines):
  - sbe_like: closed 1553, failed 385, heartbeats 353, max_rec_depth 4
  - sbe_default: closed 1477, heartbeats 507, failed 307, max_rec_depth 4
  - exact: none 1032, closed_other 1008, closed_self 249, max_rec_depth 4, heartbeats 2
  - apply: partial 1032, closed_other 1008, closed_self 249, max_rec_depth 4, heartbeats 2
