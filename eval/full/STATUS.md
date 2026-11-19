# 7b full run: status

Updated 2026-11-20 05:18 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 50 of 126 (shard size 50)
- Goals done: 2523 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 44
- Crashes by cause: oom 715
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3777 goals, projected 19.2 h → finish about 2026-11-21 00:30; observed throughput 26.8 s per goal → about 2026-11-21 09:27

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2523 | 715 | 250 | 1392 | 122 | 44 |

Proved at N: 1: 15, 2: 21, 3: 33, 4: 17, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2523 goals with baselines):
  - sbe_like: failed 1046, closed 790, heartbeats 683, max_rec_depth 4
  - sbe_default: failed 994, closed 768, heartbeats 758, max_rec_depth 3
  - exact: closed_self 2253, closed_other 136, none 133, heartbeats 1
  - apply: closed_self 2253, closed_other 136, partial 133, heartbeats 1
