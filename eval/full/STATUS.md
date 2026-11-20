# 7b full run: status

Updated 2026-11-20 23:35 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 101 of 126 (shard size 50)
- Goals done: 5095 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1206
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1205 goals, projected 6.0 h → finish about 2026-11-21 05:36; observed throughput 26.2 s per goal → about 2026-11-21 08:22

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2095 | 387 | 200 | 911 | 584 | 13 |

Proved at N: 1: 378, 2: 152, 3: 91, 4: 42, 5: 32, 6: 10, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2095 goals with baselines):
  - sbe_like: closed 1413, failed 343, heartbeats 335, max_rec_depth 4
  - sbe_default: closed 1337, heartbeats 484, failed 270, max_rec_depth 4
  - exact: none 961, closed_other 896, closed_self 232, max_rec_depth 4, heartbeats 2
  - apply: partial 961, closed_other 896, closed_self 232, max_rec_depth 4, heartbeats 2
