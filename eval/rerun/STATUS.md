# 7b full run: status

Updated 2026-11-22 21:04 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 20 of 23 (shard size 50)
- Goals done: 1023 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 427
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 105 goals, projected 0.9 h → finish about 2026-11-22 21:55; observed throughput 113.9 s per goal → about 2026-11-23 00:23

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 391 | 148 | 173 | 68 | 2 |

Proved at N: 1: 35, 2: 17, 3: 13, 4: 5, 5: 6, 8: 1

## Baselines so far

