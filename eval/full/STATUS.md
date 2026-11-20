# 7b full run: status

Updated 2026-11-20 13:21 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 76 of 126 (shard size 50)
- Goals done: 3823 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 64
- Crashes by cause: oom 937
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2477 goals, projected 11.5 h → finish about 2026-11-21 00:51; observed throughput 25.3 s per goal → about 2026-11-21 06:45

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 823 | 118 | 68 | 410 | 221 | 6 |

Proved at N: 1: 197, 2: 45, 3: 46, 4: 26, 5: 24, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (823 goals with baselines):
  - sbe_like: closed 573, heartbeats 155, failed 91, max_rec_depth 4
  - sbe_default: closed 531, heartbeats 224, failed 64, max_rec_depth 4
  - exact: none 390, closed_other 345, closed_self 84, max_rec_depth 4
  - apply: partial 390, closed_other 345, closed_self 84, max_rec_depth 4
