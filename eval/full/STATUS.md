# 7b full run: status

Updated 2026-11-20 20:44 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 89 of 126 (shard size 50)
- Goals done: 4495 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1072
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1805 goals, projected 8.3 h → finish about 2026-11-21 05:02; observed throughput 27.4 s per goal → about 2026-11-21 10:29

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1495 | 253 | 95 | 701 | 433 | 13 |

Proved at N: 1: 341, 2: 85, 3: 63, 4: 31, 5: 27, 6: 7, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1495 goals with baselines):
  - sbe_like: closed 1022, heartbeats 281, failed 188, max_rec_depth 4
  - sbe_default: closed 950, heartbeats 401, failed 140, max_rec_depth 4
  - exact: none 683, closed_other 635, closed_self 172, max_rec_depth 4, heartbeats 1
  - apply: partial 683, closed_other 635, closed_self 172, max_rec_depth 4, heartbeats 1
