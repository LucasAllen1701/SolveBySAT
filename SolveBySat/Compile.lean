/-
SolveBySat.Compile: from a closed Lean goal and a list of constants to a clause forest
(SPEC §4), with the rejection messages of §4.5.

Milestones 2 and 3: `∀`, `→`, atoms, connectives in targets (built-in clauses) and heads
(splitting), and binders inside terms (`lam`/`pi`, needed for the opaque atom of `∃`).
Milestone 4: universe parameters of constants in `H` are level variables. Data constants
are milestone 5; until then they are rejected with a message naming the milestone.
Milestone 9a-1 (M9_PLAN 2.1): with `CompileOptions.iffEq`, every `↔` head on any split path
also gives the paths `L = R` (`propext`) and `R = L` (`Eq.symm` of it).
Milestone 9a-2 (M9_PLAN 3.1, amendment 6.1): with `CompileOptions.rewrite`, equality rules made per
use (substitution, congruence and the equality core) are added as clauses; see `addRules`.
-/
import Lean
import SolveBySat.Forest

namespace SolveBySat

open Lean Meta

/-! ## Preprocessing (SPEC §4.1) -/

register_option solve_by_sat.checkTemplates : Bool := {
  defValue := false
  descr := "solve_by_sat (testing only): assert that every type template is built from a type \
    that preprocessing leaves unchanged (EVAL_PLAN §10.7)"
}

/-- Remove every `mdata` node (the templates ignore metadata). -/
def stripMData (e : Expr) : MetaM Expr :=
  Core.transform e (pre := fun x => match x with
    | .mdata _ y => return .visit y
    | _ => return .continue)

/-- Definitions unfolded by preprocessing, and nothing else. -/
def unfoldedConsts : List Name := [``Not, ``Ne, ``GE.ge, ``GT.gt]

/-- Instantiate metavariables, inline `let`, strip metadata, β-reduce, unfold `Not`, `Ne`,
`GE.ge`, `GT.gt` (when fully applied), and normalise universe levels (`Level.normalize`:
`max` arguments sorted, subsumed terms absorbed, `succ` pushed inside `max`). No `whnf`,
no other unfolding. -/
def preprocess (e : Expr) : MetaM Expr := do
  let e ← instantiateMVars e
  let e ← zetaReduce e
  let e ← Core.transform e (pre := fun e => do
    match e with
    | .mdata _ x => return .visit x
    | _ =>
      let f := e.getAppFn
      if let .const c ls := f then
        if unfoldedConsts.contains c then
          let info ← getConstInfoDefn c
          let arity := info.type.getForallBinderNames.length
          if e.getAppNumArgs ≥ arity then
            let v ← instantiateValueLevelParams (.defnInfo info) ls
            return .visit (v.beta e.getAppArgs)
      return .continue)
  let e ← Core.betaReduce e
  return e.replaceLevel fun l => some l.normalize

/-! ## Template decomposition, shared with the decoder -/

inductive Piece where
  | expr (e : Expr)
  | level (l : Level)

/-- The symbol and children of a rigid template node (SPEC §4.4 table). For an atom
(`atom := true`), an eigenvariable head is wrapped in `app` even without arguments. A
binder `fun x : τ => b` / `∀ x : τ, b` has children `τ` and `b`, with `b`'s bound variable
loose. The decoder navigates instantiated expressions with the same function, so template
paths and expression positions agree by construction. -/
def decompose (e : Expr) (atom : Bool := false) : Except String (String × Array Piece) :=
  let e := e.consumeMData
  let f := e.getAppFn.consumeMData
  let args := e.getAppArgs.map Piece.expr
  match f with
  | .const c ls => .ok (s!"c:{c}", ls.toArray.map Piece.level ++ args)
  | .fvar _ =>
    if atom || !args.isEmpty then .ok ("app", #[Piece.expr f] ++ args)
    else .error "a variable is not a rigid term"
  | .sort l => if args.isEmpty then .ok ("sort", #[.level l]) else .error "ill-formed application of a sort"
  | .lit (.natVal n) => .ok (s!"lit:{n}", args)
  | .lit (.strVal s) => .ok (s!"lit:{s.quote}", args)
  | .proj S i x => .ok (s!"proj:{S}:{i}", #[Piece.expr x] ++ args)
  | .lam _ d b _ => if args.isEmpty then .ok ("lam", #[.expr d, .expr b]) else .error "a β-redex"
  | .forallE _ d b _ => if args.isEmpty then .ok ("pi", #[.expr d, .expr b]) else .error "ill-formed application of a ∀"
  | .letE .. => .error "a let inside a term"
  | .mvar _ => .error "a metavariable"
  | .bvar _ => .error "a loose bound variable"
  | .app .. | .mdata .. => .error "internal: unexpected application head"

/-! ## Compiled forest with the information the decoder needs -/

/-- How one binder of a goal position or clause is used, in binder order. -/
inductive BinderUse where
  /-- An eigenvariable or clause variable, by static name. -/
  | static (name : String)
  /-- A local hypothesis of a goal position (it gives one clause per split path). -/
  | hyp
  /-- A premise of a clause: its index among the clause's premises. -/
  | prem (k : Nat)
  deriving Inhabited, Repr, BEq

/-- Head splitting (SPEC §4.2): which component of an `∧` / `↔` head a clause uses. With
`iffEq` (M9_PLAN 2.1), an `↔` head `L ↔ R` also gives the head `L = R` (`propEq`) and the
head `R = L` (`propEqSymm`), each an `Eq` atom at type `Prop` that ends its path. -/
inductive Split where
  | left | right | mp | mpr | propEq | propEqSymm
  deriving Inhabited, Repr, BEq

def Split.suffix : Split → String
  | .left => "left" | .right => "right" | .mp => "mp" | .mpr => "mpr"
  | .propEq => "propext" | .propEqSymm => "propext_symm"

/-- Options of the compiler. Every one is off by default, and with all of them off the
forest is exactly milestone 8's. -/
structure CompileOptions where
  /-- M9_PLAN 2.1: `↔` heads also give the equations `L = R` and `R = L` between propositions. -/
  iffEq : Bool := false
  /-- Mutation check of M9_PLAN 2.2 (testing only): the recipes of the two `iffEq` paths are
  swapped, so the decoder builds `L = R` for the path whose head is `R = L` and conversely. -/
  iffEqMutant : Bool := false
  /-- M9_PLAN 3.1: equality rules made per use, selected on rewriting paths (`addRules`). -/
  rewrite : Bool := false
  /-- M9_PLAN 3.1: the equality core includes `Eq.trans` (only with `rewrite`). -/
  eqTrans : Bool := true
  /-- M9_PLAN 3.1: the source symbols, in place of the automatic choice (only with `rewrite`). -/
  rewriteSymbols : Option (Array Name) := none
  /-- Mutation checks of M9_PLAN 3.2 (testing only): rules also at positions that are not term
  positions (`Ineligible`, for the static motive check); each rule's proof taken from a rule of the
  same kind, symbol and position in another context (`Context`); every liberal candidate built
  (`Liberal`, selection dropped). -/
  rewriteIneligibleMutant : Bool := false
  rewriteContextMutant : Bool := false
  rewriteLiberal : Bool := false
  deriving Inhabited, Repr

/-- How the decoder builds the proof of a clause's head from the proof of its statement. -/
inductive Step where
  /-- Open the next binders as metavariables. -/
  | binders (uses : Array BinderUse)
  | andLeft
  | andRight
  /-- `Iff.mp`; the extra premise has index `k`. -/
  | iffMp (k : Nat)
  | iffMpr (k : Nat)
  /-- M9_PLAN 2.1: `propext : (L ↔ R) → L = R`. -/
  | propEq
  /-- M9_PLAN 2.1: `Eq.symm (propext _) : R = L`. -/
  | propEqSymm
  deriving Inhabited, Repr, BEq

inductive Builtin where
  | andIntro | orInl | orInr | existsIntro | iffIntro | trueIntro
  deriving Inhabited, Repr, BEq

inductive ClauseOrigin where
  | global (c : Name)
  /-- Binder `idx` of goal position `goal`. -/
  | localHyp (goal : Nat) (idx : Nat)
  /-- A connective rule of the goal position the clause is local to. -/
  | builtin (k : Builtin)
  /-- 9a-2: equality rule `k` of `Compiled.rules`. -/
  | rule (k : Nat)
  deriving Inhabited, Repr

structure GoalInfo where
  binders : Array BinderUse := #[]
  deriving Inhabited, Repr

structure ClauseInfo where
  origin : ClauseOrigin := .global .anonymous
  steps : Array Step := #[]
  /-- Static names of the level variables, in the constant's universe-parameter order. -/
  levelVars : Array String := #[]
  /-- A data clause (SPEC §6.9): its node builds a value. -/
  isData : Bool := false
  deriving Inhabited, Repr

/-- 9a-2: an equality rule as built (M9_PLAN 3.1). Its statement and proof are closed but for the
universe parameters `levelParams`; for a rule local to the root, both are abstracted over the root's
binders (all of them, in order), which the decoder applies to the root node's free variables. -/
structure RuleInfo where
  key : Rules.Key
  name : String
  clause : Nat
  stmt : Expr
  proof : Expr
  levelParams : List Name := []
  rootLocal : Bool := false
  /-- 8a's position (substitution and congruence). -/
  pos8a : Nat := 0
  deriving Inhabited

/-- 9a-2: what the selection found and what was built (M9_PLAN 3.3's records). -/
structure RuleStats where
  sources : Nat := 0
  symbols : Array String := #[]
  /-- Liberal candidates not in the strict selection (substitution and congruence keys). -/
  liberalExtra : Array Rules.Key := #[]
  broken : Nat := 0
  noRow : Nat := 0
  /-- Rules dropped: by the static motive check, or because their statement could not be compiled. -/
  dropped : Array (String × String) := #[]
  /-- The term positions of the forest's symbols (for 8a's numbering of the keys above). -/
  sigs : Rules.Sigs := {}
  /-- Every liberal candidate (substitution and congruence keys), strict ones included. -/
  liberal : Array Rules.Key := #[]
  deriving Inhabited

structure Compiled where
  forest : Forest
  goalInfo : Array GoalInfo
  clauseInfo : Array ClauseInfo
  /-- A closed representative expression for each ground template term that has one. -/
  groundExprs : Std.HashMap Term Expr
  /-- The preprocessed goal type. -/
  goalType : Expr
  /-- Root hypotheses (or split components of them) that gave no clause, with the reason. -/
  notes : Array MessageData := #[]
  /-- The options it was compiled with. -/
  opts : CompileOptions := {}
  /-- 9a-2: the equality rules (clause origin `.rule k`). -/
  rules : Array RuleInfo := #[]
  ruleStats : RuleStats := {}

/-- M9_PLAN 2.1: is a clause one of the `iffEq` paths (its last split is `propEq` or
`propEqSymm`)? -/
def ClauseInfo.isIffEq (ci : ClauseInfo) : Bool :=
  ci.steps.any fun s => s == .propEq || s == .propEqSymm

/-- The number of `iffEq` (`propext`) paths compiled: from constants of `H`, and from local
hypotheses. -/
def Compiled.iffEqCounts (C : Compiled) : Nat × Nat :=
  C.clauseInfo.foldl (init := (0, 0)) fun (g, l) ci =>
    if !ci.isIffEq then (g, l) else match ci.origin with
      | .global _ => (g + 1, l)
      | .localHyp .. => (g, l + 1)
      | _ => (g, l)

/-! ## Compilation -/

inductive FVKind where
  | eig (name : String)
  | cvar (name : String)
  | proof
  /-- A variable bound inside a term, opened at binder depth `level`. -/
  | bound (level : Nat)

structure CState where
  goals : Array GoalPos := #[]
  clauses : Array Clause := #[]
  goalInfo : Array GoalInfo := #[]
  clauseInfo : Array ClauseInfo := #[]
  kinds : Std.HashMap FVarId FVKind := {}
  varTypes : Array (String × Option Term) := #[]
  groundTypes : Std.HashMap Term (Option Term) := {}
  groundOrder : Array Term := #[]
  groundExprs : Std.HashMap Term Expr := {}
  /-- Types of the rigid positions of the atom being compiled. -/
  posTypes : Array (Array Nat × Option Term) := #[]
  /-- Number of term binders currently open (for de Bruijn indices). -/
  depth : Nat := 0
  counter : Nat := 0
  notes : Array MessageData := #[]
  /-- Universe parameters of the constant being compiled → level variables. -/
  levelMap : Std.HashMap Name String := {}
  levelVars : Array String := #[]
  /-- Head symbols of the data clauses, if data positions are being created (pass 2 of
  `compile`); `none` in pass 1, which only finds the data clauses. -/
  dataKeys : Option (Std.HashSet (String × Nat)) := none
  /-- Head symbols of the data clauses compiled so far. -/
  dataHeads : Array (String × Nat) := #[]
  opts : CompileOptions := {}
  /-- 9a-2 (only with `rewrite`): the atom being compiled, every rigid node of every atom with its
  local context (by atom and template path), the term positions of each symbol, and the root's
  local context and binders. -/
  curLoc : Option Rules.Loc := none
  nodes : Std.HashMap (Rules.Loc × Array Nat) (Expr × LocalContext × LocalInstances) := {}
  /-- The universe parameters' level variables at each recorded atom (a constant of H's). -/
  atomLevels : Std.HashMap Rules.Loc (Std.HashMap Name String) := {}
  sigs : Rules.Sigs := {}
  rootCtx : Option (LocalContext × LocalInstances × Array Expr) := none
  rules : Array RuleInfo := #[]
  ruleStats : RuleStats := {}

abbrev CompileM := StateRefT CState MetaM

def compileError {α} (msg : MessageData) : CompileM α :=
  throwError m!"solve_by_sat: {msg}"

def freshStatic (n : Name) : CompileM String := do
  let k := (← get).counter
  modify fun s => { s with counter := k + 1 }
  return s!"{n.eraseMacroScopes}#{k}"

def kindOf (f : FVarId) : CompileM (Option FVKind) := return (← get).kinds[f]?

def setKind (x : Expr) (k : FVKind) : CompileM Unit :=
  modify fun s => { s with kinds := s.kinds.insert x.fvarId! k }

def compileLevel : Level → CompileM Term
  | .zero => return .const "lvl:zero"
  | .succ l => return .app "lvl:succ" #[← compileLevel l]
  | .max a b => return .app "lvl:max" #[← compileLevel a, ← compileLevel b]
  | .imax a b => return .app "lvl:imax" #[← compileLevel a, ← compileLevel b]
  | .param p => do
    if let some v := (← get).levelMap[p]? then return .var v
    return .const s!"lvl:param:{p}"
  | .mvar _ => compileError "universe metavariable in a statement"

/-- Type templates (used by the static typing filter of 6.8). Binders become `pi`/`lam`
with de Bruijn `bvar:i` leaves, so closed types compare up to binder names. Anything that
cannot be compiled (including a type that mentions a variable bound inside a term) gives
`none`: unknown type, the candidate is kept. -/
partial def compileType (ty : Expr) : CompileM (Option Term) := do
  -- EVAL_PLAN §10.7 decision 2 (testing only): every type a template is built from must be
  -- unchanged by preprocessing, so that it compares syntactically with the preprocessed terms
  if solve_by_sat.checkTemplates.get (← getOptions) then
    let p ← preprocess ty
    let s ← stripMData ty
    if p != s then
      throwError "solve_by_sat: internal: a type template is built from a type that preprocessing \
        changes: {ty} ⇒ {p}"
  try some <$> go ty catch _ => return none
where
  go (e : Expr) : CompileM Term := do
    let e := e.consumeMData
    if !e.hasLooseBVars then
      if ← isProof e then return .const Term.proofSym
    match e with
    | .bvar i => return .const (Term.bvarSym i)
    | .fvar f => match ← kindOf f with
      | some (.eig n) | some (.cvar n) => return .var n
      | _ => throwError "a variable that is not static"
    | .forallE _ d b _ => return .app "pi" #[← go d, ← go b]
    | .lam _ d b _ => return .app "lam" #[← go d, ← go b]
    | _ =>
      match decompose e with
      | .error msg => throwError msg
      | .ok (sym, pieces) =>
        let args ← pieces.mapM fun
          | .level l => compileLevel l
          | .expr x => go x
        return .app sym args

/-- Record the type template of a compiled template node: per position if non-ground,
per term (with a closed representative when there is one) if ground. The inferred type is
preprocessed (SPEC §4.1) before it becomes a template, like every other type: otherwise it
would not compare syntactically with the preprocessed terms (EVAL_PLAN §10.7). -/
def recordNode (t : Term) (e : Expr) (path : Array Nat) : CompileM Unit := do
  if t.isGround then
    unless (← get).groundTypes.contains t do
      let ty ← compileType (← preprocess (← inferType e))
      modify fun s => { s with groundTypes := s.groundTypes.insert t ty, groundOrder := s.groundOrder.push t }
    unless e.hasFVar || (← get).groundExprs.contains t do
      modify fun s => { s with groundExprs := s.groundExprs.insert t e }
  else
    let ty ← compileType (← preprocess (← inferType e))
    modify fun s => { s with posTypes := s.posTypes.push (path, ty) }

/-! ### 9a-2: term positions and occurrences -/

/-- 8a's eligibility (M8_PLAN §2.3, amendment 4.1 decision 3; formerly `M8.eligible` in
`Test/M8Rules.lean`, which now calls this): is position `i` of the telescope `xs` eligible (its binder
is explicit, its value is a term: its type is not a sort other than `Prop`, not a class, not a
proposition; no later binder's type mentions it), and is it a `Prop` position? -/
def rewriteEligible (xs : Array Expr) (i : Nat) : MetaM (Option Bool) := do
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

/-- The term positions of a rigid node `e` with `nPieces` template arguments (M9_PLAN 3.1): the
positions of its symbol's type (read without reduction, as in 8a) that are eligible and that the
result type does not mention. A symbol whose type ends in a sort other than `Prop`, or in a
proposition (a proof), has none, as in 8a. -/
def computeSig (e : Expr) (nPieces : Nat) : MetaM Rules.Sig := do
  let f := e.getAppFn.consumeMData
  let nargs := e.getAppNumArgs
  let offset := nPieces - nargs
  let ty ← match f with
    | .const c _ => pure (← getConstInfo c).type
    | _ => inferType f
  forallTelescope ty fun xs r => do
    let r ← instantiateMVars r
    let kindOk ← if r.isProp then pure true else if r.isSort then pure false else pure !(← isProp r)
    let mut mask := Array.replicate nPieces false
    let mut mm := Array.replicate nPieces false
    if kindOk then
      for i in [0:min xs.size nargs] do
        if (← rewriteEligible xs i).isSome && !r.containsFVar xs[i]!.fvarId! then
          mask := mask.set! (offset + i) true
        else
          mm := mm.set! (offset + i) true
    return { mask, offset, mutantMask := mm }

/-- Record a rigid node of the atom being compiled (only with `rewrite`): its expression and local
context, and its symbol's term positions. -/
def recordOcc (t : Term) (e : Expr) (path : Array Nat) : CompileM Unit := do
  let s ← get
  unless s.opts.rewrite do return
  let some loc := s.curLoc | return
  let some k := Rules.sigKey t | return
  let lctx ← getLCtx
  let linst ← getLocalInstances
  modify fun s => { s with nodes := s.nodes.insert (loc, path) (e, lctx, linst) }
  unless (← get).sigs.contains k do
    let sig ← try computeSig e t.args.size catch _ => pure { mask := Array.replicate t.args.size false, offset := 0 }
    modify fun s => { s with sigs := s.sigs.insert k sig }

/-- Compile an argument term of an atom (SPEC §4.4). Binders inside the term are opened
as local declarations (so types can be inferred) and their variables become `bvar:i`. -/
partial def compileTerm (e : Expr) (path : Array Nat) : CompileM Term := do
  let e := e.consumeMData
  if ← isProof e then return .const Term.proofSym
  if let .fvar f := e then
    match ← kindOf f with
    | some (.eig n) | some (.cvar n) => return .var n
    | some (.bound lvl) => return .const (Term.bvarSym ((← get).depth - lvl - 1))
    | _ => compileError m!"unexpected free variable {e}"
  if let .fvar f := e.getAppFn.consumeMData then
    match ← kindOf f with
    | some (.cvar n) =>
      compileError m!"the clause variable {n} is applied to arguments in {e}: not first order"
    | some (.bound _) =>
      compileError m!"a bound variable is applied to arguments in {e}: not first order"
    | _ => pure ()
  let t ← match e with
    | .lam n d b bi | .forallE n d b bi =>
      let dT ← compileTerm d (path.push 0)
      let bT ← withLocalDecl n bi d fun x => do
        let lvl := (← get).depth
        setKind x (.bound lvl)
        modify fun s => { s with depth := lvl + 1 }
        try compileTerm (b.instantiate1 x) (path.push 1)
        finally modify fun s => { s with depth := lvl }
      pure (Term.app (if e.isLambda then "lam" else "pi") #[dT, bT])
    | _ =>
      match decompose e with
      | .error msg => compileError m!"unsupported term {e}: {msg}"
      | .ok (sym, pieces) =>
        let mut args := #[]
        for h : i in [0:pieces.size] do
          args := args.push (← match pieces[i] with
            | .level l => compileLevel l
            | .expr x => compileTerm x (path.push i))
        pure (Term.app sym args)
  recordNode t e path
  recordOcc t e path
  return t

/-- Compile a proposition as an opaque atom (SPEC §2.1, and amendment 1 of milestone 3:
every target and head, connective or not, is an atom with a constant or eigenvariable
head). Returns the template and the type templates of its rigid positions. -/
def compileAtom (R : Expr) (what : String) (loc : Option Rules.Loc := none) :
    CompileM (Term × Array (Array Nat × Option Term)) := do
  let R := R.consumeMData
  let savedLoc := (← get).curLoc
  modify fun s => { s with curLoc := loc }
  try compileAtomCore R what
  finally modify fun s => { s with curLoc := savedLoc }
where
  compileAtomCore (R : Expr) (what : String) : CompileM (Term × Array (Array Nat × Option Term)) := do
    match R.getAppFn.consumeMData with
    | .const .. => pure ()
    | .fvar f =>
      match ← kindOf f with
      | some (.eig _) => pure ()
      | some (.cvar n) => compileError m!"the {what} {R} has the clause variable {n} as its head symbol"
      | _ => compileError m!"the {what} {R} is not an atom"
    | _ => compileError m!"the {what} {R} is not an atom (its head is not a constant or an eigenvariable)"
    modify fun s => { s with posTypes := #[] }
    match decompose R (atom := true) with
    | .error msg => compileError m!"the {what} {R} is not supported: {msg}"
    | .ok (sym, pieces) =>
      let mut args := #[]
      for h : i in [0:pieces.size] do
        args := args.push (← match pieces[i] with
          | .level l => compileLevel l
          | .expr x => compileTerm x #[i])
      let a := Term.app sym args
      recordOcc a R #[]
      if (← get).opts.rewrite then
        if let some loc := (← get).curLoc then
          modify fun s => { s with atomLevels := s.atomLevels.insert loc s.levelMap }
      return (a, (← get).posTypes)

/-- Open the leading `∀` binders of `e` as local declarations and run `k` on them
(name, type, free variable) and the body. Only syntactic binders: no `whnf`. -/
partial def telescope {α} (e : Expr) (k : Array (Name × Expr × Expr) → Expr → CompileM α) : CompileM α :=
  go e #[]
where
  go (e : Expr) (acc : Array (Name × Expr × Expr)) : CompileM α := do
    match e.consumeMData with
    | .forallE n d b bi =>
      withLocalDecl n bi d fun x => go (b.instantiate1 x) (acc.push (n, d, x))
    | body => k acc body

def checkBinderType (n : Name) (d : Expr) : CompileM Unit := do
  let kinds := (← get).kinds
  if d.hasAnyFVar (fun f => kinds[f]? matches some .proof) then
    compileError m!"the type of binder {n} mentions a proof variable: {d}"
  if d.hasMVar then compileError m!"the type of binder {n} contains a metavariable: {d}"

/-- `A ∧ B` → `(A, B)`, likewise for `↔`. -/
def binApp? (c : Name) (e : Expr) : Option (Expr × Expr) :=
  let e := e.consumeMData
  if e.isAppOfArity c 2 then some (e.appFn!.appArg!, e.appArg!) else none

/-- The split paths of a clause formula (SPEC §4.2 and amendment 1): the opaque head `[]`,
and recursively the components of an `∧` head (`left`, `right`) and of an `↔` head (`mp`:
head `B` with premise `A`; `mpr`: head `A` with premise `B`). With `iffEq` (M9_PLAN 2.1), an
`↔` head `A ↔ B` also gives `[propEq]` (head `A = B`) and `[propEqSymm]` (head `B = A`),
after its other paths, so that with the option off the paths are exactly as before. -/
partial def splitPaths (e : Expr) : CompileM (List (List Split)) :=
  telescope e fun _ body => do
    if let some (a, b) := binApp? ``And body then
      return [[]] ++ (← splitPaths a).map (.left :: ·) ++ (← splitPaths b).map (.right :: ·)
    if let some (a, b) := binApp? ``Iff body then
      let eqs := if (← get).opts.iffEq then [[Split.propEq], [Split.propEqSymm]] else []
      return [[]] ++ (← splitPaths b).map (.mp :: ·) ++ (← splitPaths a).map (.mpr :: ·) ++ eqs
    return [[]]

/-- Does a split path end in an `iffEq` head? -/
def isIffEqPath (path : List Split) : Bool :=
  path.getLast? matches some .propEq | some .propEqSymm

/-- The equation `@Eq Prop a b` between two propositions. -/
def mkPropEq (a b : Expr) : Expr :=
  mkApp3 (mkConst ``Eq [Level.one]) (mkSort Level.zero) a b

/-- Run `k` for an `iffEq` path (M9_PLAN 2.1): if it cannot be compiled (for instance a side
whose template cannot be built), the path is dropped and reported in a note, as root split
paths are; the clause's other paths are unaffected. -/
def dropIffEqPath (shown : String) (k : CompileM Nat) : CompileM (Option Nat) := do
  let saved ← get
  try some <$> k
  catch ex =>
    let note := m!"solve_by_sat: the ↔-as-equation path {shown} is dropped:\n{ex.toMessageData}"
    set { saved with notes := saved.notes.push note }
    return none

/-- Classify binders: non-Prop binders become static variables of the given kind, Prop
binders are returned as hypotheses/premises. -/
def classifyBinders (bs : Array (Name × Expr × Expr)) (clauseVars : Bool) :
    CompileM (Array (String × Expr × Nat) × Array (Nat × Name × Expr) × Array BinderUse) := do
  let mut statics := #[]
  let mut props := #[]
  let mut uses := #[]
  for h : i in [0:bs.size] do
    let (n, d, x) := bs[i]
    checkBinderType n d
    if ← isProp d then
      setKind x .proof
      props := props.push (i, n, d)
      uses := uses.push BinderUse.hyp
    else
      let nm ← freshStatic n
      setKind x (if clauseVars then .cvar nm else .eig nm)
      let ty ← compileType d
      modify fun s => { s with varTypes := s.varTypes.push (nm, ty) }
      statics := statics.push (nm, d, i)
      uses := uses.push (.static nm)
  return (statics, props, uses)

/-- The result type of a type `∀ xs, R` (after the binders), in the current context. -/
partial def resultType {α} (d : Expr) (k : Expr → CompileM α) : CompileM α :=
  telescope d fun _ body => k body

/-- Is a variable of type `d` eligible for a data position (milestone 5, requirement 1):
its type is not a proposition, not a function type and not a Sort? -/
def dataEligible (d : Expr) : CompileM Bool := do
  let d := d.consumeMData
  if d.isForall || d.isSort then return false
  return !(← isProp d)

mutual
/-- Data positions (SPEC §6.9) for the variables `vars` (name, type) of a clause whose
premises have `Env = scope`: only in pass 2 of `compile`, only for eligible types, and
only when the type's head symbol is the head symbol of some data clause (a data position
that no data clause can match would only add clauses). -/
partial def dataPositions (vars : Array (String × Expr)) (scope : Array String) :
    CompileM (Array (String × Nat)) := do
  let some keys := (← get).dataKeys | return #[]
  let mut out := #[]
  for (b, d) in vars do
    unless ← dataEligible d do continue
    let saved ← get
    let compiled ← try some <$> compileAtom d s!"type of {b}" catch _ => pure none
    let some (tgt, tys) := compiled | set saved; continue
    unless (tgt.symKey.map keys.contains).getD false do set saved; continue
    let gid := (← get).goals.size
    modify fun s => { s with
      goals := s.goals.push { tgt, eig := #[], hyps := #[], env := Forest.sortStrs scope, tgtTypes := tys,
                              dataVar := some b },
      goalInfo := s.goalInfo.push {} }
    out := out.push (b, gid)
  return out

/-- Compile a data clause (SPEC §6.9): a constant of `H`, or an eigenvariable of function
type, whose result type is neither a proposition nor a Sort. Its non-Prop binders are
clause variables (with data positions of their own), its Prop binders are premises, its
head is the result type, and its value is `headExpr` applied to all its binders. -/
partial def compileDataClause (e : Expr) (env : Array String) (localOf : Option Nat)
    (origin : ClauseOrigin) (name : String) (levelParams : List Name) (headExpr : Expr) :
    CompileM Nat := do
  let cid := (← get).clauses.size
  modify fun s => { s with
    clauses := s.clauses.push { name, head := default, vars := #[], prems := #[], env := Forest.sortStrs env, localOf },
    clauseInfo := s.clauseInfo.push {} }
  let savedLevels := (← get).levelMap
  let mut lvars := #[]
  for p in levelParams do
    let v ← freshStatic p
    lvars := lvars.push v
    modify fun s => { s with levelMap := s.levelMap.insert p v, levelVars := s.levelVars.push v }
  let lvarsFinal := lvars
  try
    telescope e fun bs body => do
      let (vs, ps, uses) ← classifyBinders bs true
      let mut uses := uses
      let mut prems := #[]
      for (i, _, d) in ps do
        uses := uses.set! i (.prem prems.size)
        prems := prems.push d
      let (head, tys) ← compileAtom body s!"result type of {name}"
      -- the value template and the types of its positions
      modify fun s => { s with posTypes := #[] }
      let value ← compileTerm (mkAppN headExpr (bs.map (·.2.2))) #[]
      let rootTy ← compileType body
      let valueTypes := #[(#[], rootTy)] ++ ((← get).posTypes.filter (·.1 != #[]))
      let vars := lvarsFinal ++ vs.map (·.1)
      let scope := env ++ vars
      let mut premIds := #[]
      for d in prems do premIds := premIds.push (← compileGoal d scope)
      let dps ← dataPositions (vs.map fun (b, d, _) => (b, d)) scope
      modify fun s => { s with
        clauses := s.clauses.set! cid { name, head, vars, prems := premIds, env := Forest.sortStrs env,
                                         localOf, headTypes := tys, dataPos := dps, dataVal := some value,
                                         valueTypes },
        clauseInfo := s.clauseInfo.set! cid { origin, steps := #[.binders uses], levelVars := lvarsFinal, isData := true },
        dataHeads := match head.symKey with | some k => s.dataHeads.push k | none => s.dataHeads }
  finally modify fun s => { s with levelMap := savedLevels }
  return cid

/-- Compile a goal formula (SPEC §2.1) into a goal position with `Env = env`, its local
hypotheses, and the built-in clauses of a connective target. -/
partial def compileGoal (e : Expr) (env : Array String) (isRoot : Bool := false) : CompileM Nat := do
  let gid := (← get).goals.size
  modify fun s => { s with goals := s.goals.push { tgt := default, eig := #[], hyps := #[], env := Forest.sortStrs env },
                           goalInfo := s.goalInfo.push {} }
  telescope e fun bs body => do
    let (eigTys, hypBinders, uses) ← classifyBinders bs false
    let eigs := eigTys.map (·.1)
    let scope := env ++ eigs
    let mut hyps := #[]
    -- an eigenvariable of function type with a data result is a data clause local to this
    -- goal position (milestone 5, requirement 2); a plain eigenvariable is not: it is
    -- already a grounding candidate (NOTES.md, milestone 5)
    for (_, d, i) in eigTys do
      if d.consumeMData.isForall then
        let isData ← resultType d fun r => do
          let r := r.consumeMData
          return !r.isSort && !(← isProp r)
        if isData then
          let (n, _, x) := bs[i]!
          discard <| compileDataClause d scope (some gid) (.localHyp gid i)
            s!"{n.eraseMacroScopes}" [] x
    for (i, n, d) in hypBinders do
      let hname := if n.hasMacroScopes then s!"{n.eraseMacroScopes}{i}@g{gid}" else s!"{n}"
      hyps := hyps ++ (← compileHyp d scope gid i hname isRoot)
    if isRoot then
      let lctx ← getLCtx
      let linst ← getLocalInstances
      modify fun s => { s with rootCtx := some (lctx, linst, bs.map (·.2.2)) }
    let (tgt, tys) ← compileAtom body "target" (some (.goal gid))
    modify fun s => { s with
      goals := s.goals.set! gid { tgt, eig := eigs, hyps, env := Forest.sortStrs env, tgtTypes := tys },
      goalInfo := s.goalInfo.set! gid { binders := uses } }
    compileBuiltins gid body tgt tys scope
    return gid

/-- One clause per split path of a local hypothesis. For a binder of the root goal, a path
that cannot be compiled gives no clause (amendment 2 of milestone 3) and a note. -/
partial def compileHyp (d : Expr) (scope : Array String) (gid i : Nat) (hname : String)
    (isRoot : Bool) : CompileM (Array Nat) := do
  let paths ← if isRoot then (try splitPaths d catch _ => pure [[]]) else splitPaths d
  let mut ids := #[]
  for path in paths do
    if isRoot then
      let saved ← get
      try
        ids := ids.push (← compileClauseAlong d scope (some gid) (.localHyp gid i) hname path)
      catch ex =>
        let shown := if path.isEmpty then hname else hname ++ "." ++ ".".intercalate (path.map Split.suffix)
        let note := m!"solve_by_sat: hypothesis {shown} is introduced but gives no clause:\n{ex.toMessageData}"
        set { saved with notes := saved.notes.push note }
    else if isIffEqPath path then
      let shown := hname ++ "." ++ ".".intercalate (path.map Split.suffix)
      if let some id ← dropIffEqPath shown (compileClauseAlong d scope (some gid) (.localHyp gid i) hname path) then
        ids := ids.push id
    else
      ids := ids.push (← compileClauseAlong d scope (some gid) (.localHyp gid i) hname path)
  return ids

/-- Compile the clause of a clause formula (SPEC §2.1) along one split path, with
`Env = env`. Every clause gets fresh binders, so split clauses share no static names. -/
partial def compileClauseAlong (e : Expr) (env : Array String) (localOf : Option Nat)
    (origin : ClauseOrigin) (base : String) (path : List Split) (levelParams : List Name := []) :
    CompileM Nat := do
  let name := if path.isEmpty then base else base ++ "." ++ ".".intercalate (path.map Split.suffix)
  let cid := (← get).clauses.size
  modify fun s => { s with
    clauses := s.clauses.push { name, head := default, vars := #[], prems := #[], env := Forest.sortStrs env, localOf },
    clauseInfo := s.clauseInfo.push {} }
  -- universe parameters of a constant are level variables of this clause (SPEC §4.3)
  let savedLevels := (← get).levelMap
  let mut lvars := #[]
  for p in levelParams do
    let v ← freshStatic p
    lvars := lvars.push v
    modify fun s => { s with levelMap := s.levelMap.insert p v, levelVars := s.levelVars.push v }
  let rec go (T : Expr) (path : List Split) (vars : Array String) (prems : Array Expr)
      (steps : Array Step) (varTys : Array (String × Expr)) : CompileM Unit :=
    telescope T fun bs body => do
      let (vts, ps, uses) ← classifyBinders bs true
      let vs := vts.map (·.1)
      let varTys := varTys ++ vts.map fun (b, d, _) => (b, d)
      let mut uses := uses
      let mut prems := prems
      for (i, _, d) in ps do
        uses := uses.set! i (.prem prems.size)
        prems := prems.push d
      let vars := vars ++ vs
      let steps := steps.push (.binders uses)
      match path with
      | [] =>
        -- the head first, so a bare-variable head (e.g. `Or.elim`) is reported as such
        let (head, tys) ← compileAtom body s!"head of {name}" (some (.clause cid))
        let scope := env ++ vars
        let mut premIds := #[]
        for d in prems do premIds := premIds.push (← compileGoal d scope)
        let dps ← dataPositions varTys scope
        modify fun s => { s with
          clauses := s.clauses.set! cid { name, head, vars, prems := premIds, env := Forest.sortStrs env,
                                           localOf, headTypes := tys, dataPos := dps },
          clauseInfo := s.clauseInfo.set! cid { origin, steps, levelVars := lvars } }
      | sp :: rest =>
        let some (a, b) := binApp? (if sp matches .left | .right then ``And else ``Iff) body
          | compileError m!"internal: split path {repr path} does not match the head {body}"
        -- the mutation check of M9_PLAN 2.2 swaps the two `iffEq` recipes (not the heads)
        let swap := (← get).opts.iffEqMutant
        match sp with
        | .left => go a rest vars prems (steps.push .andLeft) varTys
        | .right => go b rest vars prems (steps.push .andRight) varTys
        | .mp => go b rest vars (prems.push a) (steps.push (.iffMp prems.size)) varTys
        | .mpr => go a rest vars (prems.push b) (steps.push (.iffMpr prems.size)) varTys
        | .propEq => go (mkPropEq a b) rest vars prems (steps.push (if swap then .propEqSymm else .propEq)) varTys
        | .propEqSymm => go (mkPropEq b a) rest vars prems (steps.push (if swap then .propEq else .propEqSymm)) varTys
  try go e path lvars #[] #[] #[]
  finally modify fun s => { s with levelMap := savedLevels }
  return cid

/-- Built-in clauses of a connective target (SPEC §4.2 table). Their head is the target. -/
partial def compileBuiltins (gid : Nat) (R : Expr) (tgt : Term) (tys : Array (Array Nat × Option Term))
    (scope : Array String) : CompileM Unit := do
  let mk (name : String) (k : Builtin) (vars : Array String) (prems : Array Expr)
      (varTys : Array (String × Expr) := #[]) : CompileM Unit := do
    let cid := (← get).clauses.size
    modify fun s => { s with
      clauses := s.clauses.push { name, head := tgt, vars, prems := #[], env := Forest.sortStrs scope,
                                  localOf := some gid, headTypes := tys, builtin := true },
      clauseInfo := s.clauseInfo.push {} }
    let mut premIds := #[]
    for d in prems do premIds := premIds.push (← compileGoal d (scope ++ vars))
    let uses := vars.map BinderUse.static ++ (Array.range prems.size).map BinderUse.prem
    let dps ← dataPositions varTys (scope ++ vars)
    modify fun s => { s with
      clauses := s.clauses.modify cid fun c => { c with prems := premIds, dataPos := dps },
      clauseInfo := s.clauseInfo.set! cid { origin := .builtin k, steps := #[.binders uses] } }
  let R := R.consumeMData
  if let some (a, b) := binApp? ``And R then
    mk "And.intro" .andIntro #[] #[a, b]
  else if let some (a, b) := binApp? ``Or R then
    mk "Or.inl" .orInl #[] #[a]
    mk "Or.inr" .orInr #[] #[b]
  else if let some (a, b) := binApp? ``Iff R then
    mk "Iff.intro" .iffIntro #[] #[← mkArrow a b, ← mkArrow b a]
  else if R.isConstOf ``True then
    mk "True.intro" .trueIntro #[] #[]
  else if R.isAppOfArity ``Exists 2 then
    let α := R.appFn!.appArg!
    let p := R.appArg!.consumeMData
    if ← isProp α then
      compileError m!"the target {R} quantifies over a proposition (∃ h : P, …), which is outside the proof class"
    let n := if let .lam n .. := p then n else `w
    withLocalDecl n .default α fun w => do
      let nm ← freshStatic n
      setKind w (.cvar nm)
      let ty ← compileType α
      modify fun s => { s with varTypes := s.varTypes.push (nm, ty) }
      -- `∃ x, A` with a literal `fun`; otherwise η-expanded: `A := p w`
      let body := if let .lam _ _ b _ := p then b.instantiate1 w else mkApp p w
      mk "Exists.intro" .existsIntro #[nm] #[body] #[(nm, α)]
end

/-! ## 9a-2: equality rules made per use (M9_PLAN 3.1, amendment 6.1)

`addRules` runs after the forest is compiled. `Rules.select` (pure, `SolveBySat/Forest.lean`) picks
the occurrences; for each, the statement and proof are built here from the recorded expression, in
its local context, and checked (the static motive check); the statement is compiled as a clause (a
global clause, or one local to the root), and that clause must equal `Rules.mkRule`'s up to the
names of its variables, or the compiler stops with an internal error. Then the equality core is
selected on the forest with the rules (`Rules.selectCore`) and built the same way. No declaration
is added: the decoder applies the stored proof. -/

/-- The free variables of `es` and, recursively, of their types, in local-context order. -/
def ctxClosure (es : Array Expr) : MetaM (Array Expr) := do
  let mut seen : Std.HashSet FVarId := {}
  let mut todo : Array FVarId := es.foldl (fun acc e => acc ++ (collectFVars {} e).fvarIds) #[]
  while !todo.isEmpty do
    let f := todo.back!
    todo := todo.pop
    if seen.contains f then continue
    seen := seen.insert f
    let ty ← instantiateMVars (← f.getType)
    todo := todo ++ (collectFVars {} ty).fvarIds
  let lctx ← getLCtx
  return (lctx.sortFVarsByContextOrder seen.toArray).map mkFVar

/-- Open local declarations `x_i : tys[i]` (default binders) and run `k` on them. -/
partial def withLocals {α} (base : String) (tys : Array Expr) (k : Array Expr → CompileM α) : CompileM α :=
  go 0 #[]
where
  go (i : Nat) (acc : Array Expr) : CompileM α := do
    if h : i < tys.size then
      withLocalDeclD (.mkSimple s!"{base}{i}") tys[i] fun x => go (i + 1) (acc.push x)
    else k acc

/-- The type of argument `j` of `f` applied to `args`, as `f`'s binder type there (preprocessed). -/
def argBinderType (f : Expr) (args : Array Expr) (j : Nat) : MetaM Expr := do
  let t ← instantiateForall (← inferType f) (args.extract 0 j)
  match ← whnf t with
  | .forallE _ d _ _ => preprocess d
  | _ => throwError "argument {j} of {f} has no binder"

/-- What a substitution or congruence rule is, before it is compiled: its statement, its proof,
the context's free variables it is abstracted over (`hvars`), and the types for `Rules.mkRule`. -/
structure BuiltRule where
  stmt : Expr
  proof : Expr
  types : Rules.RuleTypes := { posLvl := default, posTy := default }

/-- Build (in the occurrence's local context) the statement and proof of a substitution or
congruence rule, and run the static motive check: the motive `fun y => f(…y…)`, with the other term
positions as placeholders, and the proof are type-checked, and the proof's type must be the
statement. Throws (the rule is dropped) on any failure. -/
def buildSubstCongr (key : Rules.Key) (occ : Rules.Occ) : CompileM BuiltRule := do
  let s ← get
  let some (e, lctx, linst) := s.nodes[(occ.loc, occ.path)]? | throwError "internal: no recorded occurrence"
  let atomT := Rules.atomAt { goals := s.goals, clauses := s.clauses } occ.loc
  let some node := Rules.subtermAt atomT occ.path | throwError "internal: no node at the occurrence"
  let some sig := (Rules.sigKey node) >>= (s.sigs[·]?) | throwError "internal: no signature"
  withLCtx lctx linst do
    let e := e.consumeMData
    let f := e.getAppFn.consumeMData
    let args := e.getAppArgs
    let off := sig.offset
    let k := key.pos - off
    let J := (Array.range args.size).filter fun j => j != k && sig.mask[off + j]!
    let τ ← argBinderType f args k
    let u := (← getLevel τ).normalize
    let tJ ← J.mapM fun j => (argBinderType f args j : MetaM Expr)
    let ρ ← preprocess (← inferType e)
    let uρ := (← getLevel ρ).normalize
    -- the context: the head (an `app` node), the arguments at the other positions, and the types
    let ctxArgs := (Array.range args.size).filter (fun j => j != k && !sig.mask[off + j]!) |>.map (args[·]!)
    let ctx ← ctxClosure (#[f, τ, ρ] ++ ctxArgs ++ tJ)
    for x in ctx do
      if ← isProp (← inferType x) then throwError "the context mentions the hypothesis {x}"
    let some (_, _, rootFVs) := s.rootCtx | throwError "internal: no root context"
    match key.row with
    | .ground => unless ctx.isEmpty do throwError "internal: a ground context with free variables {ctx}"
    | .root => unless ctx.all rootFVs.contains do throwError "internal: a root context with other variables {ctx}"
    | .hvars => pure ()
    let abs := if key.row == .hvars then ctx else #[]
    withLocalDeclD `a τ fun a => withLocalDeclD `b τ fun b => withLocals "x" tJ fun xs => do
      let nodeWith (y : Expr) : Expr := Id.run do
        let mut as := args.set! k y
        for h : i in [0:J.size] do as := as.set! J[i] xs[i]!
        return mkAppN f as
      let hTy := mkApp3 (mkConst ``Eq [u]) τ a b
      -- the static motive check
      let motive ← withLocalDeclD `y τ fun y => mkLambdaFVars #[y] (nodeWith y)
      Meta.check motive
      withLocalDeclD `h hTy fun h => do
        let (stmt, proof) ← if key.kind == .congr then do
            let body := mkApp3 (mkConst ``Eq [uρ]) ρ (nodeWith a) (nodeWith b)
            let pf := mkApp6 (mkConst ``congrArg [u, uρ]) τ ρ a b motive h
            pure (← mkForallFVars (abs ++ #[a, b] ++ xs ++ #[h]) body, ← mkLambdaFVars (abs ++ #[a, b] ++ xs ++ #[h]) pf)
          else
            withLocalDeclD `hp (nodeWith b) fun hp => do
              let cg := mkApp6 (mkConst ``congrArg [u, Level.one]) τ (mkSort Level.zero) a b motive h
              let pf := mkApp4 (mkConst ``Eq.mpr [Level.zero]) (nodeWith a) (nodeWith b) cg hp
              pure (← mkForallFVars (abs ++ #[a, b] ++ xs ++ #[h, hp]) (nodeWith a),
                    ← mkLambdaFVars (abs ++ #[a, b] ++ xs ++ #[h, hp]) pf)
        let stmt ← preprocess stmt
        Meta.check proof
        unless ← isDefEq (← inferType proof) stmt do
          throwError "the proof's type {← inferType proof} is not the statement {stmt}"
        -- the types for `Rules.mkRule`, compiled in the occurrence's context, with its universe
        -- parameters' level variables (state restored)
        let saved ← get
        let types ← try
            modify fun st => { st with levelMap := (saved.atomLevels.get? occ.loc).getD {} }
            pure { posLvl := ← compileLevel u, posTy := ← compileTerm τ #[],
                   resLvl := ← compileLevel uρ, resTy := ← compileTerm ρ #[] : Rules.RuleTypes }
          finally set saved
        return { stmt, proof, types }

/-- Build a core rule (`refl`, `symm`, `trans`) at the type of the `Eq` atom at `occ.loc`. -/
def buildCore (key : Rules.Key) (occ : Rules.Occ) : CompileM BuiltRule := do
  let s ← get
  let some ((e : Expr), lctx, linst) := s.nodes[(occ.loc, (#[] : Array Nat))]? | throwError "internal: no recorded Eq atom"
  withLCtx lctx linst do
    let e := e.consumeMData
    let Expr.const _ [u] := e.getAppFn | throwError "internal: not an Eq atom: {e}"
    let τ := e.getAppArgs[0]!
    let ctx ← ctxClosure #[τ]
    for x in ctx do
      if ← isProp (← inferType x) then throwError "the type mentions the hypothesis {x}"
    let abs := if key.row == .hvars then ctx else #[]
    let eq := fun (a b : Expr) => mkApp3 (mkConst ``Eq [u]) τ a b
    withLocalDeclD `x τ fun x => withLocalDeclD `y τ fun y => withLocalDeclD `z τ fun z => do
      let (stmt, proof) ← match key.kind with
        | .refl => pure (← mkForallFVars (abs ++ #[x]) (eq x x),
                         ← mkLambdaFVars (abs ++ #[x]) (mkApp2 (mkConst ``Eq.refl [u]) τ x))
        | .symm => withLocalDeclD `h (eq x y) fun h => do
            pure (← mkForallFVars (abs ++ #[x, y, h]) (eq y x),
                  ← mkLambdaFVars (abs ++ #[x, y, h]) (mkApp4 (mkConst ``Eq.symm [u]) τ x y h))
        | _ => withLocalDeclD `h₁ (eq x y) fun h₁ => withLocalDeclD `h₂ (eq y z) fun h₂ => do
            pure (← mkForallFVars (abs ++ #[x, y, z, h₁, h₂]) (eq x z),
                  ← mkLambdaFVars (abs ++ #[x, y, z, h₁, h₂]) (mkApp6 (mkConst ``Eq.trans [u]) τ x y z h₁ h₂))
      let stmt ← preprocess stmt
      Meta.check proof
      unless ← isDefEq (← inferType proof) stmt do
        throwError "the proof's type {← inferType proof} is not the statement {stmt}"
      return { stmt, proof }

/-- Compile a built rule's statement as a clause (global, or local to the root), check its shape
against the pure construction `pureC`, and record it. On a compile failure the rule is dropped with
a note (state restored); a shape mismatch is an internal error. -/
def installRule (key : Rules.Key) (name : String) (b : BuiltRule) (pureC : ClauseT × Option Nat)
    (pos8a : Nat) : CompileM Unit := do
  let s ← get
  let some (rlctx, rlinst, rootFVs) := s.rootCtx | throwError "internal: no root context"
  let k := s.rules.size
  let lps := if key.row == .hvars then (collectLevelParams {} b.stmt).params.toList else []
  let root := key.row == .root
  let saved ← get
  let cid? ← try
      some <$> (if root then
        withLCtx rlctx rlinst (compileClauseAlong b.stmt (s.goals[0]!.env ++ s.goals[0]!.eig) (some 0) (.rule k) name [] lps)
      else compileClauseAlong b.stmt #[] none (.rule k) name [] lps)
    catch ex =>
      let msg ← ex.toMessageData.toString
      set { saved with notes := saved.notes.push m!"solve_by_sat: rewrite: the rule {name} is dropped: {msg}",
                       ruleStats := { saved.ruleStats with dropped := saved.ruleStats.dropped.push (name, msg) } }
      pure none
  let some cid := cid? | return
  let st ← get
  let cl := st.clauses[cid]!
  let .mk _ ph _ pps := pureC.1
  let mine := #[cl.head] ++ cl.prems.map (st.goals[·]!.tgt)
  let theirs := #[ph] ++ (pps.map fun | .mk t _ _ => t).toArray
  unless Rules.alphaEq mine theirs && cl.localOf == pureC.2 do
    throwError "solve_by_sat: internal: the compiled rule {name} is {mine.toList} (local to {cl.localOf}), \
      not the clause {theirs.toList} (local to {pureC.2}) of the selection (M9_PLAN 3.1)"
  let (stmt, proof) ← if root then
      withLCtx rlctx rlinst do pure (← mkForallFVars rootFVs b.stmt, ← mkLambdaFVars rootFVs b.proof)
    else pure (b.stmt, b.proof)
  modify fun s => { s with rules := s.rules.push { key, name, clause := cid, stmt, proof, levelParams := lps,
                                                    rootLocal := root, pos8a } }

/-- Add the equality rules (M9_PLAN 3.1) to the compiled forest. `H` decides which core kinds are
left out (a polymorphic `Eq.refl`, `Eq.symm` or `Eq.trans` that H already has). -/
def addRules (H : Array Name) : CompileM Unit := do
  let s ← get
  let opts := s.opts
  let F0 : Forest := { goals := s.goals, clauses := s.clauses }
  let syms := opts.rewriteSymbols.map (·.map fun n => s!"c:{n}")
  let sel := Rules.select F0 s.sigs syms (liberal := opts.rewriteLiberal) (mutant := opts.rewriteIneligibleMutant)
  let st0 : RuleStats := { sources := sel.sources.size, symbols := sel.symbols, liberalExtra := sel.liberalExtra,
                           broken := sel.broken, noRow := sel.noRow, sigs := s.sigs,
                           liberal := sel.liberal.map (·.1) }
  modify fun s => { s with ruleStats := st0 }
  let mut idx := 0
  let mut congrIds : Array Nat := #[]
  for (key, occ) in sel.rules do
    let name := Rules.ruleName s.sigs key idx
    idx := idx + 1
    let saved ← get
    let built ← try some <$> buildSubstCongr key occ
      catch ex =>
        let msg ← ex.toMessageData.toString
        set { saved with notes := saved.notes.push m!"solve_by_sat: rewrite: the rule {name} is dropped by the static motive check: {msg}",
                         ruleStats := { saved.ruleStats with dropped := saved.ruleStats.dropped.push (name, msg) } }
        pure none
    let some b := built | continue
    -- the context mutation (testing only): the proof of a rule of the same kind, symbol and position
    -- in another context
    let b ← if !opts.rewriteContextMutant then pure b else do
      let other := sel.liberal.find? fun (k', _) => k'.kind == key.kind && k'.symbol == key.symbol &&
        k'.pos == key.pos && k' != key
      match other with
      | none => pure b
      | some (k', o') =>
        let saved ← get
        let b' ← try some <$> buildSubstCongr k' o' catch _ => set saved; pure none
        pure (match b' with | some b' => { b with proof := b'.proof } | none => b)
    let pureC := Rules.mkRule F0 s.sigs key occ b.types name s!"{name}."
    let before := (← get).clauses.size
    installRule key name b pureC (key.pos8a s.sigs)
    if key.kind == .congr && (← get).clauses.size > before then congrIds := congrIds.push before
  -- the equality core, on the forest with the rules
  let s ← get
  let F1 : Forest := { goals := s.goals, clauses := s.clauses }
  let skip := #[(``Eq.refl, Rules.Kind.refl), (``Eq.symm, .symm), (``Eq.trans, .trans)].filterMap fun (n, k) =>
    if H.contains n then some k else none
  for (key, occ) in Rules.selectCore F1 sel.sources congrIds skip opts.eqTrans do
    let name := Rules.ruleName s.sigs key idx
    idx := idx + 1
    let saved ← get
    let built ← try some <$> buildCore key occ
      catch ex =>
        let msg ← ex.toMessageData.toString
        set { saved with notes := saved.notes.push m!"solve_by_sat: rewrite: the rule {name} is dropped by the static check: {msg}",
                         ruleStats := { saved.ruleStats with dropped := saved.ruleStats.dropped.push (name, msg) } }
        pure none
    let some b := built | continue
    installRule key name b (Rules.mkCore key name s!"{name}.") 0

/-- Compile a closed goal and the constants `H` into a clause forest (SPEC §4). -/
def compile (goal : Expr) (H : Array Name) (opts : CompileOptions := {}) : MetaM Compiled := do
  if goal.hasFVar then throwError "solve_by_sat: internal: the goal is not closed after revert"
  let goalType ← preprocess goal
  let go : CompileM Unit := do
    discard <| compileGoal goalType #[] (isRoot := true)
    for c in H do
      let info ← getConstInfo c
      let ty ← preprocess info.type
      if ← isProp ty then
        for path in ← splitPaths ty do
          if isIffEqPath path then
            let shown := s!"{c}." ++ ".".intercalate (path.map Split.suffix)
            discard <| dropIffEqPath shown (compileClauseAlong ty #[] none (.global c) s!"{c}" path info.levelParams)
          else
            discard <| compileClauseAlong ty #[] none (.global c) s!"{c}" path info.levelParams
      else
        -- a data constant (SPEC §6.9): its result type must not be a Sort
        let isSortResult ← resultType ty fun r => pure r.consumeMData.isSort
        if isSortResult then
          compileError m!"{c} is a type former (its result type is a Sort), neither a proof nor a data constant"
        discard <| compileDataClause ty #[] none (.global c) s!"{c}" info.levelParams
          (mkConst c (info.levelParams.map Level.param))
  -- pass 1 finds the data clauses; only if there are some, pass 2 adds data positions
  -- (milestone 5, requirement 1: with no data clause every CNF is unchanged)
  let ((), s1) ← go.run { opts }
  let s ← if s1.dataHeads.isEmpty then pure s1 else
    let keys := s1.dataHeads.foldl (fun h k => h.insert k) ({} : Std.HashSet (String × Nat))
    pure (← go.run { dataKeys := some keys, opts }).2
  -- 9a-2: the equality rules, after everything else (with `rewrite` off, nothing changes)
  let s ← if !opts.rewrite then pure s else pure (← (addRules H).run s).2
  let forest : Forest := { goals := s.goals, clauses := s.clauses, varTypes := s.varTypes,
                           groundTypes := s.groundOrder.map (fun t => (t, s.groundTypes[t]!)),
                           levelVars := s.levelVars }
  match forest.check with
  | .error e => throwError "solve_by_sat: internal: ill-formed forest: {e}"
  | .ok () => pure ()
  return { forest, goalInfo := s.goalInfo, clauseInfo := s.clauseInfo, groundExprs := s.groundExprs,
           goalType, notes := s.notes, opts, rules := s.rules, ruleStats := s.ruleStats }

end SolveBySat
