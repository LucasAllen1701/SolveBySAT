# 7b full run: status

Updated 2026-11-20 01:39 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 39 of 126 (shard size 50)
- Goals done: 1973 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 564
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4327 goals, projected 22.4 h → finish about 2026-11-21 00:03; observed throughput 27.7 s per goal → about 2026-11-21 10:56

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1973 | 564 | 217 | 1050 | 105 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 13, 5: 18, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1973 goals with baselines):
  - sbe_like: failed 830, closed 576, heartbeats 563, max_rec_depth 4
  - sbe_default: failed 791, heartbeats 625, closed 554, max_rec_depth 3
  - exact: closed_self 1767, closed_other 108, none 98
  - apply: closed_self 1767, closed_other 108, partial 98
