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

A position i is *eligible* (§2.3, amendment 4.1 decision 3) if its binder is explicit, its value is a
term (its type is not a sort other than `Prop`, not a class, and not a proposition), no later binder's
type mentions it, and the symbol's result type does not mention it. A position whose type is `Prop` is
eligible and, since amendment 4.1 decision 1, uses `=` like every other position. Positions skipped
only because the result type depends on them are counted (`probe_skipped_dep`).

Rules, quantified over all the symbol's arguments (with their binder infos) and universe
parameters, for xs the arguments, a = xs[i], and a fresh b of the same type:
- `_probe.<f>.congr.<i>`     : ∀ xs b, a = b → f xs = f xs[i := b]
    := fun xs b h => congrArg (fun y => f xs[i := y]) h
- `_probe.<P>.subst.<i>`     : ∀ xs b, a = b → P xs[i := b] → P xs
    := fun xs b h hp => Eq.mpr (congrArg (fun y => P xs[i := y]) h) hp
- (amendment 4.1 decision 2) `_probe.<c>.propext.«<path>»`, for each accepted H_main constant c and each
  split path of its statement (SPEC 4.2: `∧` gives paths `l` and `r`, `↔` gives `mp` with extra premise
  the left side and `mpr` with extra premise the right side, and a `∀` component adds binders) whose
  head is `L ↔ R`: the same binders and premises, head `L = R`, proved by `propext` of the projected
  proof. The path is its steps joined by `_`, or `root` for the statement itself.
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

/-- Amendment 4.1 decision 3: does the symbol's result type `r` depend on position `i`? -/
def resultDepends (xs : Array Expr) (r : Expr) (i : Nat) : MetaM Bool := do
  return (← instantiateMVars r).containsFVar xs[i]!.fvarId!

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
    let _ := propPos   -- amendment 4.1 decision 1: a Prop position uses `=` too
    let kind := if k == .fn then "congr" else "subst"
    let n := ruleName c kind i
    -- built already in this environment (the test file's earlier examples): reuse it
    if (← getEnv).contains n then return Except.ok n
    try
      withLocalDeclD `b t fun b => do
        let hTy ← mkEq x b
        withLocalDeclD `h hTy fun h => do
          let motive ← withLocalDeclD `y t fun y => mkLambdaFVars #[y] (mkAppN f (xs.set! i y))
          let eqPf := h
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

def pathStr (p : List String) : String := if p.isEmpty then "root" else "_".intercalate p

/-- Amendment 4.1 decision 2: the `propext` equations of constant `c`, one per split path whose head
is `L ↔ R` (at most 6 split steps deep). Each is built, kernel-checked and added. -/
partial def propextEqs (c : Name) : MetaM (Array (Except String Name)) := do
  let ci ← getConstInfo c
  let lvls := ci.levelParams.map mkLevelParam
  let out ← IO.mkRef (#[] : Array (Except String Name))
  let rec go (fvars : Array Expr) (pf ty : Expr) (path : List String) : MetaM Unit := do
    if path.length > 6 then return
    forallTelescope ty fun ys body => do
      let fvars := fvars ++ ys
      let pf := mkAppN pf ys
      let body ← instantiateMVars body
      if body.isAppOfArity ``Iff 2 then
        let L := body.appFn!.appArg!
        let R := body.appArg!
        let n := Name.mkStr (Name.mkStr (`_probe ++ c) "propext") (pathStr path)
        if (← getEnv).contains n then out.modify (·.push (.ok n))
        else
          try
            let ty ← instantiateMVars (← mkForallFVars fvars (← mkEq L R))
            let val ← instantiateMVars (← mkLambdaFVars fvars (← mkPropExt pf))
            addDecl (.thmDecl { name := n, levelParams := ci.levelParams, type := ty, value := val })
            out.modify (·.push (.ok n))
          catch e => out.modify (·.push (.error s!"{n}: {← e.toMessageData.toString}"))
        withLocalDeclD `hl L fun hl => do go (fvars.push hl) (← mkAppM ``Iff.mp #[pf, hl]) R (path ++ ["mp"])
        withLocalDeclD `hr R fun hr => do go (fvars.push hr) (← mkAppM ``Iff.mpr #[pf, hr]) L (path ++ ["mpr"])
      else if body.isAppOfArity ``And 2 then
        go fvars (← mkAppM ``And.left #[pf]) body.appFn!.appArg! (path ++ ["l"])
        go fvars (← mkAppM ``And.right #[pf]) body.appArg! (path ++ ["r"])
  go #[] (mkConst c lvls) ci.type []
  out.get

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
  /-- (symbol, position, reason) of every eligible position whose rule failed to build (for a
  `propext` equation: the H constant, 0, and the reason) -/
  failed : Array (Name × Nat × String)
  /-- positions skipped because the symbol's result type depends on them (amendment 4.1 decision 3) -/
  skippedDep : Nat := 0

/-- Generate and add the rules for a goal (§2.3). -/
def generate (goal : Expr) (hmain : Array Name) : MetaM Rules := do
  let syms ← symbolsOf goal hmain
  let mut rules := #[]
  let mut failed := #[]
  let mut skippedDep := 0
  for c in syms do
    let some k ← symKind? c | continue
    let ci ← getConstInfo c
    let n ← forallTelescope ci.type fun xs _ => pure xs.size
    for i in [0:n] do
      -- 0: not eligible; 1: eligible but the result type depends on it (skipped, counted); 2: build
      let st ← forallTelescope ci.type fun xs r => do
        if (← eligible xs i).isNone then return 0
        if ← resultDepends xs r i then return 1
        return 2
      if st == 1 then skippedDep := skippedDep + 1
      unless st == 2 do continue
      match ← buildRule c k i with
      | .ok r => rules := rules.push r
      | .error msg => failed := failed.push (c, i, msg)
  for h in hmain do
    for r in ← propextEqs h do
      match r with
      | .ok n => rules := rules.push n
      | .error msg => failed := failed.push (h, 0, msg)
  return { symbols := syms, rules := rules.qsort (·.toString < ·.toString), failed, skippedDep }

/-- §2.3: H = the accepted H_main constants, then `Eq.refl`, `Eq.symm` and `Eq.trans` if they
are not already there, then the rules in name order. -/
def probeH (hmain : Array Name) (rules : Array Name) : Array Name := Id.run do
  let mut H := hmain
  for e in [``Eq.refl, ``Eq.symm, ``Eq.trans] do
    unless H.contains e do H := H.push e
  return H ++ rules

def rulesJson (R : Rules) : List (String × Json) :=
  [("probe_symbols", toJson R.symbols.size), ("probe_rules", toJson R.rules.size),
   ("probe_propext", toJson (R.rules.filter fun r => (r.toString.splitOn ".propext.").length > 1).size),
   ("probe_skipped_dep", toJson R.skippedDep),
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
