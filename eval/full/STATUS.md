# 7b full run: status

Updated 2026-11-20 03:52 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 45 of 126 (shard size 50)
- Goals done: 2273 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 43
- Crashes by cause: oom 651
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4027 goals, projected 20.4 h → finish about 2026-11-21 00:13; observed throughput 27.5 s per goal → about 2026-11-21 10:40

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2273 | 651 | 236 | 1227 | 116 | 43 |

Proved at N: 1: 14, 2: 21, 3: 31, 4: 14, 5: 19, 6: 5, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2273 goals with baselines):
  - sbe_like: failed 969, heartbeats 651, closed 649, max_rec_depth 4
  - sbe_default: failed 921, heartbeats 723, closed 626, max_rec_depth 3
  - exact: closed_self 2015, none 133, closed_other 124, heartbeats 1
  - apply: closed_self 2015, partial 133, closed_other 124, heartbeats 1
