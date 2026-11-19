# 7b full run: status

Updated 2026-11-20 10:41 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 64 of 126 (shard size 50)
- Goals done: 3223 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 60
- Crashes by cause: oom 885
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3077 goals, projected 17.7 h → finish about 2026-11-21 04:26; observed throughput 27.0 s per goal → about 2026-11-21 09:47

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 223 | 66 | 7 | 84 | 64 | 2 |

Proved at N: 1: 68, 2: 34, 3: 39, 4: 21, 5: 22, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (223 goals with baselines):
  - sbe_like: closed 165, heartbeats 46, failed 12
  - sbe_default: closed 148, heartbeats 66, failed 9
  - exact: closed_other 106, none 92, closed_self 25
  - apply: closed_other 106, partial 92, closed_self 25
