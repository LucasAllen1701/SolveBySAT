# 7b full run: status

Updated 2026-11-19 17:00 (machine time). Specs: `/home/tom/SolveBySAT/eval/specs_full.jsonl`; P = 1; commit at start `6ef9ea207a`.

**Driver ended: STOPPED: decoder bug or solver error (see results.jsonl).**


- Shards done: 15 of 126 (shard size 50)
- Goals done: 774 of 6300
- decoder_bug / solver_error / harness_error: 1
- Goals that hit a time limit (solver or loop timeout, watchdog): 22
- Crashes by cause: oom 233
- Driver wall time of finished driver runs: 6.75 h
- Remaining: 5526 goals, projected 30.2 h → finish about 2026-11-20 23:11; observed throughput 30.5 s per goal → about 2026-11-21 15:50

## Outcomes so far

| run | tier | goals | crash(oom) | decoder_bug | goal_rejected | no_proof_le_Nmax | proved | timeout(solver) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| main | A | 774 | 233 | 1 | 23 | 432 | 63 | 22 |

Proved at N: 1: 6, 2: 13, 3: 16, 4: 8, 5: 9, 6: 3, 7: 4, 8: 3, 9: 1

## Baselines so far

- Tier A (774 goals with baselines):
  - sbe_like: heartbeats 333, failed 231, closed 206, max_rec_depth 4
  - sbe_default: heartbeats 368, failed 217, closed 186, max_rec_depth 3
  - exact: closed_self 622, none 95, closed_other 57
  - apply: closed_self 622, partial 95, closed_other 57

**decoder_bug** on `main:A/List.getLast_eq_head_reverse`: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun α#0 l#1 h => Eq.symm(List.head_reverse(fun a0@g5 => h(List.reverse_eq_nil_iff.mp(a0@g5))))
error: Tactic `introN` failed: The metavariable below has already been assigned

Note: This likely indicates an internal error in this tactic or a prior one

case h
α✝ : Type u_1
l✝ : List α✝
h✝ : l✝ = [] → False
⊢ l✝.reverse = [] → False
