# 7b full run: status

Updated 2026-11-20 13:30 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 77 of 126 (shard size 50)
- Goals done: 3873 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 64
- Crashes by cause: oom 940
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 2427 goals, projected 11.2 h → finish about 2026-11-21 00:44; observed throughput 25.1 s per goal → about 2026-11-21 06:25

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 873 | 121 | 70 | 443 | 233 | 6 |

Proved at N: 1: 204, 2: 48, 3: 47, 4: 27, 5: 24, 6: 6, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (873 goals with baselines):
  - sbe_like: closed 601, heartbeats 161, failed 107, max_rec_depth 4
  - sbe_default: closed 558, heartbeats 235, failed 76, max_rec_depth 4
  - exact: none 415, closed_other 366, closed_self 88, max_rec_depth 4
  - apply: partial 415, closed_other 366, closed_self 88, max_rec_depth 4
