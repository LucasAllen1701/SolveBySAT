# 7b full run: status

Updated 2026-11-20 00:01 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 30 of 126 (shard size 50)
- Goals done: 1523 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 36
- Crashes by cause: oom 498
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4777 goals, projected 24.1 h → finish about 2026-11-21 00:05; observed throughput 32.2 s per goal → about 2026-11-21 18:41

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1523 | 498 | 95 | 798 | 96 | 36 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 16, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1523 goals with baselines):
  - sbe_like: failed 614, heartbeats 548, closed 357, max_rec_depth 4
  - sbe_default: heartbeats 602, failed 583, closed 335, max_rec_depth 3
  - exact: closed_self 1336, none 96, closed_other 91
  - apply: closed_self 1336, partial 96, closed_other 91
