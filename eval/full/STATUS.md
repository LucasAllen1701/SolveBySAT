# 7b full run: status

Updated 2026-11-20 13:42 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 78 of 126 (shard size 50)
- Goals done: 3923 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 64
- Crashes by cause: oom 951
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2377 goals, projected 11.0 h → finish about 2026-11-21 00:41; observed throughput 24.9 s per goal → about 2026-11-21 06:10

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 923 | 132 | 70 | 460 | 255 | 6 |

Proved at N: 1: 217, 2: 54, 3: 50, 4: 27, 5: 24, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (923 goals with baselines):
  - sbe_like: closed 642, heartbeats 163, failed 114, max_rec_depth 4
  - sbe_default: closed 597, heartbeats 240, failed 82, max_rec_depth 4
  - exact: none 431, closed_other 394, closed_self 94, max_rec_depth 4
  - apply: partial 431, closed_other 394, closed_self 94, max_rec_depth 4
