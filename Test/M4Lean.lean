/-
Milestone 4 acceptance (SPEC §9 and the milestone 4 requirements): full typing clause of
6.8 and universe levels.
- E1: `(n : Nat) : n = n` with `[Eq.refl]` in 1 node (polymorphic `Eq.refl`), minimal;
- F2, F3 (SPEC §9.2) fail with the "no proof" message; E2 is F2 with the quantifiers
  swapped, which succeeds, so F2 fails because of scope;
- E3: the ill-typed grounding recorded under milestone 2 (`h : ∀ (S : Type) (y : S), P0`)
  now succeeds in 1 node with proof `h T t`;
- G2 with the static filter disabled gives "no proof" (also in Test/M2.lean);
- U1: with every type unknown (testing option), the decoder reports the documented
  limitation for candidates of unknown type, not a bug;
- S1, S2: CNF sizes of L1 and E1 before (typing clause off) and after the typing clause.

Run: `lake env lean Test/M4Lean.lean` — success means no errors. The unit test of label
allocation is `lake exe test_m4` (Test/M4.lean).
-/
import SolveBySat
set_option solve_by_sat.verbose true

open Lean Elab Tactic in
/-- `expect_error_with "p" => tac` succeeds iff `tac` fails with a message starting with
`p`; the goal is then left unchanged. -/
elab "expect_error_with " p:str " => " t:tactic : tactic => do
  let saved ← saveState
  let msg ← try
      evalTactic t
      pure none
    catch ex => pure (some (← ex.toMessageData.toString))
  saved.restore
  match msg with
  | none => throwError "expected an error starting with {repr p.getString}, but the tactic succeeded"
  | some m =>
    unless m.startsWith p.getString do
      throwError "expected an error starting with {repr p.getString}, got:\n{m}"
    logInfo m!"expected error: {(m.splitOn "\n").head!}"

/-! ## E1: polymorphic `Eq.refl` -/

example (n : Nat) : n = n := by
  solve_by_sat [Eq.refl] (nodes := 1)

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (n : Nat) : n = n := by
  solve_by_sat [Eq.refl] (nodes := 0)

/-! ## F2, F3 (verbatim from the spec, then with the exact message) -/

-- F2: eigenvariable escape
example : ∃ x : Nat, ∀ y : Nat, x = y := by
  fail_if_success solve_by_sat [Eq.refl] (nodes := 6)
  sorry
-- F3: needs computation, a documented limitation
example : 2 + 2 = 4 := by
  fail_if_success solve_by_sat [Eq.refl] (nodes := 6)
  sorry

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example : ∃ x : Nat, ∀ y : Nat, x = y := by
  solve_by_sat [Eq.refl] (nodes := 6)

/-- error: solve_by_sat: no proof with at most 6 nodes exists in the class -/
#guard_msgs in
example : 2 + 2 = 4 := by
  solve_by_sat [Eq.refl] (nodes := 6)

-- E2: F2 with the quantifiers swapped has a 2-node proof, so F2 fails because of scope.
example : ∀ y : Nat, ∃ x : Nat, x = y := by
  solve_by_sat [Eq.refl] (nodes := 2)

/-! ## E3: the milestone 2 ill-typed grounding, now decided by the typing clause -/

theorem E3 (T : Type) (P0 : Prop) (t : T) (Q : T → Prop) (h : ∀ (S : Type) (y : S), P0) : P0 := by
  solve_by_sat [] (nodes := 1)

/--
info: theorem E3 : ∀ (T : Type) (P0 : Prop) (t : T) (Q : T → Prop), (∀ (S : Type) (y : S), P0) → P0 :=
fun T P0 t Q h => h T t
-/
#guard_msgs in
#print E3

/-- error: solve_by_sat: no proof with at most 0 nodes exists in the class -/
#guard_msgs in
example (T : Type) (P0 : Prop) (t : T) (Q : T → Prop) (h : ∀ (S : Type) (y : S), P0) : P0 := by
  solve_by_sat [] (nodes := 0)

/-! ## G2 with the static filter disabled -/

/-- error: solve_by_sat: no proof with at most 2 nodes exists in the class -/
#guard_msgs in
set_option solve_by_sat.staticTyping false in
example (Q : Nat → Prop) (P0 : Prop) (h : ∀ y, Q y → P0) (q : ∀ z, Q z) : P0 := by
  solve_by_sat [] (nodes := 2)

/-! ## U1: candidates of unknown type -/

-- With every type unknown, `y : Nat` may be grounded to `Q` or `P0` with no typing
-- clause; the decoder reports the documented limitation, not a bug.
set_option solve_by_sat.forgetTypes true in
example (Q : Nat → Prop) (P0 : Prop) (h : ∀ y, Q y → P0) (q : ∀ z, Q z) : P0 := by
  expect_error_with "solve_by_sat: documented limitation" => solve_by_sat [] (nodes := 2)
  sorry

/-! ## S1, S2: CNF size before and after the typing clause -/

-- S1: L1 before / after
set_option solve_by_sat.typingClause false in
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)

-- S2: E1 before / after
set_option solve_by_sat.typingClause false in
example (n : Nat) : n = n := by
  solve_by_sat [Eq.refl] (nodes := 1)
example (n : Nat) : n = n := by
  solve_by_sat [Eq.refl] (nodes := 1)
