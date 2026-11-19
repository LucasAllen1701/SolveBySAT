# 7b full run: status

Updated 2026-11-20 06:28 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 53 of 126 (shard size 50)
- Goals done: 2673 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 48
- Crashes by cause: oom 743
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 3627 goals, projected 18.1 h → finish about 2026-11-21 00:31; observed throughput 26.9 s per goal → about 2026-11-21 09:34

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2673 | 743 | 261 | 1493 | 128 | 48 |

Proved at N: 1: 15, 2: 22, 3: 34, 4: 19, 5: 20, 6: 6, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2673 goals with baselines):
  - sbe_like: failed 1074, closed 851, heartbeats 742, max_rec_depth 6
  - sbe_default: failed 1021, heartbeats 825, closed 822, max_rec_depth 5
  - exact: closed_self 2400, closed_other 139, none 133, heartbeats 1
  - apply: closed_self 2400, closed_other 139, partial 133, heartbeats 1
