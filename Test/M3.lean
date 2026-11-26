/-
Milestone 3 acceptance (SPEC §9.2): L5 to L8 succeed; F1 fails as expected; the node
counts of L5 to L8 are minimal, so each fails with one node fewer.

Tests for the milestone 3 amendments (NOTES.md):
- A1: every target and head is also an opaque atom: `(h : A ∨ B) : A ∨ B` and
  `(h : A ∧ B) : A ∧ B` in 1 node;
- A2: a root hypothesis that is not a clause is introduced but gives no clause;
- A3: scope without universe polymorphism: `∃ x, ∀ y, R x y` has no proof (6 nodes),
  `∀ y, ∃ x, R x y` has one;
- A4: decoder grounding: a grounded variable whose value contains another grounded
  variable; a grounding to a ground term that contains a proof of a hypothesis.

Run: `lake env lean Test/M3.lean` — success means no errors.
-/
import SolveBySat
set_option solve_by_sat.verbose true

/-! ## L5 to L8 -/

-- L5: conjunction, 3 nodes
example (A B : Prop) (ha : A) (hb : B) : A ∧ B := by
  solve_by_sat [] (nodes := 3)
-- L6: disjunction, 2 nodes
example (A B : Prop) (hb : B) : A ∨ B := by
  solve_by_sat [] (nodes := 2)
-- L7: existential with a forced witness, 2 nodes
example (a b : Nat) (h : a ≤ b) : ∃ x, x ≤ b := by
  solve_by_sat [] (nodes := 2)
-- L8: conjunctive hypothesis through a projection, 1 node
example (A B : Prop) (h : A ∧ B) : B := by
  solve_by_sat [] (nodes := 1)

/-! ## F1 (verbatim from the spec, then with the exact message) -/

-- F1: hypothesis out of scope
example (A : Prop) : (A → A) ∧ A := by
  fail_if_success solve_by_sat [] (nodes := 6)
  sorry

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example (A : Prop) : (A → A) ∧ A := by
  solve_by_sat [] (nodes := 6)

/-! ## Minimality of L5 to L8 -/

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (A B : Prop) (ha : A) (hb : B) : A ∧ B := by
  solve_by_sat [] (nodes := 2)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 3 nodes, more than N = 2
---
error: solve_by_sat: no proof with at most 2 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (A B : Prop) (ha : A) (hb : B) : A ∧ B := by
  solve_by_sat [] (nodes := 2)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (A B : Prop) (hb : B) : A ∨ B := by
  solve_by_sat [] (nodes := 1)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 2 nodes, more than N = 1
---
error: solve_by_sat: no proof with at most 1 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (A B : Prop) (hb : B) : A ∨ B := by
  solve_by_sat [] (nodes := 1)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (a b : Nat) (h : a ≤ b) : ∃ x, x ≤ b := by
  solve_by_sat [] (nodes := 1)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 2 nodes, more than N = 1
---
error: solve_by_sat: no proof with at most 1 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (a b : Nat) (h : a ≤ b) : ∃ x, x ≤ b := by
  solve_by_sat [] (nodes := 1)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (A B : Prop) (h : A ∧ B) : B := by
  solve_by_sat [] (nodes := 0)

/-! ## A1: opaque atoms -/

-- A1a: a hypothesis with an `∨` head is a clause with that opaque head.
example (A B : Prop) (h : A ∨ B) : A ∨ B := by
  solve_by_sat [] (nodes := 1)
-- A1b: an `∧` head gives the split clauses and the opaque one.
example (A B : Prop) (h : A ∧ B) : A ∧ B := by
  solve_by_sat [] (nodes := 1)
-- A1c: an `∃` head is kept opaque (needs a `fun` in the template), and a `↔` head is
-- split into `Iff.mp`/`Iff.mpr` clauses.
example (P : Nat → Prop) (h : ∃ x, P x) : ∃ x, P x := by
  solve_by_sat [] (nodes := 1)
example (A B : Prop) (h : A ↔ B) (ha : A) : B := by
  solve_by_sat [] (nodes := 2)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (A B : Prop) (h : A ∨ B) : A ∨ B := by
  solve_by_sat [] (nodes := 0)

/-! ## A2: a root hypothesis that is not a clause -/

-- `bad` is introduced (it is a binder of the goal) but gives no clause; the note is shown
-- under `solve_by_sat.verbose`.
example (A : Prop) (bad : ∀ f : Nat → Nat, f 0 = 0) (ha : A) : A := by
  solve_by_sat [] (nodes := 1)

/-! ## A3: eigenvariable scope without universe polymorphism -/

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example (R : Nat → Nat → Prop) (r : ∀ n, R n n) : ∃ x, ∀ y, R x y := by
  solve_by_sat [] (nodes := 6)

example (R : Nat → Nat → Prop) (r : ∀ n, R n n) : ∀ y, ∃ x, R x y := by
  solve_by_sat [] (nodes := 2)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (R : Nat → Nat → Prop) (r : ∀ n, R n n) : ∀ y, ∃ x, R x y := by
  solve_by_sat [] (nodes := 1)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 2 nodes, more than N = 1
---
error: solve_by_sat: no proof with at most 1 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (R : Nat → Nat → Prop) (r : ∀ n, R n n) : ∀ y, ∃ x, R x y := by
  solve_by_sat [] (nodes := 1)

/-! ## A4: decoder grounding -/

-- A4a: `y : Int` and `u : Nat` are determined by no equation. The only Int-typed
-- candidate is the rigid object `g u` in the premise target `R (g u)`, so the model
-- grounds `y` to `g u`, whose value contains the still-open `u`; a later round grounds
-- `u` to `k`. The term printed below must be `h (g k) k (q (g k)) (r (g k))`.
theorem A4a (g : Nat → Int) (k : Nat) (Q R : Int → Prop) (P0 : Prop)
    (h : ∀ (y : Int) (u : Nat), Q y → R (g u) → P0) (q : ∀ y', Q y') (r : ∀ t, R t) : P0 := by
  solve_by_sat [] (nodes := 3)
#print A4a

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (g : Nat → Int) (k : Nat) (Q R : Int → Prop) (P0 : Prop)
    (h : ∀ (y : Int) (u : Nat), Q y → R (g u) → P0) (q : ∀ y', Q y') (r : ∀ t, R t) : P0 := by
  solve_by_sat [] (nodes := 2)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 3 nodes, more than N = 2
---
error: solve_by_sat: no proof with at most 2 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (g : Nat → Int) (k : Nat) (Q R : Int → Prop) (P0 : Prop)
    (h : ∀ (y : Int) (u : Nat), Q y → R (g u) → P0) (q : ∀ y', Q y') (r : ∀ t, R t) : P0 := by
  solve_by_sat [] (nodes := 2)

-- A4b: `s` (at the nodes of `h` and `q`) is grounded to `⟨3, hp⟩`, a ground term that
-- contains the proof `hp` of a hypothesis; its expression is read from the replayed root
-- target. The term printed below must use `⟨3, hp⟩` for `s`.
theorem A4b (R0 : Prop) (Q T : {x : Nat // x = 3} → Prop) (hp : 3 = 3)
    (h : ∀ s, Q s → R0) (q : ∀ s, Q s) (t : ∀ s, T s) : R0 ∧ T ⟨3, hp⟩ := by
  solve_by_sat [] (nodes := 4)
#print A4b

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (R0 : Prop) (Q T : {x : Nat // x = 3} → Prop) (hp : 3 = 3)
    (h : ∀ s, Q s → R0) (q : ∀ s, Q s) (t : ∀ s, T s) : R0 ∧ T ⟨3, hp⟩ := by
  solve_by_sat [] (nodes := 3)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: early exit (node bounds): every proof has at least 4 nodes, more than N = 3
---
error: solve_by_sat: no proof with at most 3 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.nodeBounds true in
example (R0 : Prop) (Q T : {x : Nat // x = 3} → Prop) (hp : 3 = 3)
    (h : ∀ s, Q s → R0) (q : ∀ s, Q s) (t : ∀ s, T s) : R0 ∧ T ⟨3, hp⟩ := by
  solve_by_sat [] (nodes := 3)
