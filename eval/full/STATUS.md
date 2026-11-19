# 7b full run: status

Updated 2026-11-20 08:37 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 58 of 126 (shard size 50)
- Goals done: 2923 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 58
- Crashes by cause: oom 805
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3377 goals, projected 15.9 h → finish about 2026-11-21 00:32; observed throughput 27.3 s per goal → about 2026-11-21 10:11

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2923 | 805 | 266 | 1660 | 134 | 58 |

Proved at N: 1: 16, 2: 24, 3: 34, 4: 19, 5: 21, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (2923 goals with baselines):
  - sbe_like: failed 1114, closed 952, heartbeats 848, max_rec_depth 9
  - sbe_default: failed 1058, heartbeats 940, closed 917, max_rec_depth 8
  - exact: closed_self 2629, none 147, closed_other 146, heartbeats 1
  - apply: closed_self 2629, partial 147, closed_other 146, heartbeats 1
