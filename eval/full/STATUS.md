# 7b full run: status

Updated 2026-11-19 12:13 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 3 of 126 (shard size 50)
- Goals done: 150 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 2
- Crashes by cause: oom 91
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 6150 goals, projected 38.5 h → finish about 2026-11-21 02:41; observed throughput 48.9 s per goal → about 2026-11-22 23:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 150 | 91 | 7 | 44 | 6 | 2 |

Proved at N: 2: 4, 4: 2

## Baselines so far

- Tier A (150 goals with baselines):
  - sbe_like: heartbeats 99, failed 30, closed 21
  - sbe_default: heartbeats 105, failed 28, closed 17
  - exact: closed_self 143, closed_other 7
  - apply: closed_self 143, closed_other 7
