/-
Milestone 5 acceptance (SPEC §9: `∃ n : Nat, n ≤ n` with [Nat.le_refl, Nat.zero] in 3 nodes)
and the milestone 5 requirements, each success with its minimality check:
- D1: `∃ n : Nat, n ≤ n` with [Nat.le_refl, Nat.zero] in 3 nodes;
- D2: `∃ n : Nat, True` with [Nat.zero] in 3 nodes; "no proof" at 6 nodes with [];
- D3: `(Q : Nat → Prop) (q : ∀ m, Q (Nat.succ m)) : ∃ n, Q n` with [Nat.zero] in 3 nodes (a
  built argument of a hypothesis);
- D4: a built value with a built argument: `∃ i : Int, True` with [Int.ofNat, Nat.zero] in 4
  nodes (`Int.ofNat Nat.zero`);
- D5: A3 of milestone 3 with [Nat.zero, Nat.succ] still has no proof at 6 nodes;
- D6: the numeral limitation: `∃ n : Nat, Nat.succ n = 1` (true, `⟨0, rfl⟩`) has no proof
  at 6 nodes with [Nat.succ, Nat.zero, Eq.refl] (see NOTES.md);
- D7: `∃ n : Nat, n = 1` with [Eq.refl] in 2 nodes (the witness `1` is determined);
- E1–E3: an eigenvariable as a data clause is local to the goal position that introduced
  it (requirement 2);
- N1: universe levels are normalised: a lemma stated with `max u v` closes a goal stated
  with `max v u`.

Run: `lake env lean Test/M5Lean.lean` — success means no errors.
-/
import SolveBySat
set_option solve_by_sat.verbose true

/-! ## D1 -/

theorem D1 : ∃ n : Nat, n ≤ n := by
  solve_by_sat [Nat.le_refl, Nat.zero] (nodes := 3)

/-- info: theorem D1 : ∃ n, n ≤ n :=
Exists.intro Nat.zero (Nat.le_refl Nat.zero) -/
#guard_msgs in
#print D1

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example : ∃ n : Nat, n ≤ n := by
  solve_by_sat [Nat.le_refl, Nat.zero] (nodes := 2)

/-! ## D2 -/

example : ∃ n : Nat, True := by
  solve_by_sat [Nat.zero] (nodes := 3)

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example : ∃ n : Nat, True := by
  solve_by_sat [Nat.zero] (nodes := 2)

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example : ∃ n : Nat, True := by
  solve_by_sat [] (nodes := 6)

/-! ## D3 -/

theorem D3 (Q : Nat → Prop) (q : ∀ m, Q (Nat.succ m)) : ∃ n, Q n := by
  solve_by_sat [Nat.zero] (nodes := 3)

/-- info: theorem D3 : ∀ (Q : Nat → Prop), (∀ (m : Nat), Q m.succ) → ∃ n, Q n :=
fun Q q => Exists.intro Nat.zero.succ (q Nat.zero) -/
#guard_msgs in
#print D3

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (Q : Nat → Prop) (q : ∀ m, Q (Nat.succ m)) : ∃ n, Q n := by
  solve_by_sat [Nat.zero] (nodes := 2)

/-! ## D4: a built value with a built argument -/

theorem D4 : ∃ i : Int, True := by
  solve_by_sat [Int.ofNat, Nat.zero] (nodes := 4)

/-- info: theorem D4 : ∃ i, True :=
Exists.intro (Int.ofNat Nat.zero) True.intro -/
#guard_msgs in
#print D4

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
example : ∃ i : Int, True := by
  solve_by_sat [Int.ofNat, Nat.zero] (nodes := 3)

/-! ## D5: scope is unchanged by data constants -/

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example (R : Nat → Nat → Prop) (r : ∀ n, R n n) : ∃ x, ∀ y, R x y := by
  solve_by_sat [Nat.zero, Nat.succ] (nodes := 6)

/-! ## D6: the numeral limitation -/

-- True in Lean (`⟨0, rfl⟩`), but `Nat.succ ?n` never matches the numeral `1`
-- (`OfNat.ofNat Nat 1 _`) syntactically, and no unfolding is done.
example : ∃ n : Nat, Nat.succ n = 1 := ⟨0, rfl⟩

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example : ∃ n : Nat, Nat.succ n = 1 := by
  solve_by_sat [Nat.succ, Nat.zero, Eq.refl] (nodes := 6)

/-! ## D7: a numeral witness determined by unification (formerly Test/M5Pending.lean) -/

-- `Eq.refl` forces the witness to equal `1`, which occurs in the statement, so it is a
-- determined argument (SPEC §2.2), as in L7: nothing is built.
theorem D7 : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 2)

/-- info: theorem D7 : ∃ n, n = 1 :=
Exists.intro 1 (Eq.refl 1) -/
#guard_msgs in
#print D7

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 1)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 2 nodes, more than N = 1
---
error: solve_by_sat: no proof with at most 1 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example : ∃ n : Nat, n = 1 := by
  solve_by_sat [Eq.refl] (nodes := 1)

/-! ## E1–E3: eigenvariables as data clauses obey the context rules (6.3) -/

-- E1: `f` is introduced at the root, so the witness `f Nat.zero` can be built.
theorem E1 : ∀ f : Nat → Int, ∃ i : Int, True := by
  solve_by_sat [Nat.zero] (nodes := 4)

/-- info: theorem E1 : ∀ (f : Nat → Int), ∃ i, True :=
fun f => Exists.intro (f Nat.zero) True.intro -/
#guard_msgs in
#print E1

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
example : ∀ f : Nat → Int, ∃ i : Int, True := by
  solve_by_sat [Nat.zero] (nodes := 3)

-- E2: `f` is introduced in the left branch only; the right branch cannot use it.
/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example : (∀ f : Nat → Int, True) ∧ ∃ i : Int, True := by
  solve_by_sat [Nat.zero] (nodes := 6)

-- E3: the same conjunction with `f` in the context of the whole goal.
example (f : Nat → Int) : (∀ g : Nat → Int, True) ∧ ∃ i : Int, True := by
  solve_by_sat [Nat.zero] (nodes := 6)

/-! ## N1: universe levels are normalised -/

universe u v
theorem maxL (f : Sort (max u v) → Sort u) : f = f := rfl

example (f : Sort (max v u) → Sort u) : f = f := by
  solve_by_sat [maxL] (nodes := 1)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (f : Sort (max v u) → Sort u) : f = f := by
  solve_by_sat [maxL] (nodes := 0)
