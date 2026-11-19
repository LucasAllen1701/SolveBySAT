# 7b full run: status

Updated 2026-11-20 10:18 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 63 of 126 (shard size 50)
- Goals done: 3173 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 60
- Crashes by cause: oom 868
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3127 goals, projected 17.8 h → finish about 2026-11-21 04:04; observed throughput 27.0 s per goal → about 2026-11-21 09:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 173 | 49 | 7 | 66 | 49 | 2 |

Proved at N: 1: 56, 2: 32, 3: 39, 4: 21, 5: 21, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (173 goals with baselines):
  - sbe_like: closed 130, heartbeats 32, failed 11
  - sbe_default: closed 118, heartbeats 47, failed 8
  - exact: closed_other 85, none 68, closed_self 20
  - apply: closed_other 85, partial 68, closed_self 20
