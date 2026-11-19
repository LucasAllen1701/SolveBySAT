# 7b full run: status

Updated 2026-11-20 01:22 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 38 of 126 (shard size 50)
- Goals done: 1923 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 555
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4377 goals, projected 22.5 h → finish about 2026-11-20 23:51; observed throughput 27.9 s per goal → about 2026-11-21 11:16

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1923 | 555 | 215 | 1012 | 104 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 13, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1923 goals with baselines):
  - sbe_like: failed 813, heartbeats 561, closed 545, max_rec_depth 4
  - sbe_default: failed 774, heartbeats 623, closed 523, max_rec_depth 3
  - exact: closed_self 1719, closed_other 106, none 98
  - apply: closed_self 1719, closed_other 106, partial 98
