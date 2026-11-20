# 7b full run: status

Updated 2026-11-20 15:32 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 84 of 126 (shard size 50)
- Goals done: 4223 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 67
- Crashes by cause: oom 1008
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2077 goals, projected 9.4 h → finish about 2026-11-21 00:55; observed throughput 24.7 s per goal → about 2026-11-21 05:48

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1223 | 189 | 86 | 598 | 341 | 9 |

Proved at N: 1: 281, 2: 65, 3: 57, 4: 28, 5: 27, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1223 goals with baselines):
  - sbe_like: closed 835, heartbeats 231, failed 153, max_rec_depth 4
  - sbe_default: closed 773, heartbeats 333, failed 113, max_rec_depth 4
  - exact: none 564, closed_other 522, closed_self 133, max_rec_depth 4
  - apply: partial 564, closed_other 522, closed_self 133, max_rec_depth 4
