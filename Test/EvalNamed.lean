/-
Milestone 7b acceptance: the named tests of SPEC 9.1 (L1 to D7), as closed goals for the
evaluation harness. Each goal is the type the test's `solve_by_sat` call sees after
`revertAll`; `H`, options and expectations are those of Test/M2–M5Lean.lean.
-/

namespace EvalNamed

universe u v

def L1 : Prop := ∀ (x y z w : Nat), x ≤ y → y ≤ z → z ≤ w → x ≤ w
def L2 : Prop := ∀ (A B C : Prop), (A → B) → (B → C) → A → C
def L3 : Prop := ∀ (P Q : Nat → Prop) (a : Nat), (∀ y, P y → Q y) → P a → Q a
def L4 : Prop := ∀ (n : Nat), n ≤ n
def L5 : Prop := ∀ (A B : Prop), A → B → A ∧ B
def L6 : Prop := ∀ (A B : Prop), B → A ∨ B
def L7 : Prop := ∀ (a b : Nat), a ≤ b → ∃ x, x ≤ b
def L8 : Prop := ∀ (A B : Prop), A ∧ B → B
def F1 : Prop := ∀ (A : Prop), (A → A) ∧ A
def F2 : Prop := ∃ x : Nat, ∀ y : Nat, x = y
def F3 : Prop := 2 + 2 = 4
def G1 : Prop := ∀ (Q : Nat → Prop) (P0 : Prop) (k : Nat), (∀ y, Q y → P0) → (∀ z, Q z) → P0
def G2 : Prop := ∀ (Q : Nat → Prop) (P0 : Prop), (∀ y, Q y → P0) → (∀ z, Q z) → P0
def A1a : Prop := ∀ (A B : Prop), A ∨ B → A ∨ B
def A1b : Prop := ∀ (A B : Prop), A ∧ B → A ∧ B
def A1c : Prop := ∀ (P : Nat → Prop), (∃ x, P x) → ∃ x, P x
def A1d : Prop := ∀ (A B : Prop), (A ↔ B) → A → B
def A2 : Prop := ∀ (A : Prop), (∀ f : Nat → Nat, f 0 = 0) → A → A
def A3a : Prop := ∀ (R : Nat → Nat → Prop), (∀ n, R n n) → ∃ x, ∀ y, R x y
def A3b : Prop := ∀ (R : Nat → Nat → Prop), (∀ n, R n n) → ∀ y, ∃ x, R x y
def A4a : Prop := ∀ (g : Nat → Int) (k : Nat) (Q R : Int → Prop) (P0 : Prop),
  (∀ (y : Int) (u : Nat), Q y → R (g u) → P0) → (∀ y', Q y') → (∀ t, R t) → P0
def A4b : Prop := ∀ (R0 : Prop) (Q T : {x : Nat // x = 3} → Prop) (hp : 3 = 3),
  (∀ s, Q s → R0) → (∀ s, Q s) → (∀ s, T s) → R0 ∧ T ⟨3, hp⟩
def E1 : Prop := ∀ (n : Nat), n = n
def E3 : Prop := ∀ (T : Type) (P0 : Prop) (_t : T) (_Q : T → Prop), (∀ (S : Type) (_y : S), P0) → P0
theorem maxL (f : Sort (max u v) → Sort u) : f = f := rfl
def N1 : Prop := ∀ (f : Sort (max v u) → Sort u), f = f
def D1 : Prop := ∃ n : Nat, n ≤ n
def D2 : Prop := ∃ _n : Nat, True
def D3 : Prop := ∀ (Q : Nat → Prop), (∀ m, Q (Nat.succ m)) → ∃ n, Q n
def D4 : Prop := ∃ _i : Int, True
def D6 : Prop := ∃ n : Nat, Nat.succ n = 1
def D7 : Prop := ∃ n : Nat, n = 1

/-- (test, goal definition, H, options, expectation). Options: `nostatic` (static typing
filter off), `forgettypes`. Expectations: `min k` (smallest proof has k nodes), `none k`
(no proof at k nodes or fewer), `above k` (no proof at k nodes or fewer: F4),
`limitation` (the documented-limitation message). -/
def tests : List (String × Lean.Name × List Lean.Name × List String × String) := [
  ("L1", ``L1, [``Nat.le_trans], [], "min 5"),
  ("L2", ``L2, [], [], "min 3"),
  ("L3", ``L3, [], [], "min 2"),
  ("L4", ``L4, [``Nat.le_refl], [], "min 1"),
  ("L5", ``L5, [], [], "min 3"),
  ("L6", ``L6, [], [], "min 2"),
  ("L7", ``L7, [], [], "min 2"),
  ("L8", ``L8, [], [], "min 1"),
  ("F1", ``F1, [], [], "none 6"),
  ("F2", ``F2, [``Eq.refl], [], "none 6"),
  ("F3", ``F3, [``Eq.refl], [], "none 6"),
  ("F4", ``L1, [``Nat.le_trans], [], "above 4"),
  ("G1", ``G1, [], [], "min 2"),
  ("G2", ``G2, [], [], "none 2"),
  ("G2-nostatic", ``G2, [], ["nostatic"], "none 2"),
  ("A1a", ``A1a, [], [], "min 1"),
  ("A1b", ``A1b, [], [], "min 1"),
  ("A1c", ``A1c, [], [], "min 1"),
  ("A1d", ``A1d, [], [], "min 2"),
  ("A2", ``A2, [], [], "min 1"),
  ("A3a", ``A3a, [], [], "none 6"),
  ("A3b", ``A3b, [], [], "min 2"),
  ("A4a", ``A4a, [], [], "min 3"),
  ("A4b", ``A4b, [], [], "min 4"),
  ("E1", ``E1, [``Eq.refl], [], "min 1"),
  ("E3", ``E3, [], [], "min 1"),
  ("U1", ``G2, [], ["forgettypes"], "limitation"),
  ("N1", ``N1, [``maxL], [], "min 1"),
  ("D1", ``D1, [``Nat.le_refl, ``Nat.zero], [], "min 3"),
  ("D2a", ``D2, [``Nat.zero], [], "min 3"),
  ("D2b", ``D2, [], [], "none 6"),
  ("D3", ``D3, [``Nat.zero], [], "min 3"),
  ("D4", ``D4, [``Int.ofNat, ``Nat.zero], [], "min 4"),
  ("D5", ``A3a, [``Nat.zero, ``Nat.succ], [], "none 6"),
  ("D6", ``D6, [``Nat.succ, ``Nat.zero, ``Eq.refl], [], "none 6"),
  ("D7", ``D7, [``Eq.refl], [], "min 2")]

end EvalNamed
