# 7b full run: status

Updated 2026-11-20 19:35 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 85 of 126 (shard size 50)
- Goals done: 4295 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 69
- Crashes by cause: oom 1018
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 2005 goals, projected 9.0 h → finish about 2026-11-21 04:32; observed throughput 27.7 s per goal → about 2026-11-21 11:02

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1295 | 199 | 86 | 630 | 369 | 11 |

Proved at N: 1: 296, 2: 70, 3: 61, 4: 30, 5: 27, 6: 7, 7: 9, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1295 goals with baselines):
  - sbe_like: closed 879, heartbeats 251, failed 161, max_rec_depth 4
  - sbe_default: closed 816, heartbeats 354, failed 121, max_rec_depth 4
  - exact: none 593, closed_other 552, closed_self 146, max_rec_depth 4
  - apply: partial 593, closed_other 552, closed_self 146, max_rec_depth 4
