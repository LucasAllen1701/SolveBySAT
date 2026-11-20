# 7b full run: status

Updated 2026-11-20 11:38 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 68 of 126 (shard size 50)
- Goals done: 3423 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 61
- Crashes by cause: oom 911
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2877 goals, projected 14.5 h → finish about 2026-11-21 02:11; observed throughput 26.4 s per goal → about 2026-11-21 08:45

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 423 | 92 | 28 | 185 | 115 | 3 |

Proved at N: 1: 110, 2: 38, 3: 41, 4: 24, 5: 22, 6: 6, 7: 8, 8: 4, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (423 goals with baselines):
  - sbe_like: closed 299, heartbeats 84, failed 40
  - sbe_default: closed 279, heartbeats 116, failed 28
  - exact: closed_other 193, none 182, closed_self 48
  - apply: closed_other 193, partial 182, closed_self 48
