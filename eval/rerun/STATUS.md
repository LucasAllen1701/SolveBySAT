# 7b full run: status

Updated 2026-11-22 18:18 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 15 of 23 (shard size 50)
- Goals done: 773 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 353
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 355 goals, projected 3.8 h → finish about 2026-11-22 22:09; observed throughput 139.5 s per goal → about 2026-11-23 08:03

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 141 | 74 | 34 | 31 | 2 |

Proved at N: 1: 19, 2: 5, 3: 7, 4: 4, 5: 4, 8: 1

## Baselines so far

