# 7b full run: status

Updated 2026-11-20 14:09 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 79 of 126 (shard size 50)
- Goals done: 3973 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 64
- Crashes by cause: oom 980
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2327 goals, projected 10.9 h → finish about 2026-11-21 01:01; observed throughput 25.0 s per goal → about 2026-11-21 06:20

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 973 | 161 | 70 | 475 | 261 | 6 |

Proved at N: 1: 221, 2: 56, 3: 50, 4: 27, 5: 24, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (973 goals with baselines):
  - sbe_like: closed 666, heartbeats 177, failed 126, max_rec_depth 4
  - sbe_default: closed 620, heartbeats 257, failed 92, max_rec_depth 4
  - exact: none 455, closed_other 411, closed_self 103, max_rec_depth 4
  - apply: partial 455, closed_other 411, closed_self 103, max_rec_depth 4
