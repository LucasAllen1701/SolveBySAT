# 7b full run: status

Updated 2026-11-20 23:13 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 99 of 126 (shard size 50)
- Goals done: 4995 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 71
- Crashes by cause: oom 1181
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 1305 goals, projected 6.3 h → finish about 2026-11-21 05:31; observed throughput 26.5 s per goal → about 2026-11-21 08:48

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 272 | 1711 | 140 | 58 |
| main | B | 1995 | 362 | 179 | 883 | 558 | 13 |

Proved at N: 1: 375, 2: 138, 3: 84, 4: 41, 5: 31, 6: 10, 7: 10, 8: 6, 9: 3

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1995 goals with baselines):
  - sbe_like: closed 1340, heartbeats 334, failed 317, max_rec_depth 4
  - sbe_default: closed 1260, heartbeats 481, failed 250, max_rec_depth 4
  - exact: none 934, closed_other 842, closed_self 213, max_rec_depth 4, heartbeats 2
  - apply: partial 934, closed_other 842, closed_self 213, max_rec_depth 4, heartbeats 2
