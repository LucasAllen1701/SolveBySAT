# 7b full run: status

Updated 2026-11-20 00:47 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 34 of 126 (shard size 50)
- Goals done: 1723 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 529
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4577 goals, projected 23.2 h → finish about 2026-11-21 00:00; observed throughput 30.0 s per goal → about 2026-11-21 14:52

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1723 | 529 | 130 | 925 | 102 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 11, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1723 goals with baselines):
  - sbe_like: failed 732, heartbeats 558, closed 429, max_rec_depth 4
  - sbe_default: failed 701, heartbeats 612, closed 407, max_rec_depth 3
  - exact: closed_self 1532, none 98, closed_other 93
  - apply: closed_self 1532, partial 98, closed_other 93
