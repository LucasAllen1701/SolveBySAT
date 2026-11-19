# 7b full run: status

Updated 2026-11-19 15:55 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 13 of 126 (shard size 50)
- Goals done: 650 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 21
- Crashes by cause: oom 195
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5650 goals, projected 31.1 h → finish about 2026-11-20 23:02; observed throughput 30.4 s per goal → about 2026-11-21 15:34

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 650 | 195 | 23 | 359 | 52 | 21 |

Proved at N: 1: 4, 2: 11, 3: 12, 4: 6, 5: 9, 6: 3, 7: 4, 8: 2, 9: 1

## Baselines so far

- Tier A (650 goals with baselines):
  - sbe_like: heartbeats 278, failed 194, closed 174, max_rec_depth 4
  - sbe_default: heartbeats 307, failed 183, closed 157, max_rec_depth 3
  - exact: closed_self 537, none 71, closed_other 42
  - apply: closed_self 537, partial 71, closed_other 42
