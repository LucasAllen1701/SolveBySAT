# 7b full run: status

Updated 2026-11-20 07:03 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 55 of 126 (shard size 50)
- Goals done: 2773 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 51
- Crashes by cause: oom 747
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3527 goals, projected 17.3 h → finish about 2026-11-21 00:23; observed throughput 26.7 s per goal → about 2026-11-21 09:11

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2773 | 747 | 261 | 1583 | 131 | 51 |

Proved at N: 1: 16, 2: 23, 3: 34, 4: 19, 5: 20, 6: 6, 7: 7, 8: 4, 9: 2

## Baselines so far

- Tier A (2773 goals with baselines):
  - sbe_like: failed 1090, closed 905, heartbeats 769, max_rec_depth 9
  - sbe_default: failed 1037, closed 871, heartbeats 857, max_rec_depth 8
  - exact: closed_self 2498, closed_other 141, none 133, heartbeats 1
  - apply: closed_self 2498, closed_other 141, partial 133, heartbeats 1
