# 7b full run: status

Updated 2026-11-20 03:07 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 43 of 126 (shard size 50)
- Goals done: 2173 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 41
- Crashes by cause: oom 617
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4127 goals, projected 21.1 h → finish about 2026-11-21 00:15; observed throughput 27.6 s per goal → about 2026-11-21 10:42

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2173 | 617 | 229 | 1179 | 107 | 41 |

Proved at N: 1: 10, 2: 21, 3: 29, 4: 13, 5: 18, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2173 goals with baselines):
  - sbe_like: failed 922, closed 628, heartbeats 619, max_rec_depth 4
  - sbe_default: failed 880, heartbeats 685, closed 605, max_rec_depth 3
  - exact: closed_self 1955, closed_other 120, none 98
  - apply: closed_self 1955, closed_other 120, partial 98
