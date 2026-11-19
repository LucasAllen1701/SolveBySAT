# 7b full run: status

Updated 2026-11-20 00:14 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 31 of 126 (shard size 50)
- Goals done: 1573 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 36
- Crashes by cause: oom 509
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4727 goals, projected 23.9 h → finish about 2026-11-21 00:11; observed throughput 31.6 s per goal → about 2026-11-21 17:46

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1573 | 509 | 97 | 835 | 96 | 36 |

Proved at N: 1: 10, 2: 20, 3: 24, 4: 10, 5: 16, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1573 goals with baselines):
  - sbe_like: failed 641, heartbeats 548, closed 380, max_rec_depth 4
  - sbe_default: failed 610, heartbeats 602, closed 358, max_rec_depth 3
  - exact: closed_self 1385, none 96, closed_other 92
  - apply: closed_self 1385, partial 96, closed_other 92
