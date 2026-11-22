# 7b full run: status

Updated 2026-11-22 19:18 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 17 of 23 (shard size 50)
- Goals done: 873 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 375
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 255 goals, projected 2.5 h → finish about 2026-11-22 21:46; observed throughput 126.9 s per goal → about 2026-11-23 04:18

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 241 | 96 | 100 | 43 | 2 |

Proved at N: 1: 27, 2: 6, 3: 8, 4: 5, 5: 5, 8: 1

## Baselines so far

