# 7b full run: status

Updated 2026-11-19 14:27 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 9 of 126 (shard size 50)
- Goals done: 450 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 9
- Crashes by cause: oom 158
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5850 goals, projected 33.5 h → finish about 2026-11-20 23:55; observed throughput 32.3 s per goal → about 2026-11-21 18:56

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 450 | 158 | 10 | 241 | 32 | 9 |

Proved at N: 1: 2, 2: 9, 3: 5, 4: 3, 5: 6, 6: 2, 7: 3, 8: 1, 9: 1

## Baselines so far

- Tier A (450 goals with baselines):
  - sbe_like: heartbeats 210, failed 125, closed 113, max_rec_depth 2
  - sbe_default: heartbeats 228, failed 118, closed 102, max_rec_depth 2
  - exact: closed_self 423, closed_other 27
  - apply: closed_self 423, closed_other 27
