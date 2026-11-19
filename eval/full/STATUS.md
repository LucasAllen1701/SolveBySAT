# 7b full run: status

Updated 2026-11-19 15:34 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 12 of 126 (shard size 50)
- Goals done: 600 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 20
- Crashes by cause: oom 182
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5700 goals, projected 31.8 h → finish about 2026-11-20 23:20; observed throughput 30.8 s per goal → about 2026-11-21 16:16

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 600 | 182 | 15 | 335 | 48 | 20 |

Proved at N: 1: 4, 2: 11, 3: 9, 4: 5, 5: 9, 6: 3, 7: 4, 8: 2, 9: 1

## Baselines so far

- Tier A (600 goals with baselines):
  - sbe_like: heartbeats 264, failed 169, closed 163, max_rec_depth 4
  - sbe_default: heartbeats 290, failed 160, closed 147, max_rec_depth 3
  - exact: closed_self 536, closed_other 35, none 29
  - apply: closed_self 536, closed_other 35, partial 29
