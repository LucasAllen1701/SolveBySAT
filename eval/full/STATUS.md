# 7b full run: status

Updated 2026-11-20 03:31 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 44 of 126 (shard size 50)
- Goals done: 2223 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 41
- Crashes by cause: oom 637
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4077 goals, projected 20.7 h → finish about 2026-11-21 00:13; observed throughput 27.6 s per goal → about 2026-11-21 10:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2223 | 637 | 233 | 1200 | 112 | 41 |

Proved at N: 1: 10, 2: 21, 3: 31, 4: 14, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2223 goals with baselines):
  - sbe_like: failed 947, closed 636, heartbeats 636, max_rec_depth 4
  - sbe_default: failed 901, heartbeats 707, closed 612, max_rec_depth 3
  - exact: closed_self 1995, closed_other 123, none 105
  - apply: closed_self 1995, closed_other 123, partial 105
