# 7b full run: status

Updated 2026-11-19 23:25 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 28 of 126 (shard size 50)
- Goals done: 1423 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 35
- Crashes by cause: oom 462
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4877 goals, projected 24.8 h → finish about 2026-11-21 00:15; observed throughput 32.9 s per goal → about 2026-11-21 19:59

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1423 | 462 | 80 | 750 | 96 | 35 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 16, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1423 goals with baselines):
  - sbe_like: failed 544, heartbeats 537, closed 338, max_rec_depth 4
  - sbe_default: heartbeats 590, failed 514, closed 316, max_rec_depth 3
  - exact: closed_self 1242, none 96, closed_other 85
  - apply: closed_self 1242, partial 96, closed_other 85
