# 7b full run: status

Updated 2026-11-20 15:01 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 82 of 126 (shard size 50)
- Goals done: 4123 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 67
- Crashes by cause: oom 1005
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2177 goals, projected 10.0 h → finish about 2026-11-21 01:00; observed throughput 24.9 s per goal → about 2026-11-21 06:04

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1123 | 186 | 80 | 535 | 313 | 9 |

Proved at N: 1: 260, 2: 63, 3: 54, 4: 28, 5: 25, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1123 goals with baselines):
  - sbe_like: closed 774, heartbeats 205, failed 140, max_rec_depth 4
  - sbe_default: closed 721, heartbeats 296, failed 102, max_rec_depth 4
  - exact: none 510, closed_other 486, closed_self 123, max_rec_depth 4
  - apply: partial 510, closed_other 486, closed_self 123, max_rec_depth 4
