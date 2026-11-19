# 7b full run: status

Updated 2026-11-19 13:48 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 7 of 126 (shard size 50)
- Goals done: 350 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 8
- Crashes by cause: oom 143
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5950 goals, projected 34.9 h → finish about 2026-11-21 00:42; observed throughput 35.2 s per goal → about 2026-11-21 23:58

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 350 | 143 | 10 | 171 | 18 | 8 |

Proved at N: 1: 2, 2: 5, 3: 3, 4: 3, 5: 3, 6: 1, 7: 1

## Baselines so far

- Tier A (350 goals with baselines):
  - sbe_like: heartbeats 173, closed 97, failed 78, max_rec_depth 2
  - sbe_default: heartbeats 189, closed 87, failed 72, max_rec_depth 2
  - exact: closed_self 335, closed_other 15
  - apply: closed_self 335, closed_other 15
