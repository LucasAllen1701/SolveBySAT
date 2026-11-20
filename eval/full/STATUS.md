# 7b full run: status

Updated 2026-11-20 19:51 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 86 of 126 (shard size 50)
- Goals done: 4345 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 70
- Crashes by cause: oom 1023
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1955 goals, projected 8.6 h → finish about 2026-11-21 04:29; observed throughput 27.7 s per goal → about 2026-11-21 10:52

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1345 | 204 | 87 | 657 | 385 | 12 |

Proved at N: 1: 307, 2: 74, 3: 62, 4: 30, 5: 27, 6: 7, 7: 9, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1345 goals with baselines):
  - sbe_like: closed 908, heartbeats 262, failed 171, max_rec_depth 4
  - sbe_default: closed 846, heartbeats 370, failed 125, max_rec_depth 4
  - exact: none 612, closed_other 574, closed_self 155, max_rec_depth 4
  - apply: partial 612, closed_other 574, closed_self 155, max_rec_depth 4
