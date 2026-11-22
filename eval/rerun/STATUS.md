# 7b full run: status

Updated 2026-11-22 22:09 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 22 of 23 (shard size 50)
- Goals done: 1123 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 462
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 5 goals, projected 0.1 h → finish about 2026-11-22 22:13; observed throughput 106.9 s per goal → about 2026-11-22 22:18

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 453 | 162 | 211 | 78 | 2 |
| r1b | B | 38 | 21 | 12 | 5 | 0 |

Proved at N: 1: 46, 2: 19, 3: 15, 4: 5, 5: 6, 8: 1

## Baselines so far

