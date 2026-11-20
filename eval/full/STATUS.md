# 7b full run: status

Updated 2026-11-21 02:25 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 114 of 126 (shard size 50)
- Goals done: 5745 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 72
- Crashes by cause: oom 1292
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 555 goals, projected 3.0 h → finish about 2026-11-21 05:24; observed throughput 25.0 s per goal → about 2026-11-21 06:16

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 2745 | 473 | 242 | 1255 | 761 | 14 |

Proved at N: 1: 495, 2: 184, 3: 109, 4: 47, 5: 33, 6: 12, 7: 11, 8: 7, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (2745 goals with baselines):
  - sbe_like: closed 1890, failed 444, heartbeats 407, max_rec_depth 4
  - sbe_default: closed 1809, heartbeats 589, failed 343, max_rec_depth 4
  - exact: closed_other 1243, none 1197, closed_self 294, heartbeats 6, max_rec_depth 5
  - apply: closed_other 1243, partial 1197, closed_self 294, heartbeats 6, max_rec_depth 5
