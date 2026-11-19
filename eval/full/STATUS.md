# 7b full run: status

Updated 2026-11-20 01:03 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 36 of 126 (shard size 50)
- Goals done: 1823 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 37
- Crashes by cause: oom 541
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4477 goals, projected 22.8 h → finish about 2026-11-20 23:49; observed throughput 28.8 s per goal → about 2026-11-21 12:52

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1823 | 541 | 182 | 959 | 104 | 37 |

Proved at N: 1: 10, 2: 20, 3: 28, 4: 13, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1823 goals with baselines):
  - sbe_like: failed 777, heartbeats 560, closed 482, max_rec_depth 4
  - sbe_default: failed 745, heartbeats 615, closed 460, max_rec_depth 3
  - exact: closed_self 1628, none 98, closed_other 97
  - apply: closed_self 1628, partial 98, closed_other 97
