# 7b full run: status

Updated 2026-11-19 21:19 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 22 of 126 (shard size 50)
- Goals done: 1123 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 35
- Crashes by cause: oom 317
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5177 goals, projected 27.4 h → finish about 2026-11-21 00:45; observed throughput 35.1 s per goal → about 2026-11-21 23:43

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1123 | 317 | 32 | 646 | 93 | 35 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 14, 6: 4, 7: 6, 8: 3, 9: 2

## Baselines so far

- Tier A (1123 goals with baselines):
  - sbe_like: heartbeats 491, failed 331, closed 297, max_rec_depth 4
  - sbe_default: heartbeats 540, failed 306, closed 274, max_rec_depth 3
  - exact: closed_self 947, none 96, closed_other 80
  - apply: closed_self 947, partial 96, closed_other 80
