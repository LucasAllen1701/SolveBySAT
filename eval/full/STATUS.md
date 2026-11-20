# 7b full run: status

Updated 2026-11-20 22:20 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 95 of 126 (shard size 50)
- Goals done: 4795 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1142
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1505 goals, projected 7.1 h → finish about 2026-11-21 05:28; observed throughput 26.9 s per goal → about 2026-11-21 09:35

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1795 | 323 | 148 | 804 | 507 | 13 |

Proved at N: 1: 362, 2: 111, 3: 79, 4: 38, 5: 29, 6: 9, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1795 goals with baselines):
  - sbe_like: closed 1215, heartbeats 315, failed 261, max_rec_depth 4
  - sbe_default: closed 1136, heartbeats 455, failed 200, max_rec_depth 4
  - exact: none 843, closed_other 751, closed_self 195, max_rec_depth 4, heartbeats 2
  - apply: partial 843, closed_other 751, closed_self 195, max_rec_depth 4, heartbeats 2
