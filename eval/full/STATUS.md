# 7b full run: status

Updated 2026-11-19 13:25 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 6 of 126 (shard size 50)
- Goals done: 300 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 6
- Crashes by cause: oom 136
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 6000 goals, projected 35.6 h → finish about 2026-11-21 00:58; observed throughput 36.7 s per goal → about 2026-11-22 02:31

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 300 | 136 | 10 | 132 | 16 | 6 |

Proved at N: 1: 2, 2: 5, 3: 3, 4: 3, 5: 2, 7: 1

## Baselines so far

- Tier A (300 goals with baselines):
  - sbe_like: heartbeats 155, closed 87, failed 57, max_rec_depth 1
  - sbe_default: heartbeats 170, closed 78, failed 51, max_rec_depth 1
  - exact: closed_self 286, closed_other 14
  - apply: closed_self 286, closed_other 14
