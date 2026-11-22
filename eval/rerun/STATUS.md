# 7b full run: status

Updated 2026-11-22 20:37 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 19 of 23 (shard size 50)
- Goals done: 973 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 419
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 155 goals, projected 1.4 h → finish about 2026-11-22 22:03; observed throughput 118.3 s per goal → about 2026-11-23 01:43

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 341 | 140 | 142 | 57 | 2 |

Proved at N: 1: 32, 2: 12, 3: 11, 4: 5, 5: 5, 8: 1

## Baselines so far

