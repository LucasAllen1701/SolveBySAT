/-
7d-1 review of the `solve_by_sat`-only goals (NOTES.md, "7d-1: merge and reviews"): how like-for-like
`solve_by_elim` (EVAL_PLAN §10.5 decision 3, `Test/EvalRun.lean` `sbe`) behaves. Minimal statements
only; no corpus goal is run. Run with `lake env lean eval/reviews/sbe_model.lean`.

T1: the step budget. `maxDepth := 10` allows at most 9 steps in all, and every `intro` the
    discharger makes is a step. Tier A goals are passed with `nctx = 0`, so all their binders cost steps.
T2, T3: `↔` lemmas and `∧` hypotheses are applied only as stated (no `Iff.mp`, no `And.left`).
T4, T5: the `constructor` discharger takes the first constructor that applies (`Or.inl`).
T6: `Lean.Grind.Order.eq_trans_true`'s statement with its `H_main` runs out of heartbeats with the
    binders left to `intro`, and closes with them introduced (the budget, not the step bound).
T7: an `Int.le_trans` proof closes with the binders introduced and fails as a Tier A goal (depth).
T8: `IsLongestMatchAt.eq`: `apply` fails to synthesize `PatternModel ?pat`, because `pat` is fixed only
    by the premises.
-/
import Lean
open Lean Meta Elab

/-- The harness's like-for-like `solve_by_elim` (Test/EvalRun.lean `sbe`, Test/EvalNumerals.lean
`sbeLike`): `introNP nctx`, local hypotheses first, then `H`, no defaults, depth 10,
`symm`/`exfalso` off, 200,000 heartbeats. -/
def sbeLike (goal : Expr) (nctx : Nat) (H : List Name) : MetaM String := do
  let cfg : SolveByElim.SolveByElimConfig := { maxDepth := 10, symm := false, exfalso := false }
  tryCatchRuntimeEx
    (withTheReader Core.Context (fun c => { c with maxHeartbeats := 200000 * 1000 }) <| withCurrHeartbeats do
      let m ← mkFreshExprMVar goal
      let (_, g) ← m.mvarId!.introNP nctx
      g.withContext do
        let ⟨_, ctx⟩ ← SolveByElim.mkAssumptionSet false false [] [] #[]
        let lemmas := H.map (fun c => (mkConstWithFreshMVarLevels c : Elab.TermElabM Expr))
        let rest ← SolveByElim.solveByElim cfg lemmas ctx [g]
        let t ← instantiateMVars m
        if rest.isEmpty && !t.hasExprMVar then return s!"closed: {← ppExpr t}" else return "open")
    fun e => do
      if e.isMaxHeartbeat then return "heartbeats"
      if e.isMaxRecDepth then return "max_rec_depth"
      return s!"failed: {((← e.toMessageData.toString).take 80).toString}"

def run (name : String) (stmt : Term) (nctx : Nat) (H : List Name) : TermElabM Unit := do
  let g ← Term.elabTerm stmt none
  Term.synthesizeSyntheticMVarsNoPostponing
  let g ← instantiateMVars g
  IO.println s!"{name}: {← sbeLike g nctx H}"

-- T1: the step budget. k intros (Tier A: nctx = 0) + 1 apply.
#eval show TermElabM Unit from do run "T1 k=7 intros + 1" (← `(∀ (a b c d e f g : Nat), a = a)) 0 [``Eq.refl]
#eval show TermElabM Unit from do run "T1 k=8 intros + 1" (← `(∀ (a b c d e f g h : Nat), a = a)) 0 [``Eq.refl]
#eval show TermElabM Unit from do run "T1 k=9 intros + 1" (← `(∀ (a b c d e f g h i : Nat), a = a)) 0 [``Eq.refl]
#eval show TermElabM Unit from do run "T1 k=9, 9 introduced by the harness (nctx), + 1" (← `(∀ (a b c d e f g h i : Nat), a = a)) 9 [``Eq.refl]
-- T2: an ↔ lemma used in one direction
#eval show TermElabM Unit from do run "T2 Iff.mpr of an H lemma" (← `(∀ (n : Nat), n ≠ 0 → 0 < n)) 2 [``Nat.pos_iff_ne_zero]
-- T3: an ∧ hypothesis
#eval show TermElabM Unit from do run "T3 And.left of a hypothesis" (← `(∀ (p q : Prop), p ∧ q → p)) 3 []
-- T4: Or.inr by the constructor discharger
#eval show TermElabM Unit from do run "T4 Or.inr, no H" (← `(∀ (p : Prop), p → False ∨ p)) 2 []
#eval show TermElabM Unit from do run "T4b Or.inl, no H" (← `(∀ (p : Prop), p → p ∨ False)) 2 []
-- T5: exists_or_eq_right with H = [rfl]
#eval show TermElabM Unit from do run "T5 exists_or_eq_right" (← `(∀ {α : Type} (y : α) (p : α → Prop), ∃ x, p x ∨ x = y)) 0 [``rfl]
-- T6: Eq.trans with general equality lemmas in H (Lean.Grind.Order.eq_trans_true's H_main)
#eval show TermElabM Unit from do run "T6 eq_trans_true, H_main" (← `(∀ (p q : Prop), p = q → q = True → p = True)) 0 [``Eq.symm, ``Eq.trans, ``congrArg, ``congrFun', ``eq_self, ``of_eq_true]
#eval show TermElabM Unit from do run "T6b same goal, hyps introduced, H_main" (← `(∀ (p q : Prop), p = q → q = True → p = True)) 4 [``Eq.symm, ``Eq.trans, ``congrArg, ``congrFun', ``eq_self, ``of_eq_true]
#eval show TermElabM Unit from do run "T6c same goal, hyps introduced, H = [Eq.trans]" (← `(∀ (p q : Prop), p = q → q = True → p = True)) 4 [``Eq.trans]
#eval show TermElabM Unit from do run "T6d same goal, hyps introduced, H = [Eq.trans, Eq.symm]" (← `(∀ (p q : Prop), p = q → q = True → p = True)) 4 [``Eq.trans, ``Eq.symm]
#eval show TermElabM Unit from do run "T7 Int.le_trans chain, 8 binders (Tier A)" (← `(∀ (a b c d : Int), a ≤ c → b ≤ d → 0 ≤ b → 0 ≤ c → a * b ≤ c * d)) 0 [``Int.le_trans, ``Int.mul_le_mul_of_nonneg_left, ``Int.mul_le_mul_of_nonneg_right]
#eval show TermElabM Unit from do run "T7b same, binders introduced" (← `(∀ (a b c d : Int), a ≤ c → b ≤ d → 0 ≤ b → 0 ≤ c → a * b ≤ c * d)) 8 [``Int.le_trans, ``Int.mul_le_mul_of_nonneg_left, ``Int.mul_le_mul_of_nonneg_right]

-- T8 (`String.Slice.Pattern.Model.IsLongestMatchAtChain.eq_of_isLongestMatchAt_self/4`)
open String.Slice.Pattern.Model in
#eval show TermElabM Unit from do run "T8 chain/4 context, nctx 15" (← `(∀ {ρ : Type} {pat : ρ} [inst : PatternModel pat] {s : String.Slice} {startPos endPos : s.Pos}
   (h : IsLongestMatchAtChain pat startPos endPos) (h' : IsLongestMatchAt pat startPos startPos)
   (p₁ p₂ p₃ : s.Pos) (h₁ : IsLongestMatchAt pat p₁ p₂) (h₂ : IsLongestMatchAtChain pat p₂ p₃)
   (ih : IsLongestMatchAt pat p₂ p₂ → p₂ = p₃) (h'' : IsLongestMatchAt pat p₁ p₁), p₁ = p₂)) 15 [``IsLongestMatchAt.eq]
open String.Slice.Pattern.Model in
#eval show TermElabM Unit from do run "T8b smaller context" (← `(∀ {ρ : Type} {pat : ρ} [inst : PatternModel pat] {s : String.Slice}
   (p₁ p₂ : s.Pos) (h₁ : IsLongestMatchAt pat p₁ p₂) (h'' : IsLongestMatchAt pat p₁ p₁), p₁ = p₂)) 6 [``IsLongestMatchAt.eq]

-- T8c: the `apply` error itself
open String.Slice.Pattern.Model in
#eval show TermElabM Unit from do
  let t ← Term.elabTerm (← `(∀ {ρ : Type} {pat : ρ} [inst : PatternModel pat] {s : String.Slice}
     (p₁ p₂ : s.Pos) (h₁ : IsLongestMatchAt pat p₁ p₂) (h'' : IsLongestMatchAt pat p₁ p₁), p₁ = p₂)) none
  let m ← mkFreshExprMVar (← instantiateMVars t)
  let (_, g) ← m.mvarId!.introNP 8
  g.withContext do
    try
      let gs ← g.apply (← mkConstWithFreshMVarLevels ``IsLongestMatchAt.eq)
      IO.println s!"apply ok: {← gs.mapM fun g => do return toString (← ppExpr (← g.getType))}"
    catch e => IO.println s!"apply failed: {← e.toMessageData.toString}"
    try
      let gs ← g.apply (← mkConstWithFreshMVarLevels ``IsLongestMatchAt.eq) { synthAssignedInstances := false }
      IO.println s!"apply (synthAssignedInstances := false) ok: {← gs.mapM fun g => do return toString (← ppExpr (← g.getType))}"
    catch e => IO.println s!"apply (synthAssignedInstances := false) failed: {← e.toMessageData.toString}"
