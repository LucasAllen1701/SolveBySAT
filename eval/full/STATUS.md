# 7b full run: status

Updated 2026-11-20 20:21 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 88 of 126 (shard size 50)
- Goals done: 4445 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1040
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1855 goals, projected 8.3 h → finish about 2026-11-21 04:39; observed throughput 27.4 s per goal → about 2026-11-21 10:28

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1445 | 221 | 89 | 696 | 426 | 13 |

Proved at N: 1: 336, 2: 84, 3: 63, 4: 30, 5: 27, 6: 7, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1445 goals with baselines):
  - sbe_like: closed 984, heartbeats 274, failed 183, max_rec_depth 4
  - sbe_default: closed 913, heartbeats 393, failed 135, max_rec_depth 4
  - exact: none 651, closed_other 619, closed_self 171, max_rec_depth 4
  - apply: partial 651, closed_other 619, closed_self 171, max_rec_depth 4
