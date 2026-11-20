# 7b full run: status

Updated 2026-11-20 14:27 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 80 of 126 (shard size 50)
- Goals done: 4023 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 65
- Crashes by cause: oom 990
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2277 goals, projected 10.5 h → finish about 2026-11-21 00:59; observed throughput 25.0 s per goal → about 2026-11-21 06:16

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1023 | 171 | 70 | 494 | 281 | 7 |

Proved at N: 1: 235, 2: 59, 3: 51, 4: 28, 5: 25, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1023 goals with baselines):
  - sbe_like: closed 703, heartbeats 187, failed 129, max_rec_depth 4
  - sbe_default: closed 653, heartbeats 271, failed 95, max_rec_depth 4
  - exact: none 472, closed_other 437, closed_self 110, max_rec_depth 4
  - apply: partial 472, closed_other 437, closed_self 110, max_rec_depth 4
