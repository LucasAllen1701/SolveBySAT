# 7b full run: status

Updated 2026-11-20 04:21 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 47 of 126 (shard size 50)
- Goals done: 2373 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 43
- Crashes by cause: oom 675
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3927 goals, projected 20.1 h → finish about 2026-11-21 00:25; observed throughput 27.1 s per goal → about 2026-11-21 09:54

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2373 | 675 | 238 | 1298 | 119 | 43 |

Proved at N: 1: 14, 2: 21, 3: 33, 4: 15, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2373 goals with baselines):
  - sbe_like: failed 984, closed 731, heartbeats 654, max_rec_depth 4
  - sbe_default: failed 936, heartbeats 726, closed 708, max_rec_depth 3
  - exact: closed_self 2111, none 133, closed_other 128, heartbeats 1
  - apply: closed_self 2111, partial 133, closed_other 128, heartbeats 1
