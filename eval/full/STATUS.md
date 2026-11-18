# 7b full run: status

Updated 2026-11-19 10:52 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 1 of 126 (shard size 50)
- Goals done: 50 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 0
- Crashes by cause: oom 29
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 6250 goals, projected 37.7 h → finish about 2026-11-21 00:34

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 50 | 29 | 1 | 18 | 2 |

Proved at N: 2: 1, 4: 1

## Baselines so far

- Tier A (50 goals with baselines):
  - sbe_like: heartbeats 33, failed 9, closed 8
  - sbe_default: heartbeats 34, failed 9, closed 7
  - exact: closed_self 45, closed_other 5
  - apply: closed_self 45, closed_other 5
