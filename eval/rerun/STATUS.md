# 7b full run: status

Updated 2026-11-22 15:18 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_rerun.jsonl`; P = 1; commit at start `3cd95d6b46`.

- Shards done: 10 of 23 (shard size 50)
- Goals done: 523 of 1128
- decoder_bug / solver_error / harness_error: 0
- Goals that hit a time limit (solver or loop timeout, watchdog): 4
- Crashes by cause: oom 242
- Driver wall time of finished driver runs: 0.00 h
- Remaining: 605 goals, projected 3.5 h → finish about 2026-11-22 18:51; observed throughput 190.5 s per goal → about 2026-11-23 23:19

## Outcomes so far

| run | tier | goals | crash(oom) | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- |
| main | A | 523 | 242 | 271 | 6 | 4 |

Proved at N: 1: 1, 3: 1, 4: 1, 5: 2, 8: 1

## Baselines so far

