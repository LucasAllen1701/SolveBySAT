/-
Regressions found during milestone 7 (the 7b full run), each success with its minimality
check.

R1 (decoder): a clause whose head mentions one of its premises, such as
`List.head_reverse : (h : l.reverse ≠ []) → l.reverse.head h = l.getLast _`. The premise is
a proof inside a term, so it compiles to `⟨proof⟩` (SPEC §4.4). Unifying the head with the
target used to assign the premise's metavariable to the target's proof before its child was
replayed. A premise with binders then failed in `introN` ("decoder failed on a satisfiable
CNF"); a premise without binders was silently overwritten by its child. Premise
metavariables are now synthetic opaque, so the head is compared with the target by proof
irrelevance and only the child fills the premise. See NOTES.md, "7b: decoder bug".
- R1a: the premise has a binder (`P n → False`);
- R1b: the same with `¬`, the form of the full run's goal;
- R1c: a premise without binders, with the same proof in the target;
- R1d: a premise without binders, with a different proof in the target (the child's proof
  is used, and the kernel accepts it by proof irrelevance);
- R1e: the full run's goal, `List.getLast_eq_head_reverse`, with the lemmas its proof uses.
R2 (decoder configuration) is at the end of the file.
-/
import SolveBySat

/-! ## R1a -/

theorem R1a (P : Nat → Prop) (f : (n : Nat) → (P n → False) → Nat)
    (lem : ∀ n (h : P n → False), f n h = 0) (n : Nat) (hp : P n → False) : f n hp = 0 := by
  solve_by_sat [] (nodes := 3)

/-- info: theorem R1a : ∀ (P : Nat → Prop) (f : (n : Nat) → (P n → False) → Nat),
  (∀ (n : Nat) (h : P n → False), f n h = 0) → ∀ (n : Nat) (hp : P n → False), f n hp = 0 :=
fun P f lem n hp => lem n fun a => hp a -/
#guard_msgs in
#print R1a

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (P : Nat → Prop) (f : (n : Nat) → (P n → False) → Nat)
    (lem : ∀ n (h : P n → False), f n h = 0) (n : Nat) (hp : P n → False) : f n hp = 0 := by
  solve_by_sat [] (nodes := 2)

/-! ## R1b -/

example (P : Nat → Prop) (f : (n : Nat) → ¬ P n → Nat)
    (lem : ∀ n (h : ¬ P n), f n h = 0) (n : Nat) (hp : ¬ P n) : f n hp = 0 := by
  solve_by_sat [] (nodes := 3)

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (P : Nat → Prop) (f : (n : Nat) → ¬ P n → Nat)
    (lem : ∀ n (h : ¬ P n), f n h = 0) (n : Nat) (hp : ¬ P n) : f n hp = 0 := by
  solve_by_sat [] (nodes := 2)

/-! ## R1c -/

example (Q : Nat → Prop) (f : (n : Nat) → Q n → Nat) (lem : ∀ n (h : Q n), f n h = 0)
    (n : Nat) (hq : Q n) : f n hq = 0 := by
  solve_by_sat [] (nodes := 2)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example (Q : Nat → Prop) (f : (n : Nat) → Q n → Nat) (lem : ∀ n (h : Q n), f n h = 0)
    (n : Nat) (hq : Q n) : f n hq = 0 := by
  solve_by_sat [] (nodes := 1)

/-! ## R1d -/

theorem R1d (Q : Nat → Prop) (R : Prop) (f : (n : Nat) → Q n → Nat)
    (lem : ∀ n (h : Q n), f n h = 0) (n : Nat) (r : R) (q : R → Q n) (hq : Q n) :
    f n (q r) = 0 := by
  solve_by_sat [] (nodes := 2)

/-- info: theorem R1d : ∀ (Q : Nat → Prop) (R : Prop) (f : (n : Nat) → Q n → Nat),
  (∀ (n : Nat) (h : Q n), f n h = 0) → ∀ (n : Nat) (r : R) (q : R → Q n), Q n → f n ⋯ = 0 :=
fun Q R f lem n r q hq => lem n hq -/
#guard_msgs in
#print R1d

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example (Q : Nat → Prop) (R : Prop) (f : (n : Nat) → Q n → Nat)
    (lem : ∀ n (h : Q n), f n h = 0) (n : Nat) (r : R) (q : R → Q n) (hq : Q n) :
    f n (q r) = 0 := by
  solve_by_sat [] (nodes := 1)

/-! ## R1e (about 2 minutes) -/

set_option maxHeartbeats 0 in
example : type_of% @List.getLast_eq_head_reverse := by
  solve_by_sat [Eq.symm, List.head_reverse, List.reverse_eq_nil_iff] (nodes := 5)

set_option maxHeartbeats 0 in
/-- error: solve_by_sat: no proof with at most 4 nodes exists in the class -/
#guard_msgs in
example : type_of% @List.getLast_eq_head_reverse := by
  solve_by_sat [Eq.symm, List.head_reverse, List.reverse_eq_nil_iff] (nodes := 4)

/-! ## R2 (decoder): the unifier's configuration

R2: the decoder used the caller's unifier configuration. Without `ctxApprox` (a bare
`MetaM`, as in the evaluation harness; the tactic gets it from the elaborator), a clause
variable created under a hypothesis that a node introduced could not become the value of a
variable from outside that node, and decoding failed on a satisfiable CNF. The decoder now
sets the tactic's configuration itself. See NOTES.md, "7b: second decoder bug".
- R2a: `∀ x, x ≠ x.succ` from `Ne.symm` and `Nat.succ_ne_self` (4 nodes, as
  `Ne.symm (fun a => Nat.succ_ne_self x a)`), decoded with the approximations off;
- R2b: the full run's goal, `Nat.pred_eq_self_iff` position 22 of Tier B. -/

def R2aGoal : Prop := ∀ x : Nat, x ≠ x.succ
set_option linter.unusedVariables false in
def R2bGoal : Prop := ∀ {n : Nat} (n_1 : Nat), n = n_1 + 1 → ∀ (x_0 x_0 : Nat), x_0 ≠ x_0.succ

open Lean Meta in
/-- Run `solveCore` on the value of `g` with the unifier's approximations off. -/
def R2run (g : Name) (N : Nat) : MetaM Unit :=
  withConfig (fun c => { c with foApprox := false, ctxApprox := false, quasiPatternApprox := false }) do
    let goal := (← getConstInfo g).value!
    let t ← SolveBySat.solveCore goal #[``Ne.symm, ``Nat.succ_ne_self] N
    unless ← isDefEq (← inferType t) goal do throwError "wrong type"
    logInfo m!"{t}"

/-- info: fun x a => Ne.symm (fun a => Nat.succ_ne_self x a) a -/
#guard_msgs in
#eval R2run ``R2aGoal 4

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
#eval R2run ``R2aGoal 3

/-- info: fun {n} n_1 a x_0 x_0_1 a_1 => Ne.symm (fun a => Nat.succ_ne_self x_0_1 a) a_1 -/
#guard_msgs in
#eval R2run ``R2bGoal 4

/-- error: solve_by_sat: no proof with at most 3 nodes exists in the class -/
#guard_msgs in
#eval R2run ``R2bGoal 3

/-! ## R3 (compiler): type templates are built from preprocessed types (EVAL_PLAN §10.7)

The compiler built each type template from the raw inferred type (`compileType (← inferType e)`),
while terms are built from preprocessed expressions (SPEC §4.1). The syntactic typing clause
(§6.8) then compared an unnormalised type with a normalised one and excluded real proofs.
Found in the 7d-1 E1 review (`B/Std.Internal.List.Const.map_insertEntry_perm_filter_map/15`);
see NOTES.md, "7d-1 STOPPED" and the fix record after it.
- R3a: `Not` is unfolded in the target but was not in the template of `instDecidableNot …`;
- R3b: universe levels: `Eq.refl` at a type in `Type (max u v)`. The target's `Eq` level is
  normalised to `max (u+1) (v+1)`; the inferred type of `List (α × β)` was `Sort (succ (max u v))`.
-/

universe u v

/-! ## R3a -/

theorem R3a (b : Bool) : decide (¬ b = true) = decide (b = false) := by
  solve_by_sat [Decidable.decide.congr_simp, Bool.not_eq_true] (nodes := 2)

/-- info: theorem R3a : ∀ (b : Bool), (decide ¬b = true) = decide (b = false) :=
fun b => Decidable.decide.congr_simp (b = true → False) (b = false) (Bool.not_eq_true b) -/
#guard_msgs in
#print R3a

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example (b : Bool) : decide (¬ b = true) = decide (b = false) := by
  solve_by_sat [Decidable.decide.congr_simp, Bool.not_eq_true] (nodes := 1)

/-! ## R3b -/

theorem R3b {α : Type u} {β : Type v} (x : List (α × β)) : x = x := by
  solve_by_sat [Eq.refl] (nodes := 1)

/-- info: theorem R3b.{u, v} : ∀ {α : Type u} {β : Type v} (x : List (α × β)), x = x :=
fun {α} {β} x => Eq.refl x -/
#guard_msgs in
#print R3b

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example {α : Type u} {β : Type v} (x : List (α × β)) : x = x := by
  solve_by_sat [Eq.refl] (nodes := 0)
