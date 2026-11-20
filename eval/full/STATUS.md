# 7b full run: status

Updated 2026-11-20 12:11 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 71 of 126 (shard size 50)
- Goals done: 3573 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 61
- Crashes by cause: oom 919
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2727 goals, projected 13.1 h → finish about 2026-11-21 01:15; observed throughput 25.9 s per goal → about 2026-11-21 07:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 573 | 100 | 39 | 274 | 157 | 3 |

Proved at N: 1: 140, 2: 44, 3: 44, 4: 25, 5: 22, 6: 6, 7: 9, 8: 5, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (573 goals with baselines):
  - sbe_like: closed 399, heartbeats 106, failed 68
  - sbe_default: closed 374, heartbeats 153, failed 46
  - exact: closed_other 252, none 252, closed_self 69
  - apply: closed_other 252, partial 252, closed_self 69
