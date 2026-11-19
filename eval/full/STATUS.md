# 7b full run: status

Updated 2026-11-20 01:50 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 40 of 126 (shard size 50)
- Goals done: 2023 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 570
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4277 goals, projected 22.3 h → finish about 2026-11-21 00:07; observed throughput 27.3 s per goal → about 2026-11-21 10:19

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2023 | 570 | 217 | 1093 | 106 | 37 |

Proved at N: 1: 10, 2: 20, 3: 29, 4: 13, 5: 18, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2023 goals with baselines):
  - sbe_like: failed 855, closed 601, heartbeats 563, max_rec_depth 4
  - sbe_default: failed 816, heartbeats 625, closed 579, max_rec_depth 3
  - exact: closed_self 1813, closed_other 112, none 98
  - apply: closed_self 1813, closed_other 112, partial 98
