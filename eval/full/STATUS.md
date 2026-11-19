# 7b full run: status

Updated 2026-11-20 04:48 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 49 of 126 (shard size 50)
- Goals done: 2473 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 43
- Crashes by cause: oom 697
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3827 goals, projected 19.7 h → finish about 2026-11-21 00:27; observed throughput 26.6 s per goal → about 2026-11-21 09:07

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2473 | 697 | 243 | 1370 | 120 | 43 |

Proved at N: 1: 14, 2: 21, 3: 33, 4: 16, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2473 goals with baselines):
  - sbe_like: failed 1034, closed 779, heartbeats 656, max_rec_depth 4
  - sbe_default: failed 984, closed 756, heartbeats 730, max_rec_depth 3
  - exact: closed_self 2205, closed_other 134, none 133, heartbeats 1
  - apply: closed_self 2205, closed_other 134, partial 133, heartbeats 1
