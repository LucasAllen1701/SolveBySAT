# 7b full run: status

Updated 2026-11-19 14:46 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 10 of 126 (shard size 50)
- Goals done: 500 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 12
- Crashes by cause: oom 162
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5800 goals, projected 33.0 h → finish about 2026-11-20 23:47; observed throughput 31.2 s per goal → about 2026-11-21 17:03

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 500 | 162 | 10 | 274 | 42 | 12 |

Proved at N: 1: 4, 2: 11, 3: 7, 4: 5, 5: 7, 6: 2, 7: 4, 8: 1, 9: 1

## Baselines so far

- Tier A (500 goals with baselines):
  - sbe_like: heartbeats 227, failed 138, closed 133, max_rec_depth 2
  - sbe_default: heartbeats 247, failed 131, closed 120, max_rec_depth 2
  - exact: closed_self 471, closed_other 29
  - apply: closed_self 471, closed_other 29
