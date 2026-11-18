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

/-- Default node bound when `(nodes := N)` is omitted. -/
def defaultNodes : Nat := 8

/-- Prove the closed type `goal` from the constants `H` with at most `N` nodes. -/
def solveCore (goal : Expr) (H : Array Name) (N : Nat) : MetaM Expr := do
  let C ← compile goal H
  let C := if solve_by_sat.forgetTypes.get (← getOptions) then { C with forest := C.forest.forgetTypes } else C
  if solve_by_sat.verbose.get (← getOptions) then
    for note in C.notes do logInfo note
  if N == 0 then
    throwError "solve_by_sat: no proof with at most {N} nodes exists in the class"
  let opts ← getOptions
  let base : EncodeOptions := { staticTyping := solve_by_sat.staticTyping.get opts,
                                typingClause := solve_by_sat.typingClause.get opts }
  let E := encode C.forest N (if solve_by_sat.refinements.get opts then base else base.allOff)
  match ← runSolver E.cnf with
  | .unsat => throwError "solve_by_sat: no proof with at most {N} nodes exists in the class"
  | .sat model =>
    let t ← decode C E model
    if solve_by_sat.verbose.get (← getOptions) then
      if let .ok sk := readSkeleton C.forest E.vars model then
        logInfo m!"solve_by_sat: N = {N}, {E.cnf.nVars} variables, {E.cnf.clauses.size} clauses; \
          proof with {sk.size} nodes: {renderSkeleton C.forest sk 0}"
    return t

syntax solveBySatNodes := "(" &"nodes" " := " num ")"

/-- `solve_by_sat [h₁, …] (nodes := N)` searches for a backward-chaining proof of at most
`N` nodes (SPEC §2) using the constants `hᵢ` and the local context, by reduction to SAT. -/
syntax (name := solveBySat) "solve_by_sat" " [" ident,* "]" (ppSpace solveBySatNodes)? : tactic

elab_rules : tactic
  | `(tactic| solve_by_sat [$hs,*] $[$cfg]?) => do
    let N ← match cfg with
      | some c => match c with
        | `(solveBySatNodes| (nodes := $k)) => pure k.getNat
        | _ => throwUnsupportedSyntax
      | none => pure defaultNodes
    let H ← hs.getElems.mapM fun h => realizeGlobalConstNoOverloadWithInfo h
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
