# 7b full run: status

Updated 2026-11-20 12:24 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 72 of 126 (shard size 50)
- Goals done: 3623 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 62
- Crashes by cause: oom 924
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2677 goals, projected 12.7 h → finish about 2026-11-21 01:05; observed throughput 25.7 s per goal → about 2026-11-21 07:32

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 623 | 105 | 39 | 301 | 174 | 4 |

Proved at N: 1: 157, 2: 44, 3: 44, 4: 25, 5: 22, 6: 6, 7: 9, 8: 5, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (623 goals with baselines):
  - sbe_like: closed 435, heartbeats 119, failed 69
  - sbe_default: closed 410, heartbeats 166, failed 47
  - exact: closed_other 279, none 271, closed_self 73
  - apply: closed_other 279, partial 271, closed_self 73
