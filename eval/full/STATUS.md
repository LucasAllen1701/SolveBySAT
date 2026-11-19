# 7b full run: status

Updated 2026-11-19 22:42 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 26 of 126 (shard size 50)
- Goals done: 1323 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 35
- Crashes by cause: oom 419
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4977 goals, projected 26.0 h → finish about 2026-11-21 00:42; observed throughput 33.5 s per goal → about 2026-11-21 21:01

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1323 | 419 | 54 | 720 | 95 | 35 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 15, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1323 goals with baselines):
  - sbe_like: heartbeats 522, failed 463, closed 334, max_rec_depth 4
  - sbe_default: heartbeats 571, failed 437, closed 312, max_rec_depth 3
  - exact: closed_self 1142, none 96, closed_other 85
  - apply: closed_self 1142, partial 96, closed_other 85
