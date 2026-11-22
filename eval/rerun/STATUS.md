# 7b full run: status

Updated 2026-11-22 16:58 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 13 of 23 (shard size 50)
- Goals done: 673 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 7
- Crashes by cause: oom 291
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 455 goals, projected 3.5 h → finish about 2026-11-22 20:25; observed throughput 154.2 s per goal → about 2026-11-23 12:27

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 632 | 279 | 339 | 9 | 5 |
| main | B | 41 | 12 | 19 | 8 | 2 |

Proved at N: 1: 7, 3: 4, 4: 2, 5: 3, 8: 1

## Baselines so far

