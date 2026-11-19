# 7b full run: status

Updated 2026-11-19 13:12 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 5 of 126 (shard size 50)
- Goals done: 250 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 5
- Crashes by cause: oom 129
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 6050 goals, projected 36.2 h → finish about 2026-11-21 01:22; observed throughput 42.1 s per goal → about 2026-11-22 12:01

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 250 | 129 | 8 | 96 | 12 | 5 |

Proved at N: 1: 2, 2: 4, 3: 1, 4: 2, 5: 2, 7: 1

## Baselines so far

- Tier A (250 goals with baselines):
  - sbe_like: heartbeats 149, closed 58, failed 42, max_rec_depth 1
  - sbe_default: heartbeats 164, closed 49, failed 36, max_rec_depth 1
  - exact: closed_self 239, closed_other 11
  - apply: closed_self 239, closed_other 11
