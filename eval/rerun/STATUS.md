# 7b full run: status

Updated 2026-11-22 17:46 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 14 of 23 (shard size 50)
- Goals done: 723 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 330
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 405 goals, projected 4.7 h → finish about 2026-11-22 22:28; observed throughput 147.0 s per goal → about 2026-11-23 10:18

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 91 | 51 | 22 | 16 | 2 |

Proved at N: 1: 12, 2: 1, 3: 5, 4: 3, 5: 3, 8: 1

## Baselines so far

