# 7b full run: status

Updated 2026-11-19 14:06 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 8 of 126 (shard size 50)
- Goals done: 400 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 8
- Crashes by cause: oom 148
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5900 goals, projected 34.0 h → finish about 2026-11-21 00:07; observed throughput 33.2 s per goal → about 2026-11-21 20:35

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 400 | 148 | 10 | 213 | 21 | 8 |

Proved at N: 1: 2, 2: 6, 3: 3, 4: 3, 5: 3, 6: 1, 7: 2, 8: 1

## Baselines so far

- Tier A (400 goals with baselines):
  - sbe_like: heartbeats 190, failed 107, closed 101, max_rec_depth 2
  - sbe_default: heartbeats 208, failed 100, closed 90, max_rec_depth 2
  - exact: closed_self 378, closed_other 22
  - apply: closed_self 378, closed_other 22
