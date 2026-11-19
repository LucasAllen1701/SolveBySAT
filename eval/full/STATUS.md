# 7b full run: status

Updated 2026-11-19 23:02 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 27 of 126 (shard size 50)
- Goals done: 1373 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 35
- Crashes by cause: oom 439
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4927 goals, projected 25.4 h → finish about 2026-11-21 00:27; observed throughput 33.1 s per goal → about 2026-11-21 20:21

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1373 | 439 | 71 | 732 | 96 | 35 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 16, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1373 goals with baselines):
  - sbe_like: heartbeats 529, failed 503, closed 337, max_rec_depth 4
  - sbe_default: heartbeats 580, failed 475, closed 315, max_rec_depth 3
  - exact: closed_self 1192, none 96, closed_other 85
  - apply: closed_self 1192, partial 96, closed_other 85
