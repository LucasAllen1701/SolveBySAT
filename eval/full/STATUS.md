# 7b full run: status

Updated 2026-11-20 08:03 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 57 of 126 (shard size 50)
- Goals done: 2873 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 56
- Crashes by cause: oom 779
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3427 goals, projected 16.4 h → finish about 2026-11-21 00:29; observed throughput 27.0 s per goal → about 2026-11-21 09:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2873 | 779 | 263 | 1643 | 132 | 56 |

Proved at N: 1: 16, 2: 23, 3: 34, 4: 19, 5: 20, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (2873 goals with baselines):
  - sbe_like: failed 1103, closed 941, heartbeats 820, max_rec_depth 9
  - sbe_default: failed 1048, heartbeats 911, closed 906, max_rec_depth 8
  - exact: closed_self 2597, closed_other 142, none 133, heartbeats 1
  - apply: closed_self 2597, closed_other 142, partial 133, heartbeats 1
