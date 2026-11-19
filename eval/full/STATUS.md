# 7b full run: status

Updated 2026-11-20 00:28 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 32 of 126 (shard size 50)
- Goals done: 1623 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 36
- Crashes by cause: oom 515
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4677 goals, projected 23.7 h → finish about 2026-11-21 00:12; observed throughput 31.1 s per goal → about 2026-11-21 16:55

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 1623 | 515 | 101 | 873 | 98 | 36 |

Proved at N: 1: 10, 2: 20, 3: 25, 4: 10, 5: 17, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (1623 goals with baselines):
  - sbe_like: failed 661, heartbeats 552, closed 406, max_rec_depth 4
  - sbe_default: failed 630, heartbeats 606, closed 384, max_rec_depth 3
  - exact: closed_self 1433, none 98, closed_other 92
  - apply: closed_self 1433, partial 98, closed_other 92
