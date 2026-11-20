# 7b full run: status

Updated 2026-11-20 11:04 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 65 of 126 (shard size 50)
- Goals done: 3273 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 60
- Crashes by cause: oom 898
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3027 goals, projected 16.8 h → finish about 2026-11-21 03:53; observed throughput 27.0 s per goal → about 2026-11-21 09:49

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 273 | 79 | 14 | 107 | 71 | 2 |

Proved at N: 1: 75, 2: 34, 3: 39, 4: 21, 5: 22, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (273 goals with baselines):
  - sbe_like: closed 197, heartbeats 61, failed 15
  - sbe_default: closed 174, heartbeats 88, failed 11
  - exact: closed_other 129, none 113, closed_self 31
  - apply: closed_other 129, partial 113, closed_self 31
