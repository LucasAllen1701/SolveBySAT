/-
SolveBySat.Forest: clauses, goal positions, frames, and the well-formedness check
(SPEC §4.2, §4.3). Port of `Goal`, `Clause` and `Problem` in `reference/enc.py`.

Forests are written as trees (`GoalT`, `ClauseT`) and flattened into a `Forest`, whose
goal positions and clauses are numbered in the prototype's order: the root goal gets id 0,
then pre-order through local hypotheses and premises, then the global clauses.
Pure: no `Lean.Meta`.
-/
import SolveBySat.Term

namespace SolveBySat

mutual
/-- A goal formula: eigenvariables `eig`, local hypotheses `hyps`, target `tgt`. -/
inductive GoalT where
  | mk (tgt : Term) (eig : List String) (hyps : List ClauseT)
/-- A clause formula: clause variables `vars`, premises `prems`, head `head`. -/
inductive ClauseT where
  | mk (name : String) (head : Term) (vars : List String) (prems : List GoalT)
end

instance : Inhabited GoalT := ⟨.mk default [] []⟩
instance : Inhabited ClauseT := ⟨.mk default default [] []⟩

/-- Goal position `g` (SPEC §4.2). -/
structure GoalPos where
  tgt : Term
  eig : Array String
  /-- Ids of the clauses made from this goal's Prop binders. -/
  hyps : Array Nat
  /-- `Env(g)`, sorted. -/
  env : Array String
  /-- Type templates of the non-ground rigid positions of `tgt`, by template path. `none`
  means unknown (untyped forests, or a type that could not be compiled). -/
  tgtTypes : Array (Array Nat × Option Term) := #[]
  /-- For a data position (SPEC §6.9): the clause variable whose value a child builds. The
  position has no binders and its target is the variable's type. -/
  dataVar : Option String := none
  deriving Inhabited, Repr

/-- Clause `c` (SPEC §4.2). -/
structure Clause where
  name : String
  head : Term
  vars : Array String
  /-- Goal position id of each premise. -/
  prems : Array Nat
  /-- `Env(c)`, sorted. -/
  env : Array String
  /-- `some g` if the clause is local to goal position `g`; `none` for a global clause. -/
  localOf : Option Nat
  /-- Type templates of the non-ground rigid positions of `head`, by template path. -/
  headTypes : Array (Array Nat × Option Term) := #[]
  /-- A built-in connective rule of goal position `localOf` (SPEC §4.2): applicable only
  at the node that owns that goal position (`cl(β, c) ⇒ u(β, β)`, §6.3). -/
  builtin : Bool := false
  /-- Data positions (SPEC §6.9): for some clause variables, an optional child that builds
  the variable's value. Child indices follow the premises. -/
  dataPos : Array (String × Nat) := #[]
  /-- For a data clause (SPEC §6.9): the value template, the constant or eigenvariable
  applied to the clause's variables. Its head is the result type. -/
  dataVal : Option Term := none
  /-- Type templates of the value's positions, by path from the value (`#[]` = the value). -/
  valueTypes : Array (Array Nat × Option Term) := #[]
  deriving Inhabited, Repr

structure Forest where
  goals : Array GoalPos := #[]
  clauses : Array Clause := #[]
  /-- Type template of each static variable (term kind). Missing or `none`: unknown. -/
  varTypes : Array (String × Option Term) := #[]
  /-- Type template of each ground term that occurs in a template. -/
  groundTypes : Array (Term × Option Term) := #[]
  /-- Static variables of kind `level` (universe parameters of constants in `H`, SPEC
  §4.3); all others are of kind `term`. -/
  levelVars : Array String := #[]
  deriving Inhabited, Repr

namespace Forest

def sortStrs (xs : Array String) : Array String := xs.qsort (· < ·)

/-- The goal frame of `g`: `Env(g) ∪ eig(g)`. -/
def goalFrame (F : Forest) (g : Nat) : Array String :=
  sortStrs (F.goals[g]!.env ++ F.goals[g]!.eig)

/-- The clause frame of `c`: `Env(c) ∪ vars(c)`, sorted. -/
def clauseFrame (F : Forest) (c : Nat) : Array String :=
  sortStrs (F.clauses[c]!.env ++ F.clauses[c]!.vars)

/-- Largest number of children of any clause (`A`): premises and data positions. -/
def maxPrems (F : Forest) : Nat := F.clauses.foldl (fun m c => max m (c.prems.size + c.dataPos.size)) 0

/-- All eigenvariable binders `(g, b)`, in goal order (SPEC §5.3, `E`). -/
def eigs (F : Forest) : Array (Nat × String) := Id.run do
  let mut out := #[]
  for g in [0:F.goals.size] do
    for b in F.goals[g]!.eig do out := out.push (g, b)
  return out

private abbrev FM := StateT Forest (Except String)

private def checkScope (what : String) (t : Term) (scope : Array String) : FM Unit := do
  for v in t.varsOf do
    unless scope.contains v do
      throw s!"{what} {t} mentions variable {v}, which is not in scope"

mutual
private partial def addGoal (g : GoalT) (env : Array String) : FM Nat := do
  let .mk tgt eig hyps := g
  let id := (← get).goals.size
  let env' := Forest.sortStrs env
  modify fun F => { F with goals := F.goals.push { tgt, eig := eig.toArray, hyps := #[], env := env' } }
  let scope := env ++ eig.toArray
  checkScope "target" tgt scope
  let mut hs := #[]
  for h in hyps do hs := hs.push (← addClause h scope (some id))
  modify fun F => { F with goals := F.goals.modify id fun gp => { gp with hyps := hs } }
  return id

private partial def addClause (c : ClauseT) (env : Array String) (loc : Option Nat) : FM Nat := do
  let .mk name head vars prems := c
  let id := (← get).clauses.size
  let cl : Clause := { name, head, vars := vars.toArray, prems := #[], env := Forest.sortStrs env, localOf := loc }
  modify fun F => { F with clauses := F.clauses.push cl }
  let scope := env ++ vars.toArray
  checkScope s!"head of {name}:" head scope
  let mut ps := #[]
  for p in prems do ps := ps.push (← addGoal p scope)
  modify fun F => { F with clauses := F.clauses.modify id fun cl => { cl with prems := ps } }
  return id
end

/-- Well-formedness (SPEC §4.3): every template is over its frame, every binder name is
unique, and no head or target is a bare variable. -/
def check (F : Forest) : Except String Unit := do
  for g in F.goals do
    for v in g.tgt.varsOf do
      unless g.env.contains v || g.eig.contains v do
        throw s!"target {g.tgt} mentions variable {v}, which is not in scope"
    if g.tgt.isVar then throw s!"target {g.tgt} is a bare variable"
  for c in F.clauses do
    for v in c.head.varsOf do
      unless c.env.contains v || c.vars.contains v do
        throw s!"head of {c.name}: {c.head} mentions variable {v}, which is not in scope"
    if c.head.isVar then throw s!"head of {c.name} is a bare variable"
    if let some v := c.dataVal then
      for x in v.varsOf do
        unless c.env.contains x || c.vars.contains x do
          throw s!"value of {c.name}: {v} mentions variable {x}, which is not in scope"
    for (b, g) in c.dataPos do
      unless c.vars.contains b do throw s!"data position of {c.name} for {b}, which is not its variable"
      unless F.goals[g]!.dataVar == some b do throw s!"goal position {g} is not the data position of {b}"
  let binders := F.goals.flatMap (·.eig) ++ F.clauses.flatMap (·.vars)
  let mut seen : Std.HashSet String := {}
  for b in binders do
    if seen.contains b then throw s!"binder name {b} is not unique"
    seen := seen.insert b

/-- For frame pruning (SPEC §6.10, milestone 6 requirement 2): the static variables that
occur anywhere below each goal position and each clause. Below a goal position: its
target, the types of its eigenvariables and of its target positions, its data variable
(a data position "uses" the variable it builds), and everything below its local clauses
(hypotheses, built-in rules, eigenvariable data clauses). Below a clause: its head, its
value, the types of its variables and of its head and value positions, and everything
below its premises and data positions. The forest is a tree, so each set is computed
once. -/
partial def varsBelow (F : Forest) : Array (Std.HashSet String) × Array (Std.HashSet String) := Id.run do
  let types : Std.HashMap String (Option Term) := F.varTypes.foldl (fun m (b, t) => m.insert b t) {}
  let tyVars := fun (t? : Option Term) => match t? with | some t => t.varsOf | none => {}
  let mut locals : Array (Array Nat) := Array.replicate F.goals.size #[]
  for h : c in [0:F.clauses.size] do
    if let some g := F.clauses[c].localOf then locals := locals.modify g (·.push c)
  let mut gs : Array (Option (Std.HashSet String)) := Array.replicate F.goals.size none
  let mut cs : Array (Option (Std.HashSet String)) := Array.replicate F.clauses.size none
  -- a goal or clause is computed once all its children are (repeat until all are)
  let order : Array (Bool × Nat) :=
    ((Array.range F.goals.size).map (true, ·) ++ (Array.range F.clauses.size).map (false, ·))
  let mut done := false
  while !done do
    done := true
    for (isGoal, i) in order do
      if isGoal then
        if gs[i]!.isSome then continue
        let gp := F.goals[i]!
        let kids := locals[i]!
        if kids.any (cs[·]!.isNone) then done := false; continue
        let mut v := gp.tgt.varsOf
        if let some b := gp.dataVar then v := v.insert b
        for b in gp.eig do v := v.insertMany (tyVars ((types.get? b).getD none))
        for (_, t) in gp.tgtTypes do v := v.insertMany (tyVars t)
        for c in kids do v := v.insertMany cs[c]!.get!
        gs := gs.set! i (some v)
      else
        if cs[i]!.isSome then continue
        let cl := F.clauses[i]!
        let kids := cl.prems ++ cl.dataPos.map (·.2)
        if kids.any (gs[·]!.isNone) then done := false; continue
        let mut v := cl.head.varsOf
        if let some val := cl.dataVal then v := v.insertMany val.varsOf
        for b in cl.vars do v := v.insertMany (tyVars ((types.get? b).getD none))
        for (_, t) in cl.headTypes do v := v.insertMany (tyVars t)
        for (_, t) in cl.valueTypes do v := v.insertMany (tyVars t)
        for g in kids do v := v.insertMany gs[g]!.get!
        cs := cs.set! i (some v)
  return (gs.map (·.getD {}), cs.map (·.getD {}))

/-- Flatten and check a forest: every template is over its frame, every binder name is
unique, and no head or target is a bare variable. -/
def build (goal : GoalT) (globals : List ClauseT) : Except String Forest := do
  let go : FM Unit := do
    discard <| addGoal goal #[]
    for c in globals do discard <| addClause c #[] none
  let ((), F) ← go.run {}
  F.check
  return F

end Forest
end SolveBySat
