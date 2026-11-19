# 7b full run: status

Updated 2026-11-20 09:53 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 62 of 126 (shard size 50)
- Goals done: 3123 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 58
- Crashes by cause: oom 855
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3177 goals, projected 17.4 h → finish about 2026-11-21 03:16; observed throughput 27.0 s per goal → about 2026-11-21 09:42

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 123 | 36 | 2 | 47 | 38 | 0 |

Proved at N: 1: 50, 2: 29, 3: 39, 4: 19, 5: 21, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (123 goals with baselines):
  - sbe_like: closed 95, heartbeats 21, failed 7
  - sbe_default: closed 90, heartbeats 29, failed 4
  - exact: closed_other 65, none 46, closed_self 12
  - apply: closed_other 65, partial 46, closed_self 12
