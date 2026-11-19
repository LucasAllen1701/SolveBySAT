# 7b full run: status

Updated 2026-11-19 20:30 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 20 of 126 (shard size 50)
- Goals done: 1023 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 32
- Crashes by cause: oom 296
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5277 goals, projected 28.0 h → finish about 2026-11-21 00:27; observed throughput 35.6 s per goal → about 2026-11-22 00:44

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1023 | 296 | 27 | 577 | 91 | 32 |

Proved at N: 1: 10, 2: 19, 3: 24, 4: 10, 5: 14, 6: 4, 7: 5, 8: 3, 9: 2

## Baselines so far

- Tier A (1023 goals with baselines):
  - sbe_like: heartbeats 455, failed 297, closed 267, max_rec_depth 4
  - sbe_default: heartbeats 500, failed 277, closed 243, max_rec_depth 3
  - exact: closed_self 849, none 96, closed_other 78
  - apply: closed_self 849, partial 96, closed_other 78
