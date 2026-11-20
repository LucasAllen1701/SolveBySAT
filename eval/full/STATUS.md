# 7b full run: status

Updated 2026-11-20 12:00 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 70 of 126 (shard size 50)
- Goals done: 3523 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 61
- Crashes by cause: oom 915
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2777 goals, projected 13.4 h → finish about 2026-11-21 01:24; observed throughput 26.1 s per goal → about 2026-11-21 08:06

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 523 | 96 | 35 | 247 | 142 | 3 |

Proved at N: 1: 129, 2: 42, 3: 43, 4: 25, 5: 22, 6: 6, 7: 8, 8: 5, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (523 goals with baselines):
  - sbe_like: closed 365, heartbeats 99, failed 59
  - sbe_default: closed 338, heartbeats 143, failed 42
  - exact: none 232, closed_other 229, closed_self 62
  - apply: partial 232, closed_other 229, closed_self 62
