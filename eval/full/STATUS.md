# 7b full run: status

Updated 2026-11-20 05:46 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 51 of 126 (shard size 50)
- Goals done: 2573 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 46
- Crashes by cause: oom 729
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3727 goals, projected 18.8 h → finish about 2026-11-21 00:33; observed throughput 27.0 s per goal → about 2026-11-21 09:43

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2573 | 729 | 258 | 1415 | 125 | 46 |

Proved at N: 1: 15, 2: 21, 3: 34, 4: 18, 5: 19, 6: 6, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2573 goals with baselines):
  - sbe_like: failed 1055, closed 804, heartbeats 710, max_rec_depth 4
  - sbe_default: failed 1002, heartbeats 787, closed 781, max_rec_depth 3
  - exact: closed_self 2303, closed_other 136, none 133, heartbeats 1
  - apply: closed_self 2303, closed_other 136, partial 133, heartbeats 1
