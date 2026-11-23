/-
Milestone 8a (M8_PLAN.md §2.3): hand examples for the rewriting probe's rule generator
(`Test/M8Rules.lean`). Each example generates the rules for its goal (built with `addDecl`, so the
kernel checks each one) and runs the unchanged `solve_by_sat` with H as in §2.3
(`solve_by_sat_probe`), at its minimal N, with the minimality check at N − 1.

- P1: congruence, `a = b → f a = f b`.
- P2: substitution under a function, `h : x = y ⊢ P (f x) → P (f y)`.
- P3, P4: a `Prop` position rewritten with an `↔`. The rules build and the kernel accepts them,
  but the unchanged compiler rejects every `↔` rule: its premise `a ↔ b` over Prop variables
  compiles to clauses whose head is a clause variable (SPEC §2). So no proof exists in the class.
  This is recorded, as M8_PLAN §2.3 says for rejected rules, and reported to the owner.
-/
import Test.M8Rules

set_option Elab.async false   -- the rules are top-level declarations added during the proof

axiom f : Nat → Nat
axiom P : Nat → Prop
axiom Q : Prop → Prop
axiom g : Prop → Nat

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

/-! ## P3, P4: `↔` rules build but are outside the class -/

/--
info: rejected by the compiler: [_probe.Iff.subst_iff.«0»: solve_by_sat: the head of x0@g4 a has the clause variable a#2 as its head symbol,
 _probe.Iff.subst_iff.«1»: solve_by_sat: the head of x0@g4 b✝ has the clause variable b#3 as its head symbol,
 _probe.Q.subst_iff.«0»: solve_by_sat: the head of x0@g4 a✝ has the clause variable a#2 as its head symbol]
---
error: solve_by_sat: no proof with at most 3 nodes exists in the class
-/
#guard_msgs in
example (A B : Prop) (h : A ↔ B) : Q B → Q A := by solve_by_sat_probe [] (nodes := 3)

/--
info: rejected by the compiler: [_probe.Iff.subst_iff.«0»: solve_by_sat: the head of x0@g4 a has the clause variable a#2 as its head symbol,
 _probe.Iff.subst_iff.«1»: solve_by_sat: the head of x0@g4 b✝ has the clause variable b#3 as its head symbol,
 _probe.g.congr_iff.«0»: solve_by_sat: the head of x0@g4 a✝ has the clause variable a#2 as its head symbol]
---
error: solve_by_sat: no proof with at most 2 nodes exists in the class
-/
#guard_msgs in
example (A B : Prop) (h : A ↔ B) : g A = g B := by solve_by_sat_probe [] (nodes := 2)

/-- The `↔` rules of P3 and P4, built at top level: `addDecl` has kernel-checked them. -/
def showIffRules : Lean.Elab.TermElabM Unit := do
  for stx in [← `(∀ (A B : Prop), (A ↔ B) → Q B → Q A), ← `(∀ (A B : Prop), (A ↔ B) → g A = g B)] do
    let e ← Lean.Elab.Term.elabType stx
    let R ← M8.generate e #[]
    for r in R.rules do
      if r.toString.endsWith "_iff.«0»" && (r.toString.startsWith "_probe.Q" || r.toString.startsWith "_probe.g") then
        Lean.logInfo m!"{r} : {(← Lean.getConstInfo r).type}"

/--
info: _probe.Q.subst_iff.«0» : ∀ (a b : Prop), (a ↔ b) → Q b → Q a
---
info: _probe.g.congr_iff.«0» : ∀ (a b : Prop), (a ↔ b) → g a = g b
-/
#guard_msgs in
run_elab showIffRules
