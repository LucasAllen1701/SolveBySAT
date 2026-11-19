# 7b full run: status

Updated 2026-11-20 00:41 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 33 of 126 (shard size 50)
- Goals done: 1673 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 524
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4627 goals, projected 23.5 h → finish about 2026-11-21 00:11; observed throughput 30.7 s per goal → about 2026-11-21 16:05

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1673 | 524 | 108 | 902 | 102 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 11, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1673 goals with baselines):
  - sbe_like: failed 687, heartbeats 558, closed 424, max_rec_depth 4
  - sbe_default: failed 656, heartbeats 612, closed 402, max_rec_depth 3
  - exact: closed_self 1483, none 98, closed_other 92
  - apply: closed_self 1483, partial 98, closed_other 92
