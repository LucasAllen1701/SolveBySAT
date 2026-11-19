# 7b full run: status

Updated 2026-11-19 20:01 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 19 of 126 (shard size 50)
- Goals done: 973 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 31
- Crashes by cause: oom 283
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5327 goals, projected 28.4 h → finish about 2026-11-21 00:27; observed throughput 35.7 s per goal → about 2026-11-22 00:51

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 973 | 283 | 26 | 550 | 83 | 31 |

Proved at N: 1: 9, 2: 17, 3: 23, 4: 9, 5: 13, 6: 4, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (973 goals with baselines):
  - sbe_like: heartbeats 427, failed 288, closed 254, max_rec_depth 4
  - sbe_default: heartbeats 472, failed 268, closed 230, max_rec_depth 3
  - exact: closed_self 802, none 96, closed_other 75
  - apply: closed_self 802, partial 96, closed_other 75
