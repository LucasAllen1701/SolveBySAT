# 7b full run: status

Updated 2026-11-22 19:53 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 18 of 23 (shard size 50)
- Goals done: 923 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 393
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 205 goals, projected 1.9 h → finish about 2026-11-22 21:45; observed throughput 122.1 s per goal → about 2026-11-23 02:50

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 291 | 114 | 124 | 51 | 2 |

Proved at N: 1: 30, 2: 8, 3: 11, 4: 5, 5: 5, 8: 1

## Baselines so far

