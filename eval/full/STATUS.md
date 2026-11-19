# 7b full run: status

Updated 2026-11-20 09:02 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 59 of 126 (shard size 50)
- Goals done: 2973 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 58
- Crashes by cause: oom 819
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3327 goals, projected 15.4 h → finish about 2026-11-21 00:27; observed throughput 27.3 s per goal → about 2026-11-21 10:17

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2973 | 819 | 272 | 1689 | 135 | 58 |

Proved at N: 1: 16, 2: 24, 3: 35, 4: 19, 5: 21, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (2973 goals with baselines):
  - sbe_like: failed 1131, closed 963, heartbeats 868, max_rec_depth 11
  - sbe_default: failed 1071, heartbeats 963, closed 929, max_rec_depth 10
  - exact: closed_self 2631, none 182, closed_other 156, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2631, partial 182, closed_other 156, heartbeats 2, max_rec_depth 2
