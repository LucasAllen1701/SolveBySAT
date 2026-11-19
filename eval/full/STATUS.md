# 7b full run: status

Updated 2026-11-19 22:03 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 24 of 126 (shard size 50)
- Goals done: 1223 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 35
- Crashes by cause: oom 376
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5077 goals, projected 26.2 h → finish about 2026-11-21 00:17; observed throughput 34.3 s per goal → about 2026-11-21 22:26

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1223 | 376 | 50 | 669 | 93 | 35 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 14, 6: 4, 7: 6, 8: 3, 9: 2

## Baselines so far

- Tier A (1223 goals with baselines):
  - sbe_like: heartbeats 514, failed 396, closed 309, max_rec_depth 4
  - sbe_default: heartbeats 563, failed 371, closed 286, max_rec_depth 3
  - exact: closed_self 1046, none 96, closed_other 81
  - apply: closed_self 1046, partial 96, closed_other 81
