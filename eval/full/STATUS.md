# 7b full run: status

Updated 2026-11-19 16:12 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 14 of 126 (shard size 50)
- Goals done: 700 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 21
- Crashes by cause: oom 201
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5600 goals, projected 30.7 h → finish about 2026-11-20 22:55; observed throughput 29.6 s per goal → about 2026-11-21 14:14

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 700 | 201 | 23 | 396 | 59 | 21 |

Proved at N: 1: 5, 2: 11, 3: 15, 4: 8, 5: 9, 6: 3, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (700 goals with baselines):
  - sbe_like: heartbeats 292, failed 211, closed 193, max_rec_depth 4
  - sbe_default: heartbeats 323, failed 199, closed 175, max_rec_depth 3
  - exact: closed_self 551, none 95, closed_other 54
  - apply: closed_self 551, partial 95, closed_other 54
