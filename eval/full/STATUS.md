# 7b full run: status

Updated 2026-11-20 06:13 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 52 of 126 (shard size 50)
- Goals done: 2623 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 48
- Crashes by cause: oom 741
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3677 goals, projected 18.4 h → finish about 2026-11-21 00:36; observed throughput 27.1 s per goal → about 2026-11-21 09:53

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2623 | 741 | 261 | 1447 | 126 | 48 |

Proved at N: 1: 15, 2: 21, 3: 34, 4: 19, 5: 19, 6: 6, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2623 goals with baselines):
  - sbe_like: failed 1061, closed 826, heartbeats 732, max_rec_depth 4
  - sbe_default: failed 1008, heartbeats 812, closed 800, max_rec_depth 3
  - exact: closed_self 2351, closed_other 138, none 133, heartbeats 1
  - apply: closed_self 2351, closed_other 138, partial 133, heartbeats 1
