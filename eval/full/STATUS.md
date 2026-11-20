# 7b full run: status

Updated 2026-11-20 15:38 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

**Driver ended: STOPPED: decoder bug or solver error (see results.jsonl).**


- Shards done: 84 of 126 (shard size 50)
- Goals done: 4246 of 6300
- decoder_bug / solver_error / harness_error: 1
- Goals that hit a time limit (solver or loop timeout, watchdog): 68
- Crashes by cause: oom 1010
- Driver wall time of finished driver runs: 28.24 h
- Remaining: 2054 goals, projected 9.2 h → finish about 2026-11-21 00:53; observed throughput 24.7 s per goal → about 2026-11-21 05:43

## Outcomes so far

| run | tier | goals | crash(oom) | decoder_bug | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 3000 | 819 | 0 | 272 | 1711 | 140 | 58 |
| main | B | 1246 | 191 | 1 | 86 | 606 | 352 | 10 |

Proved at N: 1: 286, 2: 68, 3: 59, 4: 28, 5: 27, 6: 7, 7: 9, 8: 6, 9: 2

## Baselines so far

- Tier A (3000 goals with baselines):
  - sbe_like: failed 1137, closed 977, heartbeats 875, max_rec_depth 11
  - sbe_default: failed 1076, heartbeats 971, closed 943, max_rec_depth 10
  - exact: closed_self 2655, none 182, closed_other 159, heartbeats 2, max_rec_depth 2
  - apply: closed_self 2655, partial 182, closed_other 159, heartbeats 2, max_rec_depth 2
- Tier B (1246 goals with baselines):
  - sbe_like: closed 849, heartbeats 236, failed 157, max_rec_depth 4
  - sbe_default: closed 787, heartbeats 338, failed 117, max_rec_depth 4
  - exact: none 569, closed_other 533, closed_self 140, max_rec_depth 4
  - apply: partial 569, closed_other 533, closed_self 140, max_rec_depth 4

**decoder_bug** on `main:B/Nat.pred_eq_self_iff/22`: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun n#0 n#1 x_0#2 x_0#3 h2@g0 a5@g0 => Ne.symm(fun a0@g2 => Nat.succ_ne_self(a0@g2), a5@g0)
error: node 3: the head ?a = ?b of a0@g2 does not unify with the target Nat.succ ?n = ?n
