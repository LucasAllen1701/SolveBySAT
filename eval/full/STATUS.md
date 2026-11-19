# 7b full run: status

Updated 2026-11-19 19:38 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 18 of 126 (shard size 50)
- Goals done: 923 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 28
- Crashes by cause: oom 277
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5377 goals, projected 28.9 h → finish about 2026-11-21 00:33; observed throughput 36.2 s per goal → about 2026-11-22 01:40

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 923 | 277 | 26 | 514 | 78 | 28 |

Proved at N: 1: 9, 2: 15, 3: 21, 4: 9, 5: 13, 6: 3, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (923 goals with baselines):
  - sbe_like: heartbeats 406, failed 270, closed 243, max_rec_depth 4
  - sbe_default: heartbeats 450, failed 251, closed 219, max_rec_depth 3
  - exact: closed_self 759, none 96, closed_other 68
  - apply: closed_self 759, partial 96, closed_other 68
