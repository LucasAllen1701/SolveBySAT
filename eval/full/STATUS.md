# 7b full run: status

Updated 2026-11-20 04:06 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 46 of 126 (shard size 50)
- Goals done: 2323 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 43
- Crashes by cause: oom 662
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3977 goals, projected 20.2 h → finish about 2026-11-21 00:18; observed throughput 27.3 s per goal → about 2026-11-21 10:14

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2323 | 662 | 238 | 1263 | 117 | 43 |

Proved at N: 1: 14, 2: 21, 3: 31, 4: 15, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2323 goals with baselines):
  - sbe_like: failed 983, closed 683, heartbeats 653, max_rec_depth 4
  - sbe_default: failed 935, heartbeats 725, closed 660, max_rec_depth 3
  - exact: closed_self 2063, none 133, closed_other 126, heartbeats 1
  - apply: closed_self 2063, partial 133, closed_other 126, heartbeats 1
