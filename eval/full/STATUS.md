# 7b full run: status

Updated 2026-11-20 11:30 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 67 of 126 (shard size 50)
- Goals done: 3373 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 61
- Crashes by cause: oom 908
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2927 goals, projected 15.2 h → finish about 2026-11-21 02:42; observed throughput 26.7 s per goal → about 2026-11-21 09:12

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 373 | 89 | 28 | 157 | 96 | 3 |

Proved at N: 1: 96, 2: 36, 3: 40, 4: 22, 5: 22, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (373 goals with baselines):
  - sbe_like: closed 268, heartbeats 78, failed 27
  - sbe_default: closed 246, heartbeats 110, failed 17
  - exact: closed_other 173, none 157, closed_self 43
  - apply: closed_other 173, partial 157, closed_self 43
