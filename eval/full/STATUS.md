# 7b full run: status

Updated 2026-11-19 12:48 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 4 of 126 (shard size 50)
- Goals done: 200 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 3
- Crashes by cause: oom 119
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 6100 goals, projected 37.6 h → finish about 2026-11-21 02:27; observed throughput 46.6 s per goal → about 2026-11-22 19:45

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 200 | 119 | 7 | 60 | 11 | 3 |

Proved at N: 1: 1, 2: 4, 3: 1, 4: 2, 5: 2, 7: 1

## Baselines so far

- Tier A (200 goals with baselines):
  - sbe_like: heartbeats 129, failed 38, closed 33
  - sbe_default: heartbeats 139, failed 35, closed 26
  - exact: closed_self 192, closed_other 8
  - apply: closed_self 192, closed_other 8
