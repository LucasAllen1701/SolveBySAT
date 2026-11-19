# 7b full run: status

Updated 2026-11-20 04:31 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 48 of 126 (shard size 50)
- Goals done: 2423 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 43
- Crashes by cause: oom 683
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3877 goals, projected 19.9 h → finish about 2026-11-21 00:27; observed throughput 26.8 s per goal → about 2026-11-21 09:23

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2423 | 683 | 238 | 1340 | 119 | 43 |

Proved at N: 1: 14, 2: 21, 3: 33, 4: 15, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2423 goals with baselines):
  - sbe_like: failed 1005, closed 760, heartbeats 654, max_rec_depth 4
  - sbe_default: failed 956, closed 738, heartbeats 726, max_rec_depth 3
  - exact: closed_self 2160, none 133, closed_other 129, heartbeats 1
  - apply: closed_self 2160, partial 133, closed_other 129, heartbeats 1
