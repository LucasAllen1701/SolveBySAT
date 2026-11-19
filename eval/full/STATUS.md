# 7b full run: status

Updated 2026-11-19 15:05 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 11 of 126 (shard size 50)
- Goals done: 550 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 15
- Crashes by cause: oom 168
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5750 goals, projected 32.4 h → finish about 2026-11-20 23:29; observed throughput 30.4 s per goal → about 2026-11-21 15:37

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 550 | 168 | 11 | 309 | 47 | 15 |

Proved at N: 1: 4, 2: 11, 3: 8, 4: 5, 5: 9, 6: 3, 7: 4, 8: 2, 9: 1

## Baselines so far

- Tier A (550 goals with baselines):
  - sbe_like: heartbeats 243, failed 155, closed 148, max_rec_depth 4
  - sbe_default: heartbeats 265, failed 147, closed 135, max_rec_depth 3
  - exact: closed_self 520, closed_other 30
  - apply: closed_self 520, closed_other 30
