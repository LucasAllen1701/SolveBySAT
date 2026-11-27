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

/-- Milestone 9a-2: append clauses to a flattened forest, each global (`none`) or local to a goal
position, with its premises as new goal positions, and check the result. Used for the equality
rules of `SolveBySat.Rules` in the differential tests; the compiler builds the same clauses by
compiling their statements. -/
def extend (F : Forest) (cs : Array (ClauseT × Option Nat)) : Except String Forest := do
  let go : FM Unit := do
    for (c, loc) in cs do
      let F ← get
      let env := match loc with
        | some g => F.goals[g]!.env ++ F.goals[g]!.eig
        | none => #[]
      let id ← addClause c env loc
      -- a local clause is introduced at its goal position (the reference prover reads `hyps`)
      if let some g := loc then
        modify fun F => { F with goals := F.goals.modify g fun gp => { gp with hyps := gp.hyps.push id } }
  let ((), F') ← go.run F
  F'.check
  return F'

end Forest
/-! ## Equality rules (milestone 9a-2, M9_PLAN 3 and amendment 6.1): selection and clause shapes

Pure: the compiler (`SolveBySat.Compile`) runs this selection on the forest it compiled, builds each
selected rule's statement and proof in `MetaM`, compiles the statement as a clause, and checks that
the clause equals the one `mkRule` / `mkCore` build here (up to the names of its variables). The
differential tests (`Test/M9Diff.lean`) add the clauses `mkRule` / `mkCore` build to random forests.

- A *term position* of a rigid node is a template argument at which a rule may rewrite: the
  compiler marks them from the symbol's type (8a's eligibility, M8_PLAN amendment 4.1 decision 3).
  Every other argument (universe levels, types, instances, proofs, the head of an `app` node,
  arguments the result type depends on) is the node's *context*.
- A rule is made per (kind, symbol, position, context) (M9_DESIGN 6.4). Its *row* is that of its
  context's variables: none (`ground`), the root's eigenvariables only (`root`: the clause is local to
  the root), or the variables of one clause of H only (`hvars`: the rule is polymorphic in fresh
  copies of them). A context with any other variable fits no row and gives no rule.
- *Strict selection* (M9_DESIGN 6.5). The sources are the clauses whose head is an `Eq` atom (H,
  local hypotheses, `propext` paths). The source symbols are the symbols of their rigid sides; an
  eigenvariable is rigid (it is fixed in the proof), a clause variable is not. The
  terms of interest are the target atoms (from the atom itself) and the sources' sides; on each, the
  path from its root down to each rigid occurrence of a source symbol is a spine, and every node on
  it gets a rule at the position that leads down the spine: substitution at a target atom,
  congruence below. A spine that passes a non-term position gives no rules.
- The *liberal variant* gives every term position of every node of every atom (targets and heads) a
  rule; it is counted, not built (owner decision 2), except by the selection mutation of 3.2.
- The *equality core* (6.1, clarification 1): `Eq.refl`, `Eq.symm` and `Eq.trans` per (level, type)
  at which an `Eq` atom occurs after the rules are made: in a target, in a source's head, or in a
  congruence rule's head.
-/

namespace Rules

open Std

inductive Kind where
  | subst | congr | refl | symm | trans
  deriving BEq, Hashable, Repr, Inhabited, Ord

def Kind.name : Kind → String
  | .subst => "subst" | .congr => "congr" | .refl => "refl" | .symm => "symm" | .trans => "trans"

def Kind.isCore : Kind → Bool
  | .refl | .symm | .trans => true
  | _ => false

inductive Row where
  | ground | root | hvars
  deriving BEq, Hashable, Repr, Inhabited, Ord

def Row.name : Row → String
  | .ground => "ground" | .root => "root" | .hvars => "H"

/-- Where an atom is: the target of goal position `g`, or the head of clause `c`. -/
inductive Loc where
  | goal (g : Nat)
  | clause (c : Nat)
  deriving BEq, Hashable, Repr, Inhabited, Ord

/-- The term positions of a symbol (by template argument), and the number of leading template
arguments that are not positions in 8a's numbering (a constant's universe levels, an `app` node's
head), so that 8a's position is the template index minus `offset`. -/
structure Sig where
  mask : Array Bool
  offset : Nat
  /-- The positions that are not term positions but are positions of the symbol's type (testing
  only: the mutation check of M9_PLAN 3.2 makes rules at them, for the static motive check). -/
  mutantMask : Array Bool := #[]
  deriving Inhabited, Repr, BEq

abbrev Sigs := HashMap String Sig

/-- The key under which a node's signature is found: a constant by name and number of
arguments, an `app` node by its head variable and number of arguments. -/
def sigKey : Term → Option String
  | .app "app" as => match as[0]? with
    | some (Term.var v) => some s!"app:{v}/{as.size}"
    | _ => none
  | .app s as => if s.startsWith "c:" then some s!"{s}/{as.size}" else none
  | .var _ => none

/-- The symbol of a rigid node, for matching source symbols: an `app` node by its head variable;
binders, sorts, levels, bound variables and the proof placeholder have none. -/
def occSym : Term → Option String
  | .var _ => none
  | .app "app" as => match as[0]? with
    | some (Term.var v) => some s!"app:{v}"
    | _ => none
  | .app s _ =>
    if s == "lam" || s == "pi" || s == "sort" || s.startsWith Term.levelPrefix || s.startsWith "bvar:" ||
       s == Term.proofSym then none
    else some s

def subtermAt (t : Term) (path : Array Nat) : Option Term :=
  path.foldlM (fun u i => u.args[i]?) t

def atomAt (F : Forest) : Loc → Term
  | .goal g => F.goals[g]!.tgt
  | .clause c => F.clauses[c]!.head

def isEqAtom : Term → Bool
  | .app "c:Eq" as => as.size == 4
  | _ => false

def eqAtom (u τ a b : Term) : Term := .app "c:Eq" #[u, τ, a, b]

/-- A source (M9_PLAN 3.1): a clause that is not built in and not a data clause, whose head is an
`Eq` atom. -/
def isSource (F : Forest) (c : Nat) : Bool :=
  let cl := F.clauses[c]!
  !cl.builtin && cl.dataVal.isNone && isEqAtom cl.head

/-- An occurrence of a rule: the node at `path` in the atom at `loc`, rewritten at template
argument `pos`. For a core rule, the `Eq` atom at `loc` (path and pos are empty). -/
structure Occ where
  loc : Loc
  path : Array Nat := #[]
  pos : Nat := 0
  kind : Kind
  deriving BEq, Hashable, Repr, Inhabited

/-- The owner of each static variable: the goal position of an eigenvariable, the clause of a
clause variable. -/
def owners (F : Forest) : HashMap String Loc := Id.run do
  let mut m : HashMap String Loc := {}
  for h : g in [0:F.goals.size] do
    for b in F.goals[g].eig do m := m.insert b (.goal g)
  for h : c in [0:F.clauses.size] do
    for b in F.clauses[c].vars do m := m.insert b (.clause c)
  return m

partial def varsInOrder (ts : Array Term) : Array String :=
  ts.foldl go #[]
where
  go (acc : Array String) : Term → Array String
    | .var n => if acc.contains n then acc else acc.push n
    | .app _ as => as.foldl go acc

/-- The row of a context with variables `vs` (in a forest without rules). -/
def rowOf (F : Forest) (own : HashMap String Loc) (vs : Array String) : Option Row := do
  if vs.isEmpty then return .ground
  let os ← vs.mapM (own[·]?)
  if os.all (· == .goal 0) then return .root
  let .clause c := os[0]! | none
  unless os.all (· == .clause c) do none
  let cl := F.clauses[c]!
  unless cl.localOf.isNone && !cl.builtin do none
  return .hvars

/-- Rename the variables of an `hvars` context to `pre ++ "κi"`, in order of first occurrence. -/
def canonMap (row : Row) (ts : Array Term) (pre : String := "") : HashMap String String :=
  if row != .hvars then {} else
    (varsInOrder ts).foldl (init := {}) fun m v => m.insert v s!"{pre}κ{m.size}"

def rename (m : HashMap String String) (t : Term) : Term :=
  t.subst fun v => (m[v]?).map Term.var

def blankSym : String := "□"

/-- The node with its term positions blanked: its context. -/
def blank (node : Term) (sig : Sig) : Term :=
  match node with
  | .app s as => .app s (as.mapIdx fun j a => if sig.mask[j]?.getD false then .const blankSym else a)
  | t => t

/-- A rule's identity: kind, row, and its context in canonical form (`hvars` variables renamed),
with the position for substitution and congruence. -/
structure Key where
  kind : Kind
  row : Row
  tmpl : Array Term
  pos : Nat
  deriving BEq, Hashable, Repr, Inhabited

def Key.symbol (k : Key) : String := match k.tmpl[0]? with
  | some (Term.app "app" as) => match as[0]? with | some (Term.var v) => s!"app:{v}" | _ => "app"
  | some (Term.app s _) => s
  | _ => "?"

def occKey? (F : Forest) (own : HashMap String Loc) (sigs : Sigs) (o : Occ) : Option Key := do
  let atom := atomAt F o.loc
  if o.kind.isCore then
    let .app "c:Eq" as := atom | none
    let ctx := #[as[0]!, as[1]!]
    let row ← rowOf F own (varsInOrder ctx)
    let m := canonMap row ctx
    return { kind := o.kind, row, tmpl := ctx.map (rename m), pos := 0 }
  let node ← subtermAt atom o.path
  let sig ← sigs[← sigKey node]?
  let b := blank node sig
  let row ← rowOf F own (varsInOrder #[b])
  let m := canonMap row #[b]
  return { kind := o.kind, row, tmpl := #[rename m b], pos := o.pos }

structure Selection where
  /-- The rules made (strict, or liberal for the selection mutation), deduplicated by key, in
  order of first occurrence: targets in goal order, then sources' sides, each in pre-order. -/
  rules : Array (Key × Occ) := #[]
  /-- The rules the liberal variant would add to the strict ones (counted, not built). -/
  liberalExtra : Array Key := #[]
  /-- Source-symbol occurrences on a spine that passes a non-term position. -/
  broken : Nat := 0
  /-- Spine nodes whose context fits no row. -/
  noRow : Nat := 0
  /-- Every liberal candidate (for the context mutation of M9_PLAN 3.2). -/
  liberal : Array (Key × Occ) := #[]
  sources : Array Nat := #[]
  symbols : Array String := #[]
  deriving Inhabited

/-- The atoms of a forest that rules can rewrite: the targets of goal positions that are not data
positions, and the heads of clauses that are neither built in nor data clauses. -/
def atomLocs (F : Forest) : Array Loc := Id.run do
  let mut out := #[]
  for h : g in [0:F.goals.size] do
    if F.goals[g].dataVar.isNone then out := out.push (.goal g)
  for h : c in [0:F.clauses.size] do
    let cl := F.clauses[c]
    if !cl.builtin && cl.dataVal.isNone then out := out.push (.clause c)
  return out

/-- Every node path below (and including) `root` in `t`, in pre-order. -/
partial def nodePaths (t : Term) (root : Array Nat) : Array (Array Nat) :=
  match subtermAt t root with
  | none => #[]
  | some u => go u root #[]
where
  go (u : Term) (p : Array Nat) (acc : Array (Array Nat)) : Array (Array Nat) :=
    let acc := acc.push p
    (Array.range u.args.size).foldl (fun acc i => go u.args[i]! (p.push i) acc) acc

/-- Strict selection (and the liberal count). `symbols` replaces the automatic choice of source
symbols (`rewriteSymbols`); `liberal` builds the liberal variant instead (the selection mutation). -/
def select (F : Forest) (sigs : Sigs) (symbols : Option (Array String) := none) (liberal : Bool := false)
    (mutant : Bool := false) : Selection := Id.run do
  let own := owners F
  -- an eigenvariable is rigid: a side or an occurrence that is one has the symbol `eig:<name>`
  let sym? := fun (t : Term) => match t with
    | .var v => if (own[v]? matches some (.goal _)) then some s!"eig:{v}" else none
    | t => occSym t
  let sources := (Array.range F.clauses.size).filter (isSource F)
  let mut syms : Array String := #[]
  for c in sources do
    let as := F.clauses[c]!.head.args
    for side in #[as[2]!, as[3]!] do
      if let some s := sym? side then
        unless syms.contains s do syms := syms.push s
  if let some ss := symbols then syms := ss
  let isTerm := fun (node : Term) (k : Nat) =>
    match sigKey node >>= (sigs[·]?) with
    | some sig => sig.mask[k]?.getD false || (mutant && sig.mutantMask[k]?.getD false)
    | none => false
  -- the spines: (loc, root path, is a target atom)
  let mut roots : Array (Loc × Array Nat) := #[]
  for h : g in [0:F.goals.size] do
    if F.goals[g].dataVar.isNone then roots := roots.push (.goal g, #[])
  for c in sources do
    roots := roots.push (.clause c, #[2])
    roots := roots.push (.clause c, #[3])
  let mut seen : HashSet Key := {}
  let mut strict : Array (Key × Occ) := #[]
  let mut broken := 0
  let mut noRow := 0
  for (loc, root) in roots do
    let atom := atomAt F loc
    for q in nodePaths atom root do
      if q == root then continue
      let some s := subtermAt atom q >>= sym? | continue
      unless syms.contains s do continue
      -- the spine from the root down to q
      let mut ok := true
      let mut occs := #[]
      for d in [root.size:q.size] do
        let p := q.extract 0 d
        let node := (subtermAt atom p).get!
        let k := q[d]!
        unless isTerm node k do ok := false; break
        occs := occs.push { loc, path := p, pos := k, kind := if p.isEmpty then .subst else .congr : Occ }
      unless ok do broken := broken + 1; continue
      for o in occs do
        match occKey? F own sigs o with
        | none => noRow := noRow + 1
        | some key =>
          unless seen.contains key do
            seen := seen.insert key
            strict := strict.push (key, o)
  -- the liberal variant: every term position of every node of every atom
  let mut lib : Array (Key × Occ) := #[]
  let mut libSeen : HashSet Key := {}
  for loc in atomLocs F do
    let atom := atomAt F loc
    for p in nodePaths atom #[] do
      let node := (subtermAt atom p).get!
      for k in [0:node.args.size] do
        unless isTerm node k do continue
        let o : Occ := { loc, path := p, pos := k, kind := if p.isEmpty then .subst else .congr }
        let some key := occKey? F own sigs o | continue
        unless libSeen.contains key do
          libSeen := libSeen.insert key
          lib := lib.push (key, o)
  let extra := (lib.filter fun (k, _) => !seen.contains k).map (·.1)
  return { rules := if liberal then lib else strict, liberalExtra := extra, broken, noRow, sources,
           symbols := syms, liberal := lib }

/-- The `Eq` atoms at which the equality core is made (6.1, clarification 1), in a forest with the
rules: every target, the head of every source, and the head of every congruence rule (`congr`, the
clause ids of the congruence rules). Deduplicated by key, in order of first occurrence. Kinds that H
already has (`skip`) are left out, and `trans` unless `eqTrans`. -/
def selectCore (F : Forest) (sources congr : Array Nat) (skip : Array Kind) (eqTrans : Bool) :
    Array (Key × Occ) := Id.run do
  let own := owners F
  let mut locs : Array Loc := #[]
  for h : g in [0:F.goals.size] do
    if F.goals[g].dataVar.isNone then locs := locs.push (.goal g)
  for c in sources ++ congr do locs := locs.push (.clause c)
  let kinds := #[Kind.refl, .symm] ++ (if eqTrans then #[Kind.trans] else #[])
  let kinds := kinds.filter (!skip.contains ·)
  let mut seen : HashSet Key := {}
  let mut out := #[]
  for loc in locs do
    unless isEqAtom (atomAt F loc) do continue
    for k in kinds do
      let o : Occ := { loc, kind := k }
      let some key := occKey? F own {} o | continue
      unless seen.contains key do
        seen := seen.insert key
        out := out.push (key, o)
  return out

/-- The types a substitution or congruence rule needs that the forest does not give: the level and
type of the rewritten position, and (congruence) of the node. -/
structure RuleTypes where
  posLvl : Term
  posTy : Term
  resLvl : Term := .const "lvl:zero"
  resTy : Term := .const "Prop"
  deriving Inhabited, Repr

/-- The 8a position of a key (template index minus the signature's offset). -/
def Key.pos8a (k : Key) (sigs : Sigs) : Nat :=
  match k.tmpl[0]? >>= sigKey >>= (sigs[·]?) with
  | some sig => k.pos - sig.offset
  | none => k.pos

/-- The clause of a substitution or congruence rule at occurrence `o`, its variables named with
the prefix `pre`, as a tree to append to the forest (global, or local to the root for the `root`
row). Variables: the context's (renamed, `hvars` only), then `a`, `b`, then one per other term
position. Congruence: `a = b → f(…a…) = f(…b…)`; substitution: `a = b → P(…b…) → P(…a…)`. -/
def mkRule (F : Forest) (sigs : Sigs) (key : Key) (o : Occ) (ty : RuleTypes) (name pre : String) :
    ClauseT × Option Nat :=
  let node := (subtermAt (atomAt F o.loc) o.path).get!
  let sig := sigs[(sigKey node).get!]!
  let m := canonMap key.row #[blank node sig, ty.posLvl, ty.posTy, ty.resLvl, ty.resTy] pre
  let ctxVars := (varsInOrder #[blank node sig, ty.posLvl, ty.posTy, ty.resLvl, ty.resTy]).filterMap (m[·]?)
  let a := s!"{pre}a"
  let b := s!"{pre}b"
  let xs := (Array.range node.args.size).filter fun j => j != key.pos && sig.mask[j]!
  let withArg (v : String) : Term := match node with
    | .app s as => .app s (as.mapIdx fun j t =>
        if j == key.pos then .var v else if sig.mask[j]! then .var s!"{pre}x{j}" else rename m t)
    | t => t
  let eqAB := eqAtom (rename m ty.posLvl) (rename m ty.posTy) (.var a) (.var b)
  let vars := (ctxVars ++ #[a, b] ++ xs.map (s!"{pre}x{·}")).toList
  let loc := if key.row == .root then some 0 else none
  let goal := fun (t : Term) => GoalT.mk t [] []
  match key.kind with
  | .congr =>
    (.mk name (eqAtom (rename m ty.resLvl) (rename m ty.resTy) (withArg a) (withArg b)) vars [goal eqAB], loc)
  | _ =>
    (.mk name (withArg a) vars [goal eqAB, goal (withArg b)], loc)

/-- The clause of a core rule at the (level, type) of `key`. -/
def mkCore (key : Key) (name pre : String) : ClauseT × Option Nat :=
  let m := canonMap key.row key.tmpl pre
  let ctxVars := (varsInOrder key.tmpl).filterMap (m[·]?)
  -- the key's tmpl is already canonical (κi); prefix them
  let u := rename m key.tmpl[0]!
  let τ := rename m key.tmpl[1]!
  let x := Term.var s!"{pre}x"
  let y := Term.var s!"{pre}y"
  let z := Term.var s!"{pre}z"
  let loc := if key.row == .root then some 0 else none
  let goal := fun (t : Term) => GoalT.mk t [] []
  let vs := ctxVars.toList
  match key.kind with
  | .refl => (.mk name (eqAtom u τ x x) (vs ++ [s!"{pre}x"]) [], loc)
  | .symm => (.mk name (eqAtom u τ y x) (vs ++ [s!"{pre}x", s!"{pre}y"]) [goal (eqAtom u τ x y)], loc)
  | _ => (.mk name (eqAtom u τ x z) (vs ++ [s!"{pre}x", s!"{pre}y", s!"{pre}z"])
            [goal (eqAtom u τ x y), goal (eqAtom u τ y z)], loc)

/-- The name of a rule clause: `rw.<symbol>.<kind>.<8a position>@<row>#<index>`, or
`rw.Eq.<kind>@<row>#<index>` for the core. -/
def ruleName (sigs : Sigs) (key : Key) (idx : Nat) : String :=
  let sym := (key.symbol.drop (if key.symbol.startsWith "c:" then 2 else 0)).toString
  if key.kind.isCore then s!"rw.Eq.{key.kind.name}@{key.row.name}#{idx}"
  else s!"rw.{sym}.{key.kind.name}.{key.pos8a sigs}@{key.row.name}#{idx}"

/-- Are two clause shapes equal up to a renaming of variables (a bijection, built as it goes)? -/
partial def alphaEq (ts us : Array Term) : Bool :=
  ts.size == us.size && ((ts.zip us).foldlM (fun m (t, u) => go t u m) (({} : HashMap String String), ({} : HashMap String String))).isSome
where
  go (t u : Term) (m : HashMap String String × HashMap String String) : Option (HashMap String String × HashMap String String) :=
    match t, u with
    | .var x, .var y =>
      match m.1[x]?, m.2[y]? with
      | some y', some x' => if y' == y && x' == x then some m else none
      | none, none => some (m.1.insert x y, m.2.insert y x)
      | _, _ => none
    | .app f as, .app g bs =>
      if f != g || as.size != bs.size then none
      else (as.zip bs).foldlM (fun m (a, b) => go a b m) m
    | _, _ => none

end Rules
end SolveBySat
