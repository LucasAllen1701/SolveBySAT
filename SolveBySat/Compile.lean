/-
SolveBySat.Compile: from a closed Lean goal and a list of constants to a clause forest
(SPEC §4), with the rejection messages of §4.5.

Milestones 2 and 3: `∀`, `→`, atoms, connectives in targets (built-in clauses) and heads
(splitting), and binders inside terms (`lam`/`pi`, needed for the opaque atom of `∃`).
Milestone 4: universe parameters of constants in `H` are level variables. Data constants
are milestone 5; until then they are rejected with a message naming the milestone.
-/
import Lean
import SolveBySat.Forest

namespace SolveBySat

open Lean Meta

/-! ## Preprocessing (SPEC §4.1) -/

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

/-- Head splitting (SPEC §4.2): which component of an `∧` / `↔` head a clause uses. -/
inductive Split where
  | left | right | mp | mpr
  deriving Inhabited, Repr, BEq

def Split.suffix : Split → String
  | .left => "left" | .right => "right" | .mp => "mp" | .mpr => "mpr"

/-- How the decoder builds the proof of a clause's head from the proof of its statement. -/
inductive Step where
  /-- Open the next binders as metavariables. -/
  | binders (uses : Array BinderUse)
  | andLeft
  | andRight
  /-- `Iff.mp`; the extra premise has index `k`. -/
  | iffMp (k : Nat)
  | iffMpr (k : Nat)
  deriving Inhabited, Repr

inductive Builtin where
  | andIntro | orInl | orInr | existsIntro | iffIntro | trueIntro
  deriving Inhabited, Repr, BEq

inductive ClauseOrigin where
  | global (c : Name)
  /-- Binder `idx` of goal position `goal`. -/
  | localHyp (goal : Nat) (idx : Nat)
  /-- A connective rule of the goal position the clause is local to. -/
  | builtin (k : Builtin)
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
per term (with a closed representative when there is one) if ground. -/
def recordNode (t : Term) (e : Expr) (path : Array Nat) : CompileM Unit := do
  if t.isGround then
    unless (← get).groundTypes.contains t do
      let ty ← compileType (← inferType e)
      modify fun s => { s with groundTypes := s.groundTypes.insert t ty, groundOrder := s.groundOrder.push t }
    unless e.hasFVar || (← get).groundExprs.contains t do
      modify fun s => { s with groundExprs := s.groundExprs.insert t e }
  else
    let ty ← compileType (← inferType e)
    modify fun s => { s with posTypes := s.posTypes.push (path, ty) }

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
  return t

/-- Compile a proposition as an opaque atom (SPEC §2.1, and amendment 1 of milestone 3:
every target and head, connective or not, is an atom with a constant or eigenvariable
head). Returns the template and the type templates of its rigid positions. -/
def compileAtom (R : Expr) (what : String) : CompileM (Term × Array (Array Nat × Option Term)) := do
  let R := R.consumeMData
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
    return (.app sym args, (← get).posTypes)

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
head `B` with premise `A`; `mpr`: head `A` with premise `B`). -/
partial def splitPaths (e : Expr) : CompileM (List (List Split)) :=
  telescope e fun _ body => do
    if let some (a, b) := binApp? ``And body then
      return [[]] ++ (← splitPaths a).map (.left :: ·) ++ (← splitPaths b).map (.right :: ·)
    if let some (a, b) := binApp? ``Iff body then
      return [[]] ++ (← splitPaths b).map (.mp :: ·) ++ (← splitPaths a).map (.mpr :: ·)
    return [[]]

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
    let (tgt, tys) ← compileAtom body "target"
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
        let (head, tys) ← compileAtom body s!"head of {name}"
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
        match sp with
        | .left => go a rest vars prems (steps.push .andLeft) varTys
        | .right => go b rest vars prems (steps.push .andRight) varTys
        | .mp => go b rest vars (prems.push a) (steps.push (.iffMp prems.size)) varTys
        | .mpr => go a rest vars (prems.push b) (steps.push (.iffMpr prems.size)) varTys
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

/-- Compile a closed goal and the constants `H` into a clause forest (SPEC §4). -/
def compile (goal : Expr) (H : Array Name) : MetaM Compiled := do
  if goal.hasFVar then throwError "solve_by_sat: internal: the goal is not closed after revert"
  let goalType ← preprocess goal
  let go : CompileM Unit := do
    discard <| compileGoal goalType #[] (isRoot := true)
    for c in H do
      let info ← getConstInfo c
      let ty ← preprocess info.type
      if ← isProp ty then
        for path in ← splitPaths ty do
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
  let ((), s1) ← go.run {}
  let s ← if s1.dataHeads.isEmpty then pure s1 else
    let keys := s1.dataHeads.foldl (fun h k => h.insert k) ({} : Std.HashSet (String × Nat))
    pure (← go.run { dataKeys := some keys }).2
  let forest : Forest := { goals := s.goals, clauses := s.clauses, varTypes := s.varTypes,
                           groundTypes := s.groundOrder.map (fun t => (t, s.groundTypes[t]!)),
                           levelVars := s.levelVars }
  match forest.check with
  | .error e => throwError "solve_by_sat: internal: ill-formed forest: {e}"
  | .ok () => pure ()
  return { forest, goalInfo := s.goalInfo, clauseInfo := s.clauseInfo, groundExprs := s.groundExprs,
           goalType, notes := s.notes }

end SolveBySat
