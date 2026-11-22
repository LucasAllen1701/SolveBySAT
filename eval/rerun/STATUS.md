# 7b full run: status

Updated 2026-11-22 21:35 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 21 of 23 (shard size 50)
- Goals done: 1073 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 441
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 55 goals, projected 0.3 h → finish about 2026-11-22 21:54; observed throughput 110.1 s per goal → about 2026-11-22 23:16

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 441 | 162 | 202 | 75 | 2 |

Proved at N: 1: 41, 2: 17, 3: 14, 4: 5, 5: 6, 8: 1

## Baselines so far

