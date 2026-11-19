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
