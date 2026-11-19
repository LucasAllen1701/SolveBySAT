# 7b full run: status

Updated 2026-11-20 00:55 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 35 of 126 (shard size 50)
- Goals done: 1773 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 534
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4527 goals, projected 23.0 h → finish about 2026-11-20 23:52; observed throughput 29.4 s per goal → about 2026-11-21 13:49

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1773 | 534 | 155 | 945 | 102 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 11, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1773 goals with baselines):
  - sbe_like: failed 769, heartbeats 559, closed 441, max_rec_depth 4
  - sbe_default: failed 737, heartbeats 614, closed 419, max_rec_depth 3
  - exact: closed_self 1580, none 98, closed_other 95
  - apply: closed_self 1580, partial 98, closed_other 95
