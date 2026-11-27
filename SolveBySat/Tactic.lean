/-
SolveBySat.Tactic: `solve_by_sat [h₁, …] (nodes := N)`.

Reverts the whole local context so the goal is closed, compiles it with the listed
constants, encodes with node bound `N`, runs the SAT solver, and decodes. On UNSAT the
tactic fails with "no proof with at most N nodes". The decoded term closes the goal, so
the kernel checks it with the declaration.
-/
import Lean
import SolveBySat.Compile
import SolveBySat.Encode
import SolveBySat.Solver
import SolveBySat.Decode

namespace SolveBySat

open Lean Meta Elab Tactic

register_option solve_by_sat.verbose : Bool := {
  defValue := false
  descr := "solve_by_sat: report the CNF size and the decoded proof skeleton"
}

register_option solve_by_sat.staticTyping : Bool := {
  defValue := true
  descr := "solve_by_sat (testing only): the static half of the typing rule of SPEC §6.8"
}

register_option solve_by_sat.typingClause : Bool := {
  defValue := true
  descr := "solve_by_sat (testing only): the typing clause of SPEC §6.8"
}

register_option solve_by_sat.forgetTypes : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): treat every type template as unknown, to exercise \
    the decoder's documented limitation for candidates of unknown type"
}

/-- Every type template unknown (testing only). -/
def Forest.forgetTypes (F : Forest) : Forest :=
  { F with varTypes := F.varTypes.map (fun (b, _) => (b, none)),
           groundTypes := F.groundTypes.map (fun (t, _) => (t, none)),
           goals := F.goals.map fun g => { g with tgtTypes := g.tgtTypes.map fun (p, _) => (p, none) },
           clauses := F.clauses.map fun c => { c with headTypes := c.headTypes.map fun (p, _) => (p, none) } }

register_option solve_by_sat.refinements : Bool := {
  defValue := true
  descr := "solve_by_sat: the refinements of SPEC §6.10 and the ladder at-most-one encoding"
}

register_option solve_by_sat.nodeBounds : Bool := {
  defValue := ({} : EncodeOptions).nodeBounds
  descr := "solve_by_sat: refinement R1 (milestone 8), node–clause bounds from least depth and least \
    proof size, with the early exit when no proof has at most N nodes; off if \
    solve_by_sat.refinements is off"
}

register_option solve_by_sat.exclusivePairs : Bool := {
  defValue := ({} : EncodeOptions).exclusivePairs
  descr := "solve_by_sat: refinement R2 (milestone 8), no decomposition clauses between two objects \
    at the same node that are never active together; off if solve_by_sat.refinements is off"
}

register_option solve_by_sat.iffEq : Bool := {
  defValue := ({} : CompileOptions).iffEq
  descr := "solve_by_sat: milestone 9a-1 (M9_PLAN 2.1), every clause with an `↔` head `L ↔ R`, on any \
    split path, also gives the clauses with heads `L = R` (by `propext`) and `R = L` (by `Eq.symm`); \
    also `(iffEq := true)` in the tactic call"
}

register_option solve_by_sat.iffEqMutant : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): the mutation check of M9_PLAN 2.2, the decoder's recipes of \
    the two `iffEq` paths swapped"
}

register_option solve_by_sat.rewrite : Bool := {
  defValue := ({} : CompileOptions).rewrite
  descr := "solve_by_sat: milestone 9a-2 (M9_PLAN 3.1), equality rules made per use: substitution and \
    congruence at the term positions on rewriting paths, and `Eq.refl`, `Eq.symm`, `Eq.trans` at each \
    type at which an equation occurs; also `(rewrite := true)` in the tactic call"
}

register_option solve_by_sat.eqTrans : Bool := {
  defValue := ({} : CompileOptions).eqTrans
  descr := "solve_by_sat: with solve_by_sat.rewrite, the equality core includes `Eq.trans` \
    (M9_PLAN 3.1); also `(eqTrans := false)` in the tactic call"
}

register_option solve_by_sat.rewriteSymbols : String := {
  defValue := ""
  descr := "solve_by_sat: with solve_by_sat.rewrite, the source symbols (constants, separated by \
    commas) in place of the automatic choice (M9_PLAN 3.1); empty: automatic; also \
    `(rewriteSymbols := [c₁, …])` in the tactic call"
}

register_option solve_by_sat.rewriteIneligibleMutant : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): the mutation check of M9_PLAN 3.2, rules also at positions \
    that are not term positions"
}

register_option solve_by_sat.rewriteContextMutant : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): the mutation check of M9_PLAN 3.2, each rule's proof taken \
    from a rule of the same kind, symbol and position in another context"
}

register_option solve_by_sat.rewriteLiberal : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): the mutation check of M9_PLAN 3.2, selection dropped (every \
    liberal candidate gets a rule)"
}

register_option solve_by_sat.checkBounds : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): check that every node of a decoded proof satisfies R1's \
    node–clause bounds (M8_PLAN 3.4.5, the model check), whether or not R1 is on"
}

/-- Default node bound when `(nodes := N)` is omitted. -/
def defaultNodes : Nat := 8

/-- The compiler options from the `solve_by_sat.*` options. -/
def compileOptionsOf (opts : Options) : CompileOptions :=
  let syms := solve_by_sat.rewriteSymbols.get opts
  { iffEq := solve_by_sat.iffEq.get opts, iffEqMutant := solve_by_sat.iffEqMutant.get opts,
    rewrite := solve_by_sat.rewrite.get opts, eqTrans := solve_by_sat.eqTrans.get opts,
    rewriteSymbols := if syms.trimAscii.isEmpty then none else
      some ((syms.splitOn ",").toArray.map fun s => s.trimAscii.toString.toName),
    rewriteIneligibleMutant := solve_by_sat.rewriteIneligibleMutant.get opts,
    rewriteContextMutant := solve_by_sat.rewriteContextMutant.get opts,
    rewriteLiberal := solve_by_sat.rewriteLiberal.get opts }

/-- 9a-2: the rules by kind and row, `kind: row n, …` (kinds and rows with none left out). -/
def Compiled.ruleSummary (C : Compiled) : String :=
  let kinds := #[Rules.Kind.subst, .congr, .refl, .symm, .trans]
  let rows := #[Rules.Row.ground, .root, .hvars]
  let parts := kinds.filterMap fun k =>
    let cs := rows.filterMap fun r =>
      let n := (C.rules.filter fun R => R.key.kind == k && R.key.row == r).size
      if n == 0 then none else some s!"{r.name} {n}"
    if cs.isEmpty then none else some s!"{k.name}: {", ".intercalate cs.toList}"
  "; ".intercalate parts.toList

/-- 9a-2: a rule as its clause, `name: head ← premise, …`. -/
def Compiled.ruleLine (C : Compiled) (R : RuleInfo) : String :=
  let cl := C.forest.clauses[R.clause]!
  let ps := cl.prems.toList.map fun g => toString C.forest.goals[g]!.tgt
  s!"{R.name}: {cl.head}{if ps.isEmpty then "" else " ← " ++ ", ".intercalate ps}"

/-- Prove the closed type `goal` from the constants `H` with at most `N` nodes. -/
def solveCore (goal : Expr) (H : Array Name) (N : Nat) : MetaM Expr := do
  let C ← compile goal H (compileOptionsOf (← getOptions))
  let C := if solve_by_sat.forgetTypes.get (← getOptions) then { C with forest := C.forest.forgetTypes } else C
  if solve_by_sat.verbose.get (← getOptions) then
    for note in C.notes do logInfo note
    -- only when some were added, so that `verbose` says nothing new for a goal without `↔` heads
    let (g, l) := C.iffEqCounts
    if C.opts.iffEq && g + l > 0 then
      logInfo m!"solve_by_sat: iffEq: {g + l} propext paths added ({g} from constants of H, {l} from local hypotheses)"
    -- 9a-2: likewise only when some rules were made
    if C.opts.rewrite && !C.rules.isEmpty then
      logInfo m!"solve_by_sat: rewrite: {C.rules.size} rules ({C.ruleSummary})\n{"\n".intercalate (C.rules.toList.map C.ruleLine)}"
  if N == 0 then
    throwError "solve_by_sat: no proof with at most {N} nodes exists in the class"
  let opts ← getOptions
  let base : EncodeOptions := { staticTyping := solve_by_sat.staticTyping.get opts,
                                typingClause := solve_by_sat.typingClause.get opts,
                                nodeBounds := solve_by_sat.nodeBounds.get opts,
                                exclusivePairs := solve_by_sat.exclusivePairs.get opts }
  let E := encode C.forest N (if solve_by_sat.refinements.get opts then base else base.allOff)
  -- R1's early exit: no proof has at most N nodes, so nothing was encoded or solved
  if E.info.earlyExit then
    if solve_by_sat.verbose.get opts then
      logInfo m!"solve_by_sat: early exit (node bounds): {match E.info.rootSize with
        | some k => s!"every proof has at least {k} nodes, more than N = {N}"
        | none => "no proof tree exists at any N"}"
    throwError "solve_by_sat: no proof with at most {N} nodes exists in the class"
  match ← runSolver E.cnf with
  | .unsat => throwError "solve_by_sat: no proof with at most {N} nodes exists in the class"
  | .sat model =>
    let t ← decode C E model
    -- the model check of R1 (testing only): the pairs used satisfy the bounds
    if solve_by_sat.checkBounds.get opts then
      let B := NodeBounds.compute C.forest
      match readSkeleton C.forest E.vars model with
      | .error e => throwError "solve_by_sat: internal: {e}"
      | .ok sk =>
        for n in sk do
          unless B.gpLive N n.node n.goal && B.clLive N n.node n.clause do
            throwError "solve_by_sat: internal: node {n.node} of the decoded proof (goal position \
              {n.goal}, clause {n.clause}) violates the node bounds (M8_PLAN 3.4)"
    if solve_by_sat.verbose.get (← getOptions) then
      if let .ok sk := readSkeleton C.forest E.vars model then
        logInfo m!"solve_by_sat: N = {N}, {E.cnf.nVars} variables, {E.cnf.clauses.size} clauses; \
          proof with {sk.size} nodes: {renderSkeleton C.forest sk 0}"
    return t

syntax solveBySatNodes := "(" &"nodes" " := " num ")"
syntax solveBySatIffEq := "(" &"iffEq" " := " (&"true" <|> &"false") ")"
syntax solveBySatRewrite := "(" &"rewrite" " := " (&"true" <|> &"false") ")"
syntax solveBySatEqTrans := "(" &"eqTrans" " := " (&"true" <|> &"false") ")"
syntax solveBySatRewriteSymbols := "(" &"rewriteSymbols" " := " "[" ident,* "]" ")"

/-- `solve_by_sat [h₁, …] (nodes := N) (iffEq := b) (rewrite := b) (eqTrans := b)
(rewriteSymbols := [c₁, …])` searches for a backward-chaining proof of at most `N` nodes (SPEC §2)
using the constants `hᵢ` and the local context, by reduction to SAT. Every argument is optional, and
they come in this order. `(iffEq := b)` sets the option `solve_by_sat.iffEq` (M9_PLAN 2.1) for this
call; `(rewrite := b)`, `(eqTrans := b)` and `(rewriteSymbols := […])` set `solve_by_sat.rewrite`,
`solve_by_sat.eqTrans` and `solve_by_sat.rewriteSymbols` (M9_PLAN 3.1). -/
syntax (name := solveBySat) "solve_by_sat" " [" ident,* "]" (ppSpace atomic(solveBySatNodes))?
  (ppSpace atomic(solveBySatIffEq))? (ppSpace atomic(solveBySatRewrite))? (ppSpace atomic(solveBySatEqTrans))?
  (ppSpace solveBySatRewriteSymbols)? : tactic

elab_rules : tactic
  | `(tactic| solve_by_sat [$hs,*] $[$cfg]? $[$ie]? $[$rw]? $[$et]? $[$rs]?) => do
    let N ← match cfg with
      | some c => match c with
        | `(solveBySatNodes| (nodes := $k)) => pure k.getNat
        | _ => throwUnsupportedSyntax
      | none => pure defaultNodes
    -- a value `(&"true" <|> &"false")` is a node of kind `token.true` / `token.false`
    let boolOf := fun (s : Syntax) => s[3].getKind == `token.true || s[3][0].getAtomVal == "true"
    let iffEq? : Option Bool := ie.map (boolOf ·.raw)
    let rewrite? : Option Bool := rw.map (boolOf ·.raw)
    let eqTrans? : Option Bool := et.map (boolOf ·.raw)
    let syms? : Option String ← match rs with
      | some s => match s with
        | `(solveBySatRewriteSymbols| (rewriteSymbols := [$cs,*])) => do
          let ns ← cs.getElems.mapM fun c => realizeGlobalConstNoOverloadWithInfo c
          pure (some (",".intercalate (ns.toList.map toString)))
        | _ => throwUnsupportedSyntax
      | none => pure none
    let H ← hs.getElems.mapM fun h => realizeGlobalConstNoOverloadWithInfo h
    withOptions (fun o =>
      let o := match iffEq? with | some b => solve_by_sat.iffEq.set o b | none => o
      let o := match rewrite? with | some b => solve_by_sat.rewrite.set o b | none => o
      let o := match eqTrans? with | some b => solve_by_sat.eqTrans.set o b | none => o
      match syms? with | some v => solve_by_sat.rewriteSymbols.set o v | none => o) <|
    liftMetaTactic fun g => do
      let g ← g.revertAll
      g.withContext do
        let goal ← instantiateMVars (← g.getType)
        let t ← solveCore goal H N
        unless ← isDefEq (← inferType t) goal do
          throwError "solve_by_sat: internal: the decoded term does not have the goal type"
        g.assign t
        return []

end SolveBySat
