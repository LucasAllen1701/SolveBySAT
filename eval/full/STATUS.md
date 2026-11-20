# 7b full run: status

Updated 2026-11-20 21:33 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 92 of 126 (shard size 50)
- Goals done: 4645 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1118
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1655 goals, projected 7.7 h → finish about 2026-11-21 05:16; observed throughput 27.2 s per goal → about 2026-11-21 10:03

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1645 | 299 | 126 | 732 | 475 | 13 |

Proved at N: 1: 353, 2: 101, 3: 70, 4: 35, 5: 29, 6: 8, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1645 goals with baselines):
  - sbe_like: closed 1131, heartbeats 299, failed 211, max_rec_depth 4
  - sbe_default: closed 1054, heartbeats 429, failed 158, max_rec_depth 4
  - exact: none 760, closed_other 696, closed_self 183, max_rec_depth 4, heartbeats 2
  - apply: partial 760, closed_other 696, closed_self 183, max_rec_depth 4, heartbeats 2
