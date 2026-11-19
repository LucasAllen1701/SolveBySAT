# 7b full run: status

Updated 2026-11-19 19:12 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 17 of 126 (shard size 50)
- Goals done: 873 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 24
- Crashes by cause: oom 268
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5427 goals, projected 29.4 h → finish about 2026-11-21 00:34; observed throughput 36.5 s per goal → about 2026-11-22 02:14

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 873 | 268 | 26 | 484 | 71 | 24 |

Proved at N: 1: 8, 2: 15, 3: 19, 4: 8, 5: 10, 6: 3, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (873 goals with baselines):
  - sbe_like: heartbeats 383, failed 253, closed 233, max_rec_depth 4
  - sbe_default: heartbeats 427, failed 234, closed 209, max_rec_depth 3
  - exact: closed_self 716, none 95, closed_other 62
  - apply: closed_self 716, partial 95, closed_other 62
