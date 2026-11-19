# 7b full run: status

Updated 2026-11-19 23:45 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 29 of 126 (shard size 50)
- Goals done: 1473 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 36
- Crashes by cause: oom 482
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4827 goals, projected 24.1 h → finish about 2026-11-20 23:53; observed throughput 32.6 s per goal → about 2026-11-21 19:28

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1473 | 482 | 94 | 765 | 96 | 36 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 16, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1473 goals with baselines):
  - sbe_like: failed 582, heartbeats 546, closed 341, max_rec_depth 4
  - sbe_default: heartbeats 600, failed 551, closed 319, max_rec_depth 3
  - exact: closed_self 1287, none 96, closed_other 90
  - apply: closed_self 1287, partial 96, closed_other 90
