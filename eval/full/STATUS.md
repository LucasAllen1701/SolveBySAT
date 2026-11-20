# 7b full run: status

Updated 2026-11-21 01:17 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 109 of 126 (shard size 50)
- Goals done: 5495 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1267
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 805 goals, projected 4.4 h → finish about 2026-11-21 05:39; observed throughput 25.4 s per goal → about 2026-11-21 06:58

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2495 | 448 | 229 | 1113 | 692 | 13 |

Proved at N: 1: 437, 2: 179, 3: 105, 4: 46, 5: 33, 6: 12, 7: 10, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2495 goals with baselines):
  - sbe_like: closed 1713, failed 412, heartbeats 366, max_rec_depth 4
  - sbe_default: closed 1638, heartbeats 530, failed 323, max_rec_depth 4
  - exact: closed_other 1110, none 1108, closed_self 269, max_rec_depth 4, heartbeats 4
  - apply: closed_other 1110, partial 1108, closed_self 269, max_rec_depth 4, heartbeats 4
