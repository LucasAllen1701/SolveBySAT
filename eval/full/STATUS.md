# 7b full run: status

Updated 2026-11-21 02:07 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 112 of 126 (shard size 50)
- Goals done: 5645 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 72
- Crashes by cause: oom 1291
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 655 goals, projected 3.5 h → finish about 2026-11-21 05:38; observed throughput 25.3 s per goal → about 2026-11-21 06:42

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2645 | 472 | 242 | 1194 | 723 | 14 |

Proved at N: 1: 463, 2: 180, 3: 108, 4: 47, 5: 33, 6: 12, 7: 10, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2645 goals with baselines):
  - sbe_like: closed 1815, failed 432, heartbeats 394, max_rec_depth 4
  - sbe_default: closed 1735, heartbeats 570, failed 336, max_rec_depth 4
  - exact: closed_other 1184, none 1167, closed_self 284, heartbeats 6, max_rec_depth 4
  - apply: closed_other 1184, partial 1167, closed_self 284, heartbeats 6, max_rec_depth 4
