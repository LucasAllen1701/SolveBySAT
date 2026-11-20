# 7b full run: status

Updated 2026-11-20 22:55 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 98 of 126 (shard size 50)
- Goals done: 4945 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1169
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1355 goals, projected 6.5 h → finish about 2026-11-21 05:22; observed throughput 26.5 s per goal → about 2026-11-21 08:54

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1945 | 350 | 176 | 855 | 551 | 13 |

Proved at N: 1: 369, 2: 138, 3: 84, 4: 40, 5: 31, 6: 10, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1945 goals with baselines):
  - sbe_like: closed 1305, heartbeats 329, failed 307, max_rec_depth 4
  - sbe_default: closed 1227, heartbeats 472, failed 242, max_rec_depth 4
  - exact: none 917, closed_other 822, closed_self 200, max_rec_depth 4, heartbeats 2
  - apply: partial 917, closed_other 822, closed_self 200, max_rec_depth 4, heartbeats 2
