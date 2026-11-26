/-
Milestone 8c-1 (M8_PLAN 3.4.3, 3.4.5, 4.4): R1's early exit and the model check, through the tactic.

- With `solve_by_sat.nodeBounds`, a call whose N is below the least proof size s(root) fails at once
  with the usual no-proof message; with `verbose` it says why. Without R1 (the flag off, or every
  refinement off) the same call fails with the same message after solving, and says nothing more.
- A goal no clause can ever prove has s(root) = ∞.
- `solve_by_sat.checkBounds` (testing only) checks every node of a decoded proof against R1's bounds;
  a proof found with R1 off passes it.

Run: `lake env lean Test/M8C1Lean.lean` — success means no errors.
-/
import SolveBySat

/-! ## The early exit -/

-- `∃ n, n = 1` needs 2 nodes (`Exists.intro`, then `Eq.refl`), so s(root) = 2 > 1
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 2 nodes, more than N = 1
---
error: solve_by_sat: no proof with at most 1 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
set_option solve_by_sat.verbose true in
example : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 1)

-- the same call without R1: the same failure, found by the solver, and no early-exit line
/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.verbose true in
example : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 1)

-- `solve_by_sat.refinements := false` switches R1 off too
/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
set_option solve_by_sat.refinements false in
set_option solve_by_sat.verbose true in
example : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 1)

-- at N = 2 R1 does not exit early, and the proof is found
set_option solve_by_sat.nodeBounds true in
example : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 2)

-- no clause matches `False`: s(root) is infinite
/--
info: solve_by_sat: early exit (node bounds): no proof tree exists at any N
---
error: solve_by_sat: no proof with at most 3 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
set_option solve_by_sat.verbose true in
example : False := by
  solve_by_sat [] (nodes := 3)

/-! ## The model check -/

-- L1 (SPEC 9.2): a proof of exactly 5 nodes, found with R1 off, satisfies the bounds
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.checkBounds true in
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)

-- and with R1 and R2 on
set_option solve_by_sat.nodeBounds true in
set_option solve_by_sat.exclusivePairs true in
set_option solve_by_sat.checkBounds true in
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)

-- with R1, one node fewer than L1's minimal 5 is still UNSAT (the size bound is not too tight)
/-- error: solve_by_sat: no proof with at most 4 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 4)
