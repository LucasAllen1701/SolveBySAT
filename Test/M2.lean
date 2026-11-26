/-
Milestone 2 acceptance (SPEC §9.2): L1 to L4 succeed; F4 fails as expected; the node
counts of L1 to L4 are minimal, so each fails with one node fewer.

Additional tests (not in the spec):
- G1: an argument that unification leaves open but the model grounds (SPEC §2.2,
  "Determined arguments"), decoded through the groundness witnesses;
- G2: the static half of the typing rule (6.8): with it the instance is unprovable, as
  it should be; since milestone 4 the typing clause gives the same answer without it;
- R1 to R4: rejection messages for statements outside the scope of section 2 (R2 changed
  by amendment 2 of milestone 3; R2b keeps the rejection for a constant listed in H).

Run: `lake env lean Test/M2.lean` — success means no errors; the info lines show the
CNF size and the decoded skeleton of every successful call.
-/
import SolveBySat
set_option solve_by_sat.verbose true

/-! ## L1 to L4 -/

-- L1: chain of lemmas, exactly 5 nodes
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)
-- L2: implications, 3 nodes
example (A B C : Prop) : (A → B) → (B → C) → A → C := by
  solve_by_sat [] (nodes := 3)
-- L3: quantified hypothesis, 2 nodes
example (P Q : Nat → Prop) (a : Nat) (h : ∀ y, P y → Q y) (hp : P a) : Q a := by
  solve_by_sat [] (nodes := 2)
-- L4: reflexivity, 1 node
example (n : Nat) : n ≤ n := by
  solve_by_sat [Nat.le_refl] (nodes := 1)

/-! ## F4 (verbatim from the spec) -/

-- F4: one node short of L1
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  fail_if_success solve_by_sat [Nat.le_trans] (nodes := 4)
  sorry

/-! ## Minimality: L1 to L4 with one node fewer fail with exactly this message -/

/-- error: solve_by_sat: no proof with at most 4 nodes exists in the class -/
#guard_msgs in
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 4)

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (A B C : Prop) : (A → B) → (B → C) → A → C := by
  solve_by_sat [] (nodes := 2)

/-- error: solve_by_sat: no proof with at most 1 nodes exists in the class -/
#guard_msgs in
example (P Q : Nat → Prop) (a : Nat) (h : ∀ y, P y → Q y) (hp : P a) : Q a := by
  solve_by_sat [] (nodes := 1)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (n : Nat) : n ≤ n := by
  solve_by_sat [Nat.le_refl] (nodes := 0)

/-! ## G1, G2: grounding -/

-- G1: `y` (and `z`) are equated by unification but determined by nothing; the model
-- grounds them to `k`, the only Nat-typed candidate.
example (Q : Nat → Prop) (P0 : Prop) (k : Nat) (h : ∀ y, Q y → P0) (q : ∀ z, Q z) : P0 := by
  solve_by_sat [] (nodes := 2)

-- G2: without `k` there is no proof in the class (no Nat term occurs in the problem).
/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
example (Q : Nat → Prop) (P0 : Prop) (h : ∀ y, Q y → P0) (q : ∀ z, Q z) : P0 := by
  solve_by_sat [] (nodes := 2)

-- G2 without the static typing filter (changed in milestone 4): in milestone 2 the CNF
-- became satisfiable through the ill-typed grounding `y := Q` and the decoder refused it;
-- with the typing clause of 6.8 the closed types are compared in the CNF, so the answer
-- is the same as with the filter.
/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.staticTyping false in
example (Q : Nat → Prop) (P0 : Prop) (h : ∀ y, Q y → P0) (q : ∀ z, Q z) : P0 := by
  solve_by_sat [] (nodes := 2)

/-! ## R1 to R4: rejections (SPEC §2.1, §4.5) -/

/-- error: solve_by_sat: the head of Or.elim c has the clause variable c#4 as its head symbol -/
#guard_msgs in
example (A B : Prop) (h : A ∨ B) : A := by
  solve_by_sat [Or.elim] (nodes := 3)

-- R2 (changed by amendment 2 of milestone 3): a root hypothesis that is not a clause is
-- introduced but gives no clause; the call then finds no proof. The same statement as a
-- constant listed in H is still rejected (R2b).
/--
info: solve_by_sat: hypothesis h is introduced but gives no clause:
solve_by_sat: the clause variable f#0 is applied to arguments in f x: not first order
---
error: solve_by_sat: no proof with at most 3 nodes exists in the class
-/
#guard_msgs (whitespace := lax) in
set_option solve_by_sat.nodeBounds false in
set_option solve_by_sat.exclusivePairs false in
example (h : ∀ f : Nat → Nat, ∀ x, f x = x) : (1 : Nat) = 1 := by
  solve_by_sat [] (nodes := 3)

-- 8c-1: the same call with R1 on (M8_PLAN 3.4.3): the early exit, which says why with verbose
/--
info: solve_by_sat: hypothesis h is introduced but gives no clause:
solve_by_sat: the clause variable f#0 is applied to arguments in f x: not first order
---
info: solve_by_sat: early exit (node bounds): no proof tree exists at any N
---
error: solve_by_sat: no proof with at most 3 nodes exists in the class
-/
#guard_msgs (whitespace := lax) in
set_option solve_by_sat.nodeBounds true in
example (h : ∀ f : Nat → Nat, ∀ x, f x = x) : (1 : Nat) = 1 := by
  solve_by_sat [] (nodes := 3)

theorem appliedVar : ∀ (f : Nat → Nat) (x : Nat), f x = f x := fun _ _ => rfl

/-- error: solve_by_sat: the clause variable f#1 is applied to arguments in f x: not first order -/
#guard_msgs (whitespace := lax) in
example (a : Nat) : a = a := by
  solve_by_sat [appliedVar] (nodes := 3)

-- R4 (changed in milestone 4): universe-polymorphic constants are now compiled, so
-- `congrArg` is rejected for the reason SPEC §2.1 gives: the clause variable `f` is applied.
/-- error: solve_by_sat: the clause variable f#8 is applied to arguments in f a₁: not first order -/
#guard_msgs in
example (a b : Nat) (h : a = b) : b = a := by
  solve_by_sat [congrArg] (nodes := 3)

-- R4 (changed in milestone 5): `Nat.zero` is now a data constant (SPEC §6.9), so the call
-- succeeds (the constant is simply not needed); what is still rejected is a type former.
example : True := by
  solve_by_sat [Nat.zero] (nodes := 1)

/-- error: solve_by_sat: Nat is a type former (its result type is a Sort), neither a proof nor a data constant -/
#guard_msgs in
example : True := by
  solve_by_sat [Nat] (nodes := 1)
