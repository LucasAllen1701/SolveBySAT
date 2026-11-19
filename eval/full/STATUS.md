# 7b full run: status

Updated 2026-11-19 20:53 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 21 of 126 (shard size 50)
- Goals done: 1073 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 34
- Crashes by cause: oom 303
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5227 goals, projected 27.6 h → finish about 2026-11-21 00:29; observed throughput 35.3 s per goal → about 2026-11-22 00:06

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1073 | 303 | 31 | 612 | 93 | 34 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 14, 6: 4, 7: 6, 8: 3, 9: 2

## Baselines so far

- Tier A (1073 goals with baselines):
  - sbe_like: heartbeats 476, failed 312, closed 281, max_rec_depth 4
  - sbe_default: heartbeats 522, failed 290, closed 258, max_rec_depth 3
  - exact: closed_self 897, none 96, closed_other 80
  - apply: closed_self 897, partial 96, closed_other 80
