/-
Milestone 7c (EVAL_PLAN §10.9, step 3 of the 7c instructions): before counting the synthetic
grid, the chain itself is proved by the tactic through the compile path. k = 0 is the goal with
`Nat.le_trans` alone (every family's k = 0 cell); k = 4 adds the first four distractors of each
family, all at N = 5. Each proof is kernel-checked by the tactic.
-/
import SolveBySat
import Test.Synth

theorem chain_k0 : ∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)

theorem chain_S_k4 : ∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w := by
  solve_by_sat [Nat.le_trans, Synth.S.mono0, Synth.S.mono1, Synth.S.mono2, Synth.S.mono3] (nodes := 5)

theorem chain_T1_k4 : ∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w := by
  solve_by_sat [Nat.le_trans, Synth.T1.mono0, Synth.T1.mono1, Synth.T1.mono2, Synth.T1.mono3] (nodes := 5)

theorem chain_T2_k4 : ∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w := by
  solve_by_sat [Nat.le_trans, Synth.T2.mono0, Synth.T2.mono1, Synth.T2.mono2, Synth.T2.mono3] (nodes := 5)

theorem chain_T3_k4 : ∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w := by
  solve_by_sat [Nat.le_trans, Synth.T3.mono0, Synth.T3.mono1, Synth.T3.mono2, Synth.T3.mono3] (nodes := 5)

-- The proofs use no axiom beyond the distractors named in H (none are needed: the 5-node
-- chain `le_trans(h1, le_trans(h2, h3))` uses `Nat.le_trans` and the hypotheses only).
#print axioms chain_k0
#print axioms chain_T3_k4
