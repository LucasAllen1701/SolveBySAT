# 7b full run: status

Updated 2026-11-20 09:40 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 61 of 126 (shard size 50)
- Goals done: 3073 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 58
- Crashes by cause: oom 842
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3227 goals, projected 19.2 h → finish about 2026-11-21 04:53; observed throughput 27.2 s per goal → about 2026-11-21 10:00

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 73 | 23 | 2 | 30 | 18 | 0 |

Proved at N: 1: 34, 2: 26, 3: 38, 4: 19, 5: 21, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (73 goals with baselines):
  - sbe_like: closed 51, heartbeats 16, failed 6
  - sbe_default: closed 47, heartbeats 23, failed 3
  - exact: closed_other 36, none 29, closed_self 8
  - apply: closed_other 36, partial 29, closed_self 8
