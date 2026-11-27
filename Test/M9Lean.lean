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

/-! # Milestone 9a-2 (M9_PLAN 3.1, 3.2, amendment 6.1): equality rules made per use

With `rewrite` (the option `solve_by_sat.rewrite`, or `(rewrite := true)` in the call, after
`(iffEq := b)`), the compiler adds substitution and congruence rules at the term positions on the
rewriting paths, made per (symbol, position, context), and `Eq.refl`, `Eq.symm`, `Eq.trans` at every
type at which an equation occurs (`eqTrans` drops `Eq.trans`). Each test below is proved at its
least N (N − 1 fails), and fails with the no-proof message when `rewrite` is off. The "off" tests
set `solve_by_sat.rewrite false` explicitly, so that the file also passes when the whole Lean suite
is run with `-Dsolve_by_sat.rewrite=true` (`Test/m9a2_lean.sh`); the `verbose` guards pin the
options they show.
-/

#guard !(SolveBySat.CompileOptions.rewrite {})
#guard !SolveBySat.solve_by_sat.rewrite.defValue
#guard (SolveBySat.CompileOptions.eqTrans {})
#guard SolveBySat.solve_by_sat.eqTrans.defValue
#guard (SolveBySat.CompileOptions.rewriteSymbols {}).isNone
#guard SolveBySat.solve_by_sat.rewriteSymbols.defValue == ""

/-! ## The tests of M9_PLAN 3.2 -/

-- a substitution at a `Prop` position, through an `app` atom (`Q` is an eigenvariable, 6.1
-- clarification 2): the rule `Q a ← a = b, Q b` is local to the root; `(b < a) = (¬ a ≤ b)` is the
-- `R = L` path of `Nat.not_le`
theorem m9_rw_subst (Q : Prop → Prop) (a b : Nat) (h : Q (¬ a ≤ b)) : Q (b < a) := by
  solve_by_sat [Nat.not_le] (nodes := 3) (iffEq := true) (rewrite := true)

/--
info: theorem m9_rw_subst : ∀ (Q : Prop → Prop) (a b : Nat), Q ¬a ≤ b → Q (b < a) :=
fun Q a b h =>
  (fun a b h hp => Eq.mpr (congrArg (fun y => Q y) h) hp) (b < a) (a ≤ b → False) (Eq.symm (propext Nat.not_le)) h
-/
#guard_msgs in
#print m9_rw_subst

-- a congruence
theorem m9_rw_congr (a : Nat) : Nat.succ (a + 0) = Nat.succ a := by
  solve_by_sat [Nat.add_zero] (nodes := 2) (rewrite := true)

/--
info: theorem m9_rw_congr : ∀ (a : Nat), (a + 0).succ = a.succ :=
fun a => (fun a b h => congrArg (fun y => y.succ) h) (a + 0) a (Nat.add_zero a)
-/
#guard_msgs in
#print m9_rw_congr

-- a two-step chain: congruence of `f`, then `Eq.trans` at `Nat` (4 nodes)
theorem m9_rw_trans (f : Nat → Int) (a b c : Nat) (h₁ : a = b) (h₂ : b = c) : f a = f c := by
  solve_by_sat [] (nodes := 4) (rewrite := true)

/--
info: theorem m9_rw_trans : ∀ (f : Nat → Int) (a b c : Nat), a = b → b = c → f a = f c :=
fun f a b c h₁ h₂ => (fun a b h => congrArg (fun y => f y) h) a c ((fun x y z h₁ h₂ => Eq.trans h₁ h₂) a b c h₁ h₂)
-/
#guard_msgs in
#print m9_rw_trans

-- the same with `eqTrans := false` fails at N = 4 (at N = 5 the substitution rule of `Eq` at
-- `Int`, made for the target, chains two congruences instead)
/-- error: solve_by_sat: no proof with at most 4 nodes exists in the class -/
#guard_msgs in
example (f : Nat → Int) (a b c : Nat) (h₁ : a = b) (h₂ : b = c) : f a = f c := by
  solve_by_sat [] (nodes := 4) (rewrite := true) (eqTrans := false)

example (f : Nat → Int) (a b c : Nat) (h₁ : a = b) (h₂ : b = c) : f a = f c := by
  solve_by_sat [] (nodes := 5) (rewrite := true) (eqTrans := false)

-- a goal over the root's type parameters: the congruence of `HAdd.hAdd` at `α` and the root's
-- instance, a rule local to the root
theorem m9_rw_root {α} [Add α] (x y : α) (h : x = y) : x + x = y + x := by
  solve_by_sat [] (nodes := 2) (rewrite := true)

/--
info: theorem m9_rw_root.{u_1} : ∀ {α : Type u_1} [inst : Add α] (x y : α), x = y → x + x = y + x :=
fun {α} [Add α] x y h => (fun a b x0 h => congrArg (fun y => y + x0) h) x y x h
-/
#guard_msgs in
#print m9_rw_root

-- an `app` atom (6.1, clarification 2): substitution at the eigenvariable `P`, local to the root
theorem m9_rw_app (P : Nat → Prop) (a b : Nat) (h : a = b) (hp : P b) : P a := by
  solve_by_sat [] (nodes := 3) (rewrite := true)

/--
info: theorem m9_rw_app : ∀ (P : Nat → Prop) (a b : Nat), a = b → P b → P a :=
fun P a b h hp => (fun a b h hp => Eq.mpr (congrArg (fun y => P y) h) hp) a b h hp
-/
#guard_msgs in
#print m9_rw_app

-- the option form gives the same proofs
set_option solve_by_sat.rewrite true in
example {α} [Add α] (x y : α) (h : x = y) : x + x = y + x := by
  solve_by_sat [] (nodes := 2)

set_option solve_by_sat.rewrite true in
set_option solve_by_sat.eqTrans false in
/-- error: solve_by_sat: no proof with at most 4 nodes exists in the class -/
#guard_msgs in
example (f : Nat → Int) (a b c : Nat) (h₁ : a = b) (h₂ : b = c) : f a = f c := by
  solve_by_sat [] (nodes := 4)

/-! ## Minimality: N − 1 fails -/

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (Q : Prop → Prop) (a b : Nat) (h : Q (¬ a ≤ b)) : Q (b < a) := by
  solve_by_sat [Nat.not_le] (nodes := 2) (iffEq := true) (rewrite := true)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example (a : Nat) : Nat.succ (a + 0) = Nat.succ a := by
  solve_by_sat [Nat.add_zero] (nodes := 1) (rewrite := true)

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
example (f : Nat → Int) (a b c : Nat) (h₁ : a = b) (h₂ : b = c) : f a = f c := by
  solve_by_sat [] (nodes := 3) (rewrite := true)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example {α} [Add α] (x y : α) (h : x = y) : x + x = y + x := by
  solve_by_sat [] (nodes := 1) (rewrite := true)

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (P : Nat → Prop) (a b : Nat) (h : a = b) (hp : P b) : P a := by
  solve_by_sat [] (nodes := 2) (rewrite := true)

/-! ## With `rewrite` off, each fails with the no-proof message (at the default N = 8) -/

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.rewrite false in
example (Q : Prop → Prop) (a b : Nat) (h : Q (¬ a ≤ b)) : Q (b < a) := by
  solve_by_sat [Nat.not_le] (iffEq := true)

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.rewrite false in
example (a : Nat) : Nat.succ (a + 0) = Nat.succ a := by
  solve_by_sat [Nat.add_zero]

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.rewrite false in
example (f : Nat → Int) (a b c : Nat) (h₁ : a = b) (h₂ : b = c) : f a = f c := by
  solve_by_sat []

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.rewrite false in
example {α} [Add α] (x y : α) (h : x = y) : x + x = y + x := by
  solve_by_sat []

/-- error: solve_by_sat: no proof with at most 8 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.rewrite false in
example (P : Nat → Prop) (a b : Nat) (h : a = b) (hp : P b) : P a := by
  solve_by_sat []

-- `(rewrite := false)` in the call overrides the option
/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.rewrite true in
example {α} [Add α] (x y : α) (h : x = y) : x + x = y + x := by
  solve_by_sat [] (nodes := 2) (rewrite := false)

/-! ## `verbose`: the rules by kind and row, and the list -/

/--
info: solve_by_sat: rewrite: 7 rules (subst: root 2; congr: root 2; refl: root 1; symm: root 1; trans: root 1)
rw.Eq.subst.1@root#0: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?a#4, ?x0#6) ← c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?a#4, ?b#5), c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?b#5, ?x0#6)
rw.HAdd.hAdd.congr.4@root#1: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, c:HAdd.hAdd(lvl:param:u_1, lvl:param:u_1, lvl:param:u_1, ?α#0, ?α#0, ?α#0, c:instHAdd(lvl:param:u_1, ?α#0, ?inst#1), ?a#7, ?x0#9), c:HAdd.hAdd(lvl:param:u_1, lvl:param:u_1, lvl:param:u_1, ?α#0, ?α#0, ?α#0, c:instHAdd(lvl:param:u_1, ?α#0, ?inst#1), ?b#8, ?x0#9)) ← c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?a#7, ?b#8)
rw.HAdd.hAdd.congr.5@root#2: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, c:HAdd.hAdd(lvl:param:u_1, lvl:param:u_1, lvl:param:u_1, ?α#0, ?α#0, ?α#0, c:instHAdd(lvl:param:u_1, ?α#0, ?inst#1), ?x0#12, ?a#10), c:HAdd.hAdd(lvl:param:u_1, lvl:param:u_1, lvl:param:u_1, ?α#0, ?α#0, ?α#0, c:instHAdd(lvl:param:u_1, ?α#0, ?inst#1), ?x0#12, ?b#11)) ← c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?a#10, ?b#11)
rw.Eq.subst.2@root#3: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?x0#15, ?a#13) ← c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?a#13, ?b#14), c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?x0#15, ?b#14)
rw.Eq.refl@root#4: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?x#16, ?x#16)
rw.Eq.symm@root#5: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?y#18, ?x#17) ← c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?x#17, ?y#18)
rw.Eq.trans@root#6: c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?x#19, ?z#21) ← c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?x#19, ?y#20), c:Eq(lvl:succ(lvl:param:u_1), ?α#0, ?y#20, ?z#21)
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.verbose true in
set_option solve_by_sat.iffEq false in
example {α} [Add α] (x y : α) (h : x = y) : x + x = y + x := by
  solve_by_sat [] (nodes := 0) (rewrite := true)

-- no rule and no equation: nothing is printed
/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.verbose true in
example (P : Nat → Prop) (a : Nat) : P a := by
  solve_by_sat [] (nodes := 0) (rewrite := true)

-- H's polymorphic `Eq.symm` is left as it is: no `symm` rule is made
/--
info: solve_by_sat: rewrite: 6 rules (subst: ground 2; refl: ground 1, H 1; trans: ground 1, H 1)
rw.Eq.subst.1@ground#0: c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#6, ?x0#8) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#6, ?b#7), c:Eq(lvl:succ(lvl:zero), c:Nat, ?b#7, ?x0#8)
rw.Eq.subst.2@ground#1: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x0#11, ?a#9) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#9, ?b#10), c:Eq(lvl:succ(lvl:zero), c:Nat, ?x0#11, ?b#10)
rw.Eq.refl@ground#2: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#12, ?x#12)
rw.Eq.trans@ground#3: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#13, ?z#15) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#13, ?y#14), c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#14, ?z#15)
rw.Eq.refl@H#4: c:Eq(?u#16, ?α#17, ?x#18, ?x#18)
rw.Eq.trans@H#5: c:Eq(?u#19, ?α#20, ?x#21, ?z#23) ← c:Eq(?u#19, ?α#20, ?x#21, ?y#22), c:Eq(?u#19, ?α#20, ?y#22, ?z#23)
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.verbose true in
set_option solve_by_sat.iffEq false in
example (a b : Nat) (h : a = b) : b = a := by
  solve_by_sat [Eq.symm] (nodes := 0) (rewrite := true)

/-! ## The static check drops a rule whose statement cannot be compiled

A substitution at a position of `And` has the premise `b ∧ x0`, a connective target whose components
are clause variables, which the compiler rejects (SPEC 4.5): the rule is dropped and reported. -/

/--
info: solve_by_sat: rewrite: the rule rw.And.subst.0@ground#0 is dropped: solve_by_sat: the target b has the clause variable b#2 as its head symbol
---
info: solve_by_sat: rewrite: 10 rules (subst: ground 2; congr: ground 2; refl: ground 2; symm: ground 2; trans: ground 2)
rw.Eq.congr.1@ground#1: c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#1, ?x0#3), c:Eq(lvl:succ(lvl:zero), c:Nat, ?b#2, ?x0#3)) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#1, ?b#2)
rw.Eq.congr.2@ground#2: c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), c:Eq(lvl:succ(lvl:zero), c:Nat, ?x0#6, ?a#4), c:Eq(lvl:succ(lvl:zero), c:Nat, ?x0#6, ?b#5)) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#4, ?b#5)
rw.Eq.subst.1@ground#3: c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#7, ?x0#9) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#7, ?b#8), c:Eq(lvl:succ(lvl:zero), c:Nat, ?b#8, ?x0#9)
rw.Eq.subst.2@ground#4: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x0#12, ?a#10) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#10, ?b#11), c:Eq(lvl:succ(lvl:zero), c:Nat, ?x0#12, ?b#11)
rw.Eq.refl@ground#5: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#13, ?x#13)
rw.Eq.symm@ground#6: c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#15, ?x#14) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#14, ?y#15)
rw.Eq.trans@ground#7: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#16, ?z#18) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#16, ?y#17), c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#17, ?z#18)
rw.Eq.refl@ground#8: c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), ?x#19, ?x#19)
rw.Eq.symm@ground#9: c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), ?y#21, ?x#20) ← c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), ?x#20, ?y#21)
rw.Eq.trans@ground#10: c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), ?x#22, ?z#24) ← c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), ?x#22, ?y#23), c:Eq(lvl:succ(lvl:zero), sort(lvl:zero), ?y#23, ?z#24)
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs(info, error) in
set_option solve_by_sat.verbose true in
set_option solve_by_sat.iffEq false in
example (a : Nat) (h : a = 0) : a = 0 ∧ True := by
  solve_by_sat [] (nodes := 0) (rewrite := true)

/-! ## Mutation checks of M9_PLAN 3.2 -/

-- rules also at positions that are not term positions (`rewriteIneligibleMutant`, testing only):
-- with `Nat` as the source symbol, its occurrences at type positions give rules at those
-- positions, and the static motive check drops each one (a type position: the motive's other
-- arguments no longer fit). The one rule at an instance position (`HAdd.hAdd`'s 3) is type-correct
-- and is kept: instance positions are excluded by eligibility, not by typing (NOTES.md, 9a-2).
/--
info: solve_by_sat: rewrite: the rule rw.Eq.subst.0@ground#0 is dropped by the static motive check: Application type mismatch: The argument
  x0
has type
  Nat
but is expected to have type
  y
in the application
  Eq x0
---
info: solve_by_sat: rewrite: the rule rw.HAdd.hAdd.congr.0@ground#2 is dropped by the static motive check: Application type mismatch: The argument
  instHAdd
has type
  HAdd Nat Nat Nat
but is expected to have type
  HAdd y Nat Nat
in the application
  @HAdd.hAdd y Nat Nat instHAdd
---
info: solve_by_sat: rewrite: the rule rw.HAdd.hAdd.congr.1@ground#3 is dropped by the static motive check: Application type mismatch: The argument
  instHAdd
has type
  HAdd Nat Nat Nat
but is expected to have type
  HAdd Nat y Nat
in the application
  @HAdd.hAdd Nat y Nat instHAdd
---
info: solve_by_sat: rewrite: the rule rw.HAdd.hAdd.congr.2@ground#4 is dropped by the static motive check: Application type mismatch: The argument
  instHAdd
has type
  HAdd Nat Nat Nat
but is expected to have type
  HAdd Nat Nat y
in the application
  @HAdd.hAdd Nat Nat y instHAdd
---
info: solve_by_sat: rewrite: the rule rw.instHAdd.congr.0@ground#6 is dropped by the static motive check: Application type mismatch: The argument
  instAddNat
has type
  Add Nat
but is expected to have type
  Add y
in the application
  @instHAdd y instAddNat
---
info: solve_by_sat: rewrite: the rule rw.OfNat.ofNat.congr.0@ground#8 is dropped by the static motive check: Application type mismatch: The argument
  instOfNatNat 0
has type
  OfNat Nat 0
but is expected to have type
  OfNat y 0
in the application
  @OfNat.ofNat y 0 (instOfNatNat 0)
---
info: solve_by_sat: rewrite: 9 rules (subst: ground 1; congr: ground 2; refl: ground 2; symm: ground 2; trans: ground 2)
rw.Eq.subst.1@ground#1: c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#1, ?x0#3) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#1, ?b#2), c:Eq(lvl:succ(lvl:zero), c:Nat, ?b#2, ?x0#3)
rw.HAdd.hAdd.congr.3@ground#5: c:Eq(lvl:succ(lvl:zero), c:Nat, c:HAdd.hAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat, ?a#4, ?x0#6, ?x1#7), c:HAdd.hAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat, ?b#5, ?x0#6, ?x1#7)) ← c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?a#4, ?b#5)
rw.HAdd.hAdd.congr.5@ground#7: c:Eq(lvl:succ(lvl:zero), c:Nat, c:HAdd.hAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat, c:instHAdd(lvl:zero, c:Nat, c:instAddNat), ?x0#10, ?a#8), c:HAdd.hAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat, c:instHAdd(lvl:zero, c:Nat, c:instAddNat), ?x0#10, ?b#9)) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?a#8, ?b#9)
rw.Eq.refl@ground#9: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#11, ?x#11)
rw.Eq.symm@ground#10: c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#13, ?x#12) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#12, ?y#13)
rw.Eq.trans@ground#11: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#14, ?z#16) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#14, ?y#15), c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#15, ?z#16)
rw.Eq.refl@ground#12: c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?x#17, ?x#17)
rw.Eq.symm@ground#13: c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?y#19, ?x#18) ← c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?x#18, ?y#19)
rw.Eq.trans@ground#14: c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?x#20, ?z#22) ← c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?x#20, ?y#21), c:Eq(lvl:succ(lvl:zero), c:HAdd(lvl:zero, lvl:zero, lvl:zero, c:Nat, c:Nat, c:Nat), ?y#21, ?z#22)
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs(info, error) in
set_option solve_by_sat.verbose true in
set_option solve_by_sat.rewriteIneligibleMutant true in
set_option solve_by_sat.iffEq false in
example (a : Nat) : a + 0 = a := by
  solve_by_sat [] (nodes := 0) (rewrite := true) (rewriteSymbols := [Nat])

-- without the mutation, the same spines pass non-term positions and give no rule but the core
/--
info: solve_by_sat: rewrite: 3 rules (refl: ground 1; symm: ground 1; trans: ground 1)
rw.Eq.refl@ground#0: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#1, ?x#1)
rw.Eq.symm@ground#1: c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#3, ?x#2) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#2, ?y#3)
rw.Eq.trans@ground#2: c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#4, ?z#6) ← c:Eq(lvl:succ(lvl:zero), c:Nat, ?x#4, ?y#5), c:Eq(lvl:succ(lvl:zero), c:Nat, ?y#5, ?z#6)
---
error: solve_by_sat: no proof with at most 0 nodes exists in the class
-/
#guard_msgs in
set_option solve_by_sat.verbose true in
set_option solve_by_sat.iffEq false in
example (a : Nat) : a + 0 = a := by
  solve_by_sat [] (nodes := 0) (rewrite := true) (rewriteSymbols := [Nat])

-- each rule's proof taken from a rule of the same kind, symbol and position in another context
-- (`rewriteContextMutant`, testing only): the congruence of `HAdd.hAdd` at `α` gets the proof of
-- the one at `Nat` (a liberal candidate, from `k`), and the decoder's check that a rule's proof
-- proves its clause stops it: no proof
/--
error: solve_by_sat: decoder failed on a satisfiable CNF (bug).
skeleton: fun α#0 inst#1 x#2 y#3 n#4 m#5 h k => rw.HAdd.hAdd.congr.4@root#1(h)
error: node 0: the proof of the rule rw.HAdd.hAdd.congr.4@root#1 does not prove its statement ∀ (a b x0 : α✝),
  a = b → a + x0 = b + x0
-/
#guard_msgs in
set_option solve_by_sat.rewriteContextMutant true in
example {α} [Add α] (x y : α) (n m : Nat) (h : x = y) (k : n + n = m) : x + x = y + x := by
  solve_by_sat [] (nodes := 2) (rewrite := true)

-- the same without the mutation is proved
example {α} [Add α] (x y : α) (n m : Nat) (h : x = y) (k : n + n = m) : x + x = y + x := by
  solve_by_sat [] (nodes := 2) (rewrite := true)
