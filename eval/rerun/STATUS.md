# 7b full run: status

Updated 2026-11-22 16:30 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 12 of 23 (shard size 50)
- Goals done: 623 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 5
- Crashes by cause: oom 273
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 505 goals, projected 2.4 h → finish about 2026-11-22 18:52; observed throughput 164.7 s per goal → about 2026-11-23 15:36

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 623 | 273 | 337 | 8 | 5 |

Proved at N: 1: 1, 3: 2, 4: 2, 5: 2, 8: 1

## Baselines so far

