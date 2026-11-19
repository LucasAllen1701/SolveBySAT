# 7b full run: status

Updated 2026-11-20 02:22 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

- Shards done: 41 of 126 (shard size 50)
- Goals done: 2073 of 6300
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 40
- Crashes by cause: oom 583
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 4227 goals, projected 21.9 h → finish about 2026-11-21 00:15; observed throughput 27.6 s per goal → about 2026-11-21 10:47

## Outcomes so far

| run | tier | goals | crash(oom) | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 2073 | 583 | 221 | 1123 | 106 | 40 |

Proved at N: 1: 10, 2: 20, 3: 29, 4: 13, 5: 18, 6: 4, 7: 6, 8: 4, 9: 2

## Baselines so far

- Tier A (2073 goals with baselines):
  - sbe_like: failed 878, closed 605, heartbeats 586, max_rec_depth 4
  - sbe_default: failed 836, heartbeats 651, closed 583, max_rec_depth 3
  - exact: closed_self 1861, closed_other 114, none 98
  - apply: closed_self 1861, closed_other 114, partial 98
