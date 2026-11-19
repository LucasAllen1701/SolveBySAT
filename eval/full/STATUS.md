# 7b full run: status

Updated 2026-11-19 22:23 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 25 of 126 (shard size 50)
- Goals done: 1273 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 35
- Crashes by cause: oom 406
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5027 goals, projected 26.0 h → finish about 2026-11-21 00:20; observed throughput 33.9 s per goal → about 2026-11-21 21:44

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1273 | 406 | 52 | 687 | 93 | 35 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 14, 6: 4, 7: 6, 8: 3, 9: 2

## Baselines so far

- Tier A (1273 goals with baselines):
  - sbe_like: heartbeats 520, failed 433, closed 316, max_rec_depth 4
  - sbe_default: heartbeats 569, failed 408, closed 293, max_rec_depth 3
  - exact: closed_self 1094, none 96, closed_other 83
  - apply: closed_self 1094, partial 96, closed_other 83
