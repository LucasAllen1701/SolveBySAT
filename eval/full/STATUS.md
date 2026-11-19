# 7b full run: status

Updated 2026-11-19 16:43 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 15 of 126 (shard size 50)
- Goals done: 750 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 22
- Crashes by cause: oom 220
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5550 goals, projected 30.3 h → finish about 2026-11-20 23:00; observed throughput 30.1 s per goal → about 2026-11-21 15:04

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 750 | 220 | 23 | 422 | 63 | 22 |

Proved at N: 1: 6, 2: 13, 3: 16, 4: 8, 5: 9, 6: 3, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (750 goals with baselines):
  - sbe_like: heartbeats 318, failed 226, closed 202, max_rec_depth 4
  - sbe_default: heartbeats 353, failed 212, closed 182, max_rec_depth 3
  - exact: closed_self 599, none 95, closed_other 56
  - apply: closed_self 599, partial 95, closed_other 56
