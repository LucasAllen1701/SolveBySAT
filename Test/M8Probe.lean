/-
Milestone 8a (M8_PLAN.md §2.3): hand examples for the rewriting probe's rule generator
(`Test/M8Rules.lean`). Each example generates the rules for its goal (built with `addDecl`, so the
kernel checks each one) and runs the unchanged `solve_by_sat` with H as in §2.3
(`solve_by_sat_probe`), at its minimal N, with the minimality check at N − 1.

- P1: congruence, `a = b → f a = f b`.
- P2: substitution under a function, `h : x = y ⊢ P (f x) → P (f y)`.
- P3: `(¬ a ≤ b) = (b < a)` from `Nat.not_le`, through its `propext` equation (amendment 4.1).
- P4: `Q (¬ a ≤ b) → Q (b < a)`, through a substitution rule at a `Prop` position.
- P5: `A ∧ B` from `hA : A`, `h : B ↔ C`, `hC : C`, with no rules at all.
The pilot's P3 and P4 (`↔` rules, rejected by the compiler) are replaced: amendment 4.1 removed them.
Messages that the probe tactic logs about rejected rules (`Iff`'s own substitution rules, whose
`↔` head splits into variable heads) are not part of what these examples check, so P4's minimality
check matches errors only.
-/
import Test.M8Rules

set_option Elab.async false   -- the rules are top-level declarations added during the proof

axiom f : Nat → Nat
axiom P : Nat → Prop

/-! ## P1 -/

theorem P1 : ∀ a b : Nat, a = b → f a = f b := by solve_by_sat_probe [] (nodes := 2)

/-- info: theorem P1 : ∀ (a b : Nat), a = b → f a = f b :=
fun a b a_1 => _probe.f.congr.«0» a b a_1 -/
#guard_msgs in
#print P1

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example : ∀ a b : Nat, a = b → f a = f b := by solve_by_sat_probe [] (nodes := 1)

/-! ## P2 -/

theorem P2 (x y : Nat) (h : x = y) : P (f x) → P (f y) := by solve_by_sat_probe [] (nodes := 5)

/-- info: theorem P2 : ∀ (x y : Nat), x = y → P (f x) → P (f y) :=
fun x y h a => _probe.P.subst.«0» (f y) (f x) (_probe.f.congr.«0» y x (Eq.symm h)) a -/
#guard_msgs in
#print P2

/-- error: solve_by_sat: no proof with at most 4 nodes exists in the class -/
#guard_msgs in
example (x y : Nat) (h : x = y) : P (f x) → P (f y) := by solve_by_sat_probe [] (nodes := 4)

/-! ## P3, P4, P5 (M8_PLAN amendment 4.1 decision 5; P3 and P4 replace the `↔` examples)

P3: an equation between propositions from an `↔` lemma, through its `propext` equation.
P4: a substitution rule at a `Prop` position (`=` since amendment 4.1), with the `propext` equation
turned round by `Eq.symm`.
P5: rewriting with a local `↔` under a connective of the goal needs no rule: `And.intro` and the
built-in `Iff.mpr` of the hypothesis are already in the class. -/

axiom Q : Prop → Prop

theorem P3 (a b : Nat) : (¬ a ≤ b) = (b < a) := by solve_by_sat_probe [Nat.not_le] (nodes := 1)

/-- info: theorem P3 : ∀ (a b : Nat), (¬a ≤ b) = (b < a) :=
fun a b => _probe.Nat.not_le.propext.root -/
#guard_msgs in
#print P3

-- P3's minimal N is 1, so there is no smaller N to check. Its rule is the `propext` equation:
/-- info: @_probe.Nat.not_le.propext.root : ∀ {a b : Nat}, (¬a ≤ b) = (b < a) -/
#guard_msgs in
#check @«_probe».Nat.not_le.propext.root

theorem P4 (a b : Nat) : Q (¬ a ≤ b) → Q (b < a) := by solve_by_sat_probe [Nat.not_le] (nodes := 4)

/-- info: theorem P4 : ∀ (a b : Nat), Q ¬a ≤ b → Q (b < a) :=
fun a b a_1 => _probe.Q.subst.«0» (b < a) (a ≤ b → False) (Eq.symm _probe.Nat.not_le.propext.root) a_1 -/
#guard_msgs in
#print P4

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs (error, drop info) in
example (a b : Nat) : Q (¬ a ≤ b) → Q (b < a) := by solve_by_sat_probe [Nat.not_le] (nodes := 3)

theorem P5 (A B C : Prop) (hA : A) (h : B ↔ C) (hC : C) : A ∧ B := by solve_by_sat [] (nodes := 4)

/-- info: theorem P5 : ∀ (A B C : Prop), A → (B ↔ C) → C → A ∧ B :=
fun A B C hA h hC => ⟨hA, h.mpr hC⟩ -/
#guard_msgs in
#print P5

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
example (A B C : Prop) (hA : A) (h : B ↔ C) (hC : C) : A ∧ B := by solve_by_sat [] (nodes := 3)
