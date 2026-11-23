/-
Milestone 8a (M8_PLAN.md §2.3): the rewriting probe's rule generator. Harness code only:
nothing in `SolveBySat/` changes. The rules are ordinary theorems, added with `addDecl` (so the
kernel checks each one) and passed to the unchanged tactic in H.

For a goal, the *symbols* are the constants that occur in its preprocessed statement
(`SolveBySat.preprocess`, SPEC 4.1) and in the preprocessed statements of its accepted H_main
constants. A symbol is
- a *predicate symbol* if its type ends in `Prop` (it builds propositions: atom heads, `Eq`
  included);
- a *function symbol* if its type ends in a type that is not a sort (it builds terms);
- otherwise (type formers, which end in a sort other than `Prop`, and proofs, whose type ends in
  a proposition) it has no rules.
The argument positions are the binders of the symbol's type, read without reduction
(`forallTelescope`), numbered from 0.

A position i is *eligible* (§2.3) if its binder is explicit, its value is a term (its type is not
a sort other than `Prop`, not a class, and not a proposition), and no later binder's type mentions
it. A position whose type is `Prop` is eligible, and uses `↔` in place of `=`.

Rules, quantified over all the symbol's arguments (with their binder infos) and universe
parameters, for xs the arguments, a = xs[i], and a fresh b of the same type:
- `_probe.<f>.congr.<i>`     : ∀ xs b, a = b → f xs = f xs[i := b]
    := fun xs b h => congrArg (fun y => f xs[i := y]) h
- `_probe.<P>.subst.<i>`     : ∀ xs b, a = b → P xs[i := b] → P xs
    := fun xs b h hp => Eq.mpr (congrArg (fun y => P xs[i := y]) h) hp
- `_probe.<f>.congr_iff.<i>`, `_probe.<P>.subst_iff.<i>`: the same with `a ↔ b`, and
  `propext h` in place of `h`.
`<i>` is a string name component (`«0»`): a numeric component would be read as a macro scope
when the name goes through syntax, as in the test tactic. A rule that fails to build, or that the kernel rejects, is
recorded with its reason and left out; this is not a stop (§2.3, "Bookkeeping").
-/
import Lean
import SolveBySat

open Lean Meta

namespace M8

inductive SymKind where
  | fn | pred
  deriving BEq, Repr

/-- The kind of a symbol, or `none` if it has no rules (type former or proof). -/
def symKind? (c : Name) : MetaM (Option SymKind) := do
  let some ci := (← getEnv).find? c | return none
  forallTelescope ci.type fun _ r => do
    if r.isProp then return some .pred
    if r.isSort then return none
    if ← isProp r then return none
    return some .fn

/-- Is position `i` of the telescope `xs` eligible, and is it a `Prop` position? -/
def eligible (xs : Array Expr) (i : Nat) : MetaM (Option Bool) := do
  let x := xs[i]!
  let d ← x.fvarId!.getDecl
  unless d.binderInfo.isExplicit do return none
  let t ← instantiateMVars d.type
  let propPos := t.isProp
  unless propPos do
    if (← whnfR t).isSort then return none          -- a type
    if (← isClass? t).isSome then return none       -- an instance
    if ← isProp t then return none                  -- a proof
  for y in xs[i+1:] do                              -- another argument's type depends on it
    if (← inferType y).containsFVar x.fvarId! then return none
  return some propPos

def ruleName (c : Name) (kind : String) (i : Nat) : Name :=
  Name.mkStr (Name.mkStr (`_probe ++ c) kind) (toString i)

/-- Build, kernel-check and add one rule. -/
def buildRule (c : Name) (k : SymKind) (i : Nat) : MetaM (Except String Name) := do
  let ci ← getConstInfo c
  let lvls := ci.levelParams.map mkLevelParam
  let f := mkConst c lvls
  let res ← forallTelescope ci.type fun xs _ => do
    let some propPos ← eligible xs i | return Except.error "not eligible"
    let x := xs[i]!
    let t ← inferType x
    let kind := (if k == .fn then "congr" else "subst") ++ (if propPos then "_iff" else "")
    let n := ruleName c kind i
    -- built already in this environment (the test file's earlier examples): reuse it
    if (← getEnv).contains n then return Except.ok n
    try
      withLocalDeclD `b t fun b => do
        let hTy ← if propPos then pure (mkIff x b) else mkEq x b
        withLocalDeclD `h hTy fun h => do
          let motive ← withLocalDeclD `y t fun y => mkLambdaFVars #[y] (mkAppN f (xs.set! i y))
          let eqPf ← if propPos then mkPropExt h else pure h
          let cg ← mkAppM ``congrArg #[motive, eqPf]
          let lhs := mkAppN f xs
          let rhs := mkAppN f (xs.set! i b)
          let (ty, val) ← if k == .fn then do
              let ty ← mkForallFVars (xs ++ #[b, h]) (← mkEq lhs rhs)
              let val ← mkLambdaFVars (xs ++ #[b, h]) cg
              pure (ty, val)
            else
              withLocalDeclD `hp rhs fun hp => do
                let ty ← mkForallFVars (xs ++ #[b, h, hp]) lhs
                let val ← mkLambdaFVars (xs ++ #[b, h, hp]) (← mkEqMPR cg hp)
                pure (ty, val)
          let ty ← instantiateMVars ty
          let val ← instantiateMVars val
          if ty.hasMVar || val.hasMVar then return Except.error s!"{n}: metavariables remain"
          addDecl (.thmDecl { name := n, levelParams := ci.levelParams, type := ty, value := val })
          return Except.ok n
    catch e => return Except.error s!"{n}: {← e.toMessageData.toString}"
  return res

/-- The symbols of a goal: constants of its preprocessed statement and of the preprocessed
statements of `hmain` (its accepted H_main constants), sorted by name. -/
def symbolsOf (goal : Expr) (hmain : Array Name) : MetaM (Array Name) := do
  let mut s : NameSet := {}
  for c in (← SolveBySat.preprocess goal).getUsedConstants do s := s.insert c
  for h in hmain do
    let ci ← getConstInfo h
    for c in (← SolveBySat.preprocess ci.type).getUsedConstants do s := s.insert c
  return s.toArray.qsort (·.toString < ·.toString)

structure Rules where
  symbols : Array Name
  /-- built and kernel-checked, in name order -/
  rules : Array Name
  /-- (symbol, position, reason) of every eligible position whose rule failed to build -/
  failed : Array (Name × Nat × String)

/-- Generate and add the rules for a goal (§2.3). -/
def generate (goal : Expr) (hmain : Array Name) : MetaM Rules := do
  let syms ← symbolsOf goal hmain
  let mut rules := #[]
  let mut failed := #[]
  for c in syms do
    let some k ← symKind? c | continue
    let ci ← getConstInfo c
    let n ← forallTelescope ci.type fun xs _ => pure xs.size
    for i in [0:n] do
      let ok ← forallTelescope ci.type fun xs _ => do return (← eligible xs i).isSome
      unless ok do continue
      match ← buildRule c k i with
      | .ok r => rules := rules.push r
      | .error msg => failed := failed.push (c, i, msg)
  return { symbols := syms, rules := rules.qsort (·.toString < ·.toString), failed }

/-- §2.3: H = the accepted H_main constants, then `Eq.refl`, `Eq.symm` and `Eq.trans` if they
are not already there, then the rules in name order. -/
def probeH (hmain : Array Name) (rules : Array Name) : Array Name := Id.run do
  let mut H := hmain
  for e in [``Eq.refl, ``Eq.symm, ``Eq.trans] do
    unless H.contains e do H := H.push e
  return H ++ rules

def rulesJson (R : Rules) : List (String × Json) :=
  [("probe_symbols", toJson R.symbols.size), ("probe_rules", toJson R.rules.size),
   ("probe_rule_names", toJson (R.rules.map (·.toString))),
   ("probe_failed", Json.arr (R.failed.map fun (c, i, m) =>
      Json.arr #[Json.str c.toString, toJson i, Json.str m]))]

end M8

/-! ## Test tactic (hand examples, `Test/M8Probe.lean`)

`solve_by_sat_probe [h₁, …] (nodes := N)`: generate the rules for the current goal and the given
constants, then run the unchanged `solve_by_sat` with H as in §2.3. -/

open Lean Elab Tactic in
elab "solve_by_sat_probe" "[" hs:ident,* "]" "(" &"nodes" ":=" n:num ")" : tactic => do
  let hmain ← hs.getElems.mapM fun h => realizeGlobalConstNoOverloadWithInfo h
  -- the goal's statement: the target closed over the local context, as the harness's closed goals
  let goal ← (← getMainGoal).withContext do
    let fvars := (← getLCtx).foldl (init := #[]) fun acc d => if d.isImplementationDetail then acc else acc.push d.toExpr
    instantiateMVars (← mkForallFVars fvars (← getMainTarget))
  let R ← M8.generate goal hmain
  unless R.failed.isEmpty do
    logInfo m!"rules that failed to build: {R.failed.toList.map fun (c, i, m) => s!"{c} {i}: {m}"}"
  -- as the harness does (`runSat`): compile each constant on its own and leave out rejected ones
  let mut H := #[]
  let mut rej := #[]
  for c in M8.probeH hmain R.rules do
    try discard <| SolveBySat.compile goal #[c]; H := H.push c
    catch e => rej := rej.push m!"{c}: {e.toMessageData}"
  unless rej.isEmpty do logInfo m!"rejected by the compiler: {rej.toList}"
  let ids : Array Ident := H.map mkIdent
  evalTactic (← `(tactic| solve_by_sat [$ids,*] (nodes := $n)))
