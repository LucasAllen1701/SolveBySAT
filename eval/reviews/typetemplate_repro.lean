import SolveBySat
set_option solve_by_sat.verbose true
universe u v

-- (1) `Not` is unfolded in the target but not in the type template of `instDecidableNot …`.
-- Lean proves it with the two lemmas: 2 nodes.
example (b : Bool) : decide (¬ b = true) = decide (b = false) :=
  Decidable.decide.congr_simp _ _ (Bool.not_eq_true b)
example (b : Bool) : decide (¬ b = true) = decide (b = false) := by
  solve_by_sat [Decidable.decide.congr_simp, Bool.not_eq_true] (nodes := 4)
-- the same with the type templates forgotten (testing option)
set_option solve_by_sat.forgetTypes true in
example (b : Bool) : decide (¬ b = true) = decide (b = false) := by
  solve_by_sat [Decidable.decide.congr_simp, Bool.not_eq_true] (nodes := 4)

-- (2) levels: `Eq.refl` on a type in `Type (max u v)`. The target's level is normalised to
-- `max (u+1) (v+1)`; `inferType` gives the type template `Sort (succ (max u v))`.
example {α : Type u} {β : Type v} (x : List (α × β)) : x = x := Eq.refl x
example {α : Type u} {β : Type v} (x : List (α × β)) : x = x := by
  solve_by_sat [Eq.refl] (nodes := 3)
example {α : Type u} (x : List α) : x = x := by
  solve_by_sat [Eq.refl] (nodes := 1)
