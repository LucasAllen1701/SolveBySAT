/-
Milestone 9a-1 (M9_PLAN 2.1, 2.2): `↔` as equations, through the tactic.

With `iffEq` (the option `solve_by_sat.iffEq`, or `(iffEq := true)` in the call), every clause with
an `↔` head `L ↔ R`, on any split path, also gives a clause with head `L = R` (recipe `propext`)
and one with head `R = L` (recipe `Eq.symm (propext _)`).

- Each test of 2.2 is proved at N = 1, the least N (at N = 0 the class has no proof, checked
  below), and `#print` shows the one-node recipe.
- With `iffEq` off, each fails with the no-proof message, at the default N = 8.
- The mutation check: with the two recipes swapped (`solve_by_sat.iffEqMutant`, testing only),
  each fails with a decoder error, never with a proof.
- `verbose` reports the number of paths added (when there are any), from H and from local hypotheses,
  and the paths dropped because they cannot be compiled.

The "off" tests set `solve_by_sat.iffEq false` explicitly, so that the file also passes when the
whole Lean suite is run with `-Dsolve_by_sat.iffEq=true` (`Test/m9a1_lean.sh`).

Run: `lake env lean Test/M9Lean.lean` — success means no errors.
-/
import SolveBySat

-- the option is off by default (M9_PLAN 1, owner decision 4)
#guard !(SolveBySat.CompileOptions.iffEq {})
#guard !SolveBySat.solve_by_sat.iffEq.defValue

/-! ## The tests of M9_PLAN 2.2 -/

-- `(¬ a ≤ b) = (b < a)` from `Nat.not_le`: the `L = R` path
theorem m9_not_le (a b : Nat) : (¬ a ≤ b) = (b < a) := by
  solve_by_sat [Nat.not_le] (nodes := 1) (iffEq := true)

/--
info: theorem m9_not_le : ∀ (a b : Nat), (¬a ≤ b) = (b < a) :=
fun a b => propext Nat.not_le
-/
#guard_msgs in
#print m9_not_le

-- the sides swapped: the `R = L` path, one node (no `Eq.symm` node)
theorem m9_not_le_symm (a b : Nat) : (b < a) = (¬ a ≤ b) := by
  solve_by_sat [Nat.not_le] (nodes := 1) (iffEq := true)

/--
info: theorem m9_not_le_symm : ∀ (a b : Nat), (b < a) = ¬a ≤ b :=
fun a b => Eq.symm (propext Nat.not_le)
-/
#guard_msgs in
#print m9_not_le_symm

-- a local hypothesis, both sides
theorem m9_local (A B : Prop) (h : A ↔ B) : A = B := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

theorem m9_local_symm (A B : Prop) (h : A ↔ B) : B = A := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/--
info: theorem m9_local : ∀ (A B : Prop), (A ↔ B) → A = B :=
fun A B h => propext h
-/
#guard_msgs in
#print m9_local

/--
info: theorem m9_local_symm : ∀ (A B : Prop), (A ↔ B) → B = A :=
fun A B h => Eq.symm (propext h)
-/
#guard_msgs in
#print m9_local_symm

-- a nested path: the `↔` is the right component of an `∧` head
theorem m9_nested (A B C : Prop) (h : C ∧ (A ↔ B)) : A = B := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/--
info: theorem m9_nested : ∀ (A B C : Prop), C ∧ (A ↔ B) → A = B :=
fun A B C h => propext h.right
-/
#guard_msgs in
#print m9_nested

-- a quantified lemma
theorem m9_forall (P Q : Nat → Prop) (h : ∀ x : Nat, P x ↔ Q x) : P 0 = Q 0 := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/--
info: theorem m9_forall : ∀ (P Q : Nat → Prop), (∀ (x : Nat), P x ↔ Q x) → P 0 = Q 0 :=
fun P Q h => propext (h 0)
-/
#guard_msgs in
#print m9_forall

-- the option form gives the same proofs
set_option solve_by_sat.iffEq true in
example (a b : Nat) : (b < a) = (¬ a ≤ b) := by
  solve_by_sat [Nat.not_le] (nodes := 1)

set_option solve_by_sat.iffEq true in
example (A B C : Prop) (h : C ∧ (A ↔ B)) : A = B := by
  solve_by_sat []

/-! ## Minimality: N = 1 is the least N (at N = 0 there is no proof) -/

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (a b : Nat) : (¬ a ≤ b) = (b < a) := by
  solve_by_sat [Nat.not_le] (nodes := 0) (iffEq := true)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (a b : Nat) : (b < a) = (¬ a ≤ b) := by
  solve_by_sat [Nat.not_le] (nodes := 0) (iffEq := true)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (A B : Prop) (h : A ↔ B) : A = B := by
  solve_by_sat [] (nodes := 0) (iffEq := true)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (A B : Prop) (h : A ↔ B) : B = A := by
  solve_by_sat [] (nodes := 0) (iffEq := true)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (A B C : Prop) (h : C ∧ (A ↔ B)) : A = B := by
  solve_by_sat [] (nodes := 0) (iffEq := true)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (P Q : Nat → Prop) (h : ∀ x : Nat, P x ↔ Q x) : P 0 = Q 0 := by
  solve_by_sat [] (nodes := 0) (iffEq := true)

/-! ## With `iffEq` off, each fails with the no-proof message (at the default N = 8) -/

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq false in
example (a b : Nat) : (¬ a ≤ b) = (b < a) := by
  solve_by_sat [Nat.not_le]

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq false in
example (a b : Nat) : (b < a) = (¬ a ≤ b) := by
  solve_by_sat [Nat.not_le]

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq false in
example (A B : Prop) (h : A ↔ B) : A = B := by
  solve_by_sat []

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq false in
example (A B : Prop) (h : A ↔ B) : B = A := by
  solve_by_sat []

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq false in
example (A B C : Prop) (h : C ∧ (A ↔ B)) : A = B := by
  solve_by_sat []

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq false in
example (P Q : Nat → Prop) (h : ∀ x : Nat, P x ↔ Q x) : P 0 = Q 0 := by
  solve_by_sat []

-- `(iffEq := false)` in the call overrides the option
/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.iffEq true in
example (A B : Prop) (h : A ↔ B) : A = B := by
  solve_by_sat [] (nodes := 1) (iffEq := false)

/-! ## The mutation check: the two recipes swapped give a decoder error, never a proof -/

/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun a#0 b#1 => Nat.not_le.propext
error: node 0: the head (?b < ?a) =
  (?a ≤ ?b → False) of Nat.not_le.propext does not unify with the target (a✝ ≤ b✝ → False) = (b✝ < a✝)
-/
#guard_msgs in
set_option solve_by_sat.iffEqMutant true in
example (a b : Nat) : (¬ a ≤ b) = (b < a) := by
  solve_by_sat [Nat.not_le] (nodes := 1) (iffEq := true)

/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun a#0 b#1 => Nat.not_le.propext_symm
error: node 0: the head (?a ≤ ?b → False) =
  (?b < ?a) of Nat.not_le.propext_symm does not unify with the target (b✝ < a✝) = (a✝ ≤ b✝ → False)
-/
#guard_msgs in
set_option solve_by_sat.iffEqMutant true in
example (a b : Nat) : (b < a) = (¬ a ≤ b) := by
  solve_by_sat [Nat.not_le] (nodes := 1) (iffEq := true)

/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun A#0 B#1 h h.mp h.mpr h.propext h.propext_symm => h.propext
error: node 0: the head B✝ = A✝ of h.propext does not unify with the target A✝ = B✝
-/
#guard_msgs in
set_option solve_by_sat.iffEqMutant true in
example (A B : Prop) (h : A ↔ B) : A = B := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun A#0 B#1 h h.mp h.mpr h.propext h.propext_symm => h.propext_symm
error: node 0: the head A✝ = B✝ of h.propext_symm does not unify with the target B✝ = A✝
-/
#guard_msgs in
set_option solve_by_sat.iffEqMutant true in
example (A B : Prop) (h : A ↔ B) : B = A := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun A#0 B#1 C#2 h h.left h.right h.right.mp h.right.mpr h.right.propext h.right.propext_symm => h.right.propext
error: node 0: the head B✝ = A✝ of h.right.propext does not unify with the target A✝ = B✝
-/
#guard_msgs in
set_option solve_by_sat.iffEqMutant true in
example (A B C : Prop) (h : C ∧ (A ↔ B)) : A = B := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun P#0 Q#1 h h.mp h.mpr h.propext h.propext_symm => h.propext
error: node 0: the head Q✝ ?x = P✝ ?x of h.propext does not unify with the target P✝ 0 = Q✝ 0
-/
#guard_msgs in
set_option solve_by_sat.iffEqMutant true in
example (P Q : Nat → Prop) (h : ∀ x : Nat, P x ↔ Q x) : P 0 = Q 0 := by
  solve_by_sat [] (nodes := 1) (iffEq := true)

/-! ## `verbose`: the paths added, and the paths dropped -/

-- 2 paths from `Nat.not_le` (none from `Nat.lt_irrefl`, which has no `↔` head), 2 from the
-- nested `↔` of `h` and 2 from `k`. At N = 0 nothing is encoded, so the messages do not depend
-- on the encoder's settings.
/--
info: solve_by_sat: iffEq: 6 propext paths added (2 from constants of H, 4 from local hypotheses)
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.verbose true in
example (A B C : Prop) (h : C ∧ (A ↔ B)) (k : ∀ x : Nat, x = x ↔ True) : A = B := by
  solve_by_sat [Nat.not_le, Nat.lt_irrefl] (nodes := 0) (iffEq := true)

-- a root hypothesis whose sides cannot be compiled as terms (`g` is applied to an argument): its
-- `propext` paths are dropped and reported with its other paths; none is added, so there is no
-- count line
/--
info: solve_by_sat: hypothesis h is introduced but gives no clause:
solve_by_sat: the clause variable g#2 is applied to arguments in g 0: not first order
---
info: solve_by_sat: hypothesis h.mp is introduced but gives no clause:
solve_by_sat: the head of h.mp g 1 has the clause variable g#2 as its head symbol
---
info: solve_by_sat: hypothesis h.mpr is introduced but gives no clause:
solve_by_sat: the head of h.mpr g 0 has the clause variable g#2 as its head symbol
---
info: solve_by_sat: hypothesis h.propext is introduced but gives no clause:
solve_by_sat: the clause variable g#2 is applied to arguments in g 0: not first order
---
info: solve_by_sat: hypothesis h.propext_symm is introduced but gives no clause:
solve_by_sat: the clause variable g#2 is applied to arguments in g 1: not first order
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.verbose true in
example (A B : Prop) (h : ∀ g : Nat → Prop, g 0 ↔ g 1) : A = B := by
  solve_by_sat [] (nodes := 0) (iffEq := true)
