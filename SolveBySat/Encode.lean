/-
SolveBySat.Encode: the clause families of SPEC §6 (6.1 to 6.8, with typing and levels).

A port of `encode` in `reference/enc.py`. Families are emitted in the prototype's order
and labels are allocated lazily as there, so variable and clause counts agree with the
prototype on the same forest (checked in Test/M1.lean against numbers produced by
`reference/enc.py`). Pure: no `Lean.Meta`.
-/
import SolveBySat.Forest
import SolveBySat.CNF
import Std.Data.HashMap

namespace SolveBySat

open CNF

structure EncodeOptions where
  /-- Family 6.8. Switched off in the differential test, as in `diff.py`. -/
  groundness : Bool := true
  /-- The scope clauses of 6.7. Switched off only by the mutation check. -/
  scope : Bool := true
  /-- The occurs check of 6.7. Switched off only by the mutation check. -/
  occurs : Bool := true
  /-- Use the prototype's rank width `N·(d+1)` instead of the default
  `N·(most rigid positions in a target + most in a head) + largest ground height`.
  Only the size cross-check against the prototype sets this. -/
  protoRank : Bool := false
  /-- The static half of the typing rule of 6.8: drop a grounding candidate when its type
  and the variable's type are both closed and differ. -/
  staticTyping : Bool := true
  /-- The typing clause of 6.8: `sv ⇒ L(type of b) = L(type of o)` when both types are
  known and not both closed (or both closed and `staticTyping` is off). -/
  typingClause : Bool := true
  /-- The `open` label bit (§5.3). Switched off only by the mutation check. -/
  openBit : Bool := true
  /-- The static filter of 6.9: proof clauses only at proposition positions, data clauses
  only at data positions. Switched off only by the mutation check. -/
  dataFilter : Bool := true
  -- Refinements of SPEC §6.10 and the ladder at-most-one (milestone 6). Each can be
  -- switched off on its own; `EncodeOptions.allOff` switches all of them off.
  /-- Symmetry breaking: breadth-first numbering of the nodes. -/
  symmetry : Bool := true
  /-- Pair pruning: a decomposition pair whose templates do not unify (variables renamed
  apart) only gets a clause saying that the two labels differ in their idx field. -/
  pairPruning : Bool := true
  /-- Candidate pruning: a grounding candidate whose type does not unify with the
  variable's type (variables renamed apart) is dropped. -/
  candidatePruning : Bool := true
  /-- Frame pruning: a link copies only the variables that occur below the child (or in
  the local clause), not the whole frame. -/
  framePruning : Bool := true
  /-- The ladder (sequential) at-most-one encoding for 6 or more literals. -/
  ladderAmo : Bool := true
  /-- Count variables and clauses per family without storing the clauses (milestone 7c,
  EVAL_PLAN §4.1 and §10.9). The encoding is built exactly as otherwise; the resulting
  `cnf.clauses` is empty, so it cannot be solved. Only the measurement harness sets it. -/
  countOnly : Bool := false

/-- A named refinement configuration, for testing each refinement on its own: `all`
(the default), `none`, or exactly one of `symmetry`, `pair`, `candidate`, `frame`, `ladder`
on and the others off. -/
def EncodeOptions.config (name : String) (o : EncodeOptions := {}) : Option EncodeOptions :=
  let off := { o with symmetry := false, pairPruning := false, candidatePruning := false,
                      framePruning := false, ladderAmo := false }
  match name with
  | "all" => some o
  | "none" => some off
  | "symmetry" => some { off with symmetry := true }
  | "pair" => some { off with pairPruning := true }
  | "candidate" => some { off with candidatePruning := true }
  | "frame" => some { off with framePruning := true }
  | "ladder" => some { off with ladderAmo := true }
  | _ => none

/-- All milestone 6 refinements off (the milestone 5 encoding). -/
def EncodeOptions.allOff (o : EncodeOptions := {}) : EncodeOptions :=
  { o with symmetry := false, pairPruning := false, candidatePruning := false,
           framePruning := false, ladderAmo := false }

inductive Side where
  | goal
  | clause
  deriving BEq, Hashable, Repr, Inhabited

/-- Whose type a type template is: a static variable (its slots are on `side`), or a
template position. -/
inductive TyOwner where
  | var (side : Side) (name : String)
  | pos (side : Side) (tid : Nat) (path : Array Nat)
  /-- A position of the value of data clause `clause`. -/
  | val (clause : Nat) (path : Array Nat)
  deriving BEq, Hashable, Repr, Inhabited

/-- Term objects of SPEC §5.2. -/
inductive Obj where
  /-- A distinct closed ground subterm, shared by all nodes. -/
  | ground (t : Term)
  /-- Node `node`'s copy of the non-ground template position `path` below the atom of
  goal position / clause `tid` (on `side`); `sym` is its head symbol and arity. -/
  | rigid (node : Nat) (side : Side) (tid : Nat) (path : Array Nat) (sym : String × Nat) (opn : Bool)
  /-- The goal or clause slot of static variable `name` at node `node`. -/
  | slot (node : Nat) (side : Side) (name : String)
  /-- Node `node`'s copy of the non-ground position `path` of the type template of `owner`
  (SPEC §6.8: type templates are instantiated per node and labelled like any template).
  Never a grounding candidate. -/
  | trigid (node : Nat) (owner : TyOwner) (path : Array Nat) (sym : String × Nat) (opn : Bool)
  /-- Node `node`'s copy of position `path` of the value of data clause `clause` (SPEC
  §6.9): a per-node rigid object, active only when the node applies the clause, even if
  the value is closed (`path = #[]` is the value itself). A grounding candidate. -/
  | value (node : Nat) (clause : Nat) (path : Array Nat) (sym : String × Nat) (opn : Bool)
  deriving BEq, Hashable, Repr, Inhabited

/-- Structural variables of SPEC §5.1. -/
structure Vars where
  N : Nat
  A : Nat
  act : Array BLit
  /-- `cl[α][c]`. -/
  cl : Array (Array BLit)
  /-- `gp[α][g]`. -/
  gp : Array (Array BLit)
  /-- `y(α, β, k)` for `α < β`, `k < A`. -/
  y : Std.HashMap (Nat × Nat × Nat) BLit
  /-- `anc(γ, β)` for `γ < β`. -/
  anc : Std.HashMap (Nat × Nat) BLit
  /-- `u(β, γ)` for `γ ≤ β`. -/
  u : Std.HashMap (Nat × Nat) BLit
  deriving Inhabited

structure EncodeInfo where
  W : Nat
  SB : Nat
  IB : Nat
  RB : Nat
  pairs : Nat
  rigid : Nat
  ground : Nat
  /-- Rigid objects of type templates. -/
  typeRigid : Nat := 0
  /-- Typing clauses emitted (6.8). -/
  typing : Nat := 0
  deriving Repr, Inhabited

structure Encoding where
  cnf : CNF
  vars : Vars
  info : EncodeInfo
  /-- Groundness witnesses: for `(α, c, b)`, each kept candidate with its `sv` variable
  and whether its type and the variable's type are both known (otherwise no typing clause
  was emitted for the pair, SPEC §6.8 / milestone 4 requirement 2). -/
  sv : Std.HashMap (Nat × Nat × String) (Array (Obj × BLit × Bool)) := {}
  /-- Final label of every object (for tests). -/
  labels : Std.HashMap Obj (Array BLit) := {}
  /-- Number of times a fresh label was allocated for each object (for tests: must be 1). -/
  allocs : Std.HashMap Obj Nat := {}
  deriving Inhabited

/-- Smallest `b` with `2^b ≥ x` (Python `math.ceil(math.log2(x))` for `x ≥ 1`). -/
def clog2 (x : Nat) : Nat := Id.run do
  let mut b := 0
  while 2 ^ b < x do b := b + 1
  return b

namespace Encode

/-- The per-node object graph (enc.py `build`, `children`, `actlit`, `rigid`). -/
structure Struct where
  children : Std.HashMap Obj (Array Obj) := {}
  actlit : Std.HashMap Obj BLit := {}
  rigid : Array Obj := #[]
  /-- Ground objects with children, in creation order (they join decomposition). -/
  groundApps : Array Obj := #[]
  /-- `root[(α, side, id)]`: the argument objects of the atom. -/
  root : Std.HashMap (Nat × Side × Nat) (Array Obj) := {}
  /-- Rigid objects of type templates. -/
  trigid : Array Obj := #[]
  /-- The object standing for the type of `owner` at a node. -/
  tyRoot : Std.HashMap (Nat × TyOwner) Obj := {}
  /-- The value object of data clause `c` at node `a`. -/
  valueRoot : Std.HashMap (Nat × Nat) Obj := {}

/-- Build node `a`'s objects for the value template of data clause `c`. The value itself is
always a per-node object; its subterms are per-node objects if not ground, shared ground
objects otherwise. -/
partial def buildValue (a c : Nat) (al : BLit) (t : Term) (path : Array Nat) (root : Bool) :
    StateM Struct Obj := do
  match t with
  | .var n => return .slot a .clause n
  | .app s as => do
    if t.isGround && !root then
      let o := Obj.ground t
      unless (← get).children.contains o do
        let mut kids := #[]
        for h : i in [0:as.size] do kids := kids.push (← buildValue a c al as[i] (path.push i) false)
        modify fun S => { S with children := S.children.insert o kids, actlit := S.actlit.insert o .tt,
                                 groundApps := if kids.isEmpty then S.groundApps else S.groundApps.push o }
      return o
    let o := Obj.value a c path (s, as.size) t.isOpen
    let mut kids := #[]
    for h : i in [0:as.size] do kids := kids.push (← buildValue a c al as[i] (path.push i) false)
    modify fun S => { S with children := S.children.insert o kids, actlit := S.actlit.insert o al,
                             rigid := S.rigid.push o }
    return o

/-- Build the objects of a ground term (shared by all nodes). -/
partial def buildGround (t : Term) : StateM Struct Obj := do
  let o := Obj.ground t
  unless (← get).children.contains o do
    let mut kids := #[]
    for a in t.args do kids := kids.push (← buildGround a)
    modify fun S => { S with children := S.children.insert o kids, actlit := S.actlit.insert o .tt,
                             groundApps := if kids.isEmpty then S.groundApps else S.groundApps.push o }
  return o

/-- Build node `a`'s objects for the type template `t` of `owner`; variables are the slots
of `side` at `a`, and the objects are active with `al`. -/
partial def buildType (a : Nat) (owner : TyOwner) (side : Side) (al : BLit) (t : Term) (path : Array Nat) :
    StateM Struct Obj := do
  match t with
  | .var n => return .slot a side n
  | .app s as =>
    if t.isGround then buildGround t
    else
      let o := Obj.trigid a owner path (s, as.size) t.isOpen
      let mut kids := #[]
      for h : i in [0:as.size] do kids := kids.push (← buildType a owner side al as[i] (path.push i))
      modify fun S => { S with children := S.children.insert o kids, actlit := S.actlit.insert o al,
                               trigid := S.trigid.push o }
      return o

partial def build (a : Nat) (side : Side) (tid : Nat) (al : BLit) (t : Term) (path : Array Nat) :
    StateM Struct Obj := do
  match t with
  | .var n => return .slot a side n
  | .app s as =>
    if t.isGround then
      let o := Obj.ground t
      unless (← get).children.contains o do
        let mut kids := #[]
        for h : i in [0:as.size] do kids := kids.push (← build a side tid al as[i] (path.push i))
        modify fun S => { S with children := S.children.insert o kids, actlit := S.actlit.insert o .tt,
                                 groundApps := if kids.isEmpty then S.groundApps else S.groundApps.push o }
      return o
    else
      let o := Obj.rigid a side tid path (s, as.size) t.isOpen
      let mut kids := #[]
      for h : i in [0:as.size] do kids := kids.push (← build a side tid al as[i] (path.push i))
      modify fun S => { S with children := S.children.insert o kids, actlit := S.actlit.insert o al,
                               rigid := S.rigid.push o }
      return o

/-- Static label layout (SPEC §5.3; untyped, so no `open` bit yet). -/
structure Layout where
  N : Nat
  SB : Nat
  IB : Nat
  RB : Nat
  syms : Std.HashMap (Option (String × Nat)) Nat
  groundIds : Std.HashMap Term Nat
  /-- Width of the `open` field: 1 if some template has an open subterm, else 0 (the bit
  would be the constant 0 everywhere and is folded away; M1 forests keep their sizes). -/
  OB : Nat := 0
  W : Nat := SB + IB + RB + N + OB

def Layout.rank (L : Layout) (l : Array BLit) : Array BLit := l.extract (L.SB + L.IB) (L.SB + L.IB + L.RB)
def Layout.esc (L : Layout) (l : Array BLit) : Array BLit := l.extract (L.SB + L.IB + L.RB) (L.SB + L.IB + L.RB + L.N)
/-- The constant `open` field. -/
def Layout.openBits (L : Layout) (b : Bool) : Array BLit := Array.replicate L.OB (BLit.const b)

structure LabState where
  labels : Std.HashMap Obj (Array BLit) := {}
  allocs : Std.HashMap Obj Nat := {}

abbrev EncM := StateT LabState CnfM

/-- The label of an object, allocated on first use and cached (enc.py `lab`). Every branch
below must fall through to the cache insert; the allocation count is checked by a test. -/
def lab (L : Layout) (o : Obj) : EncM (Array BLit) := do
  if let some l := (← get).labels[o]? then return l
  modify fun st => { st with allocs := st.allocs.insert o (st.allocs.getD o 0 + 1) }
  let l ← match o with
    | .ground t =>
      pure (constBits L.syms[t.symKey]! L.SB ++ constBits L.groundIds[t]! L.IB ++
        constBits t.height L.RB ++ Array.replicate L.N BLit.ff ++ L.openBits t.isOpen)
    | .rigid _ _ _ _ sym opn | .trigid _ _ _ sym opn | .value _ _ _ sym opn =>
      pure (constBits L.syms[some sym]! L.SB ++ (← (newLits (L.IB + L.RB + L.N) : CnfM _)) ++ L.openBits opn)
    | .slot .. => pure ((← (newLits (L.W - L.OB) : CnfM _)) ++ L.openBits false)
  modify fun st => { st with labels := st.labels.insert o l }
  return l

end Encode

open Encode in
/-- Encode the forest with node bound `N` (SPEC §6.1 to 6.8; enc.py `encode`). -/
def encode (P : Forest) (N : Nat) (opts : EncodeOptions := {}) : Encoding := Id.run do
  let C := P.clauses.size
  let G := P.goals.size
  let A := P.maxPrems
  -- structural variables, allocated in the prototype's order
  let go : CnfM Vars := do
    let cl ← (List.range N).toArray.mapM fun _ => newLits C
    let gp ← (List.range N).toArray.mapM fun _ => newLits G
    let act ← newLits N
    let mut y := {}
    for a in [0:N] do
      for b in [a+1:N] do
        for k in [0:A] do y := y.insert (a, b, k) (← newLit)
    let mut anc := {}
    for g in [0:N] do
      for b in [g+1:N] do anc := anc.insert (g, b) (← newLit)
    let mut u := {}
    for b in [0:N] do
      for g in [0:b+1] do u := u.insert (b, g) (← newLit)
    return { N, A, act, cl, gp, y, anc, u }
  let (V, F0) := buildCNF go { countOnly := opts.countOnly }
  let act := V.act
  let cl := V.cl
  let gp := V.gp
  let y := fun a b k => V.y[(a, b, k)]!
  let anc := fun g b => V.anc[(g, b)]!
  let u := fun b g => V.u[(b, g)]!
  -- type templates (6.8) and kinds
  let varTypes : Std.HashMap String (Option Term) := P.varTypes.foldl (fun m (b, t) => m.insert b t) {}
  let groundTypes : Std.HashMap Term (Option Term) := P.groundTypes.foldl (fun m (g, t) => m.insert g t) {}
  let mut posTypes : Std.HashMap (Side × Nat × Array Nat) (Option Term) := {}
  for h : g in [0:G] do
    for (p, t) in P.goals[g]!.tgtTypes do posTypes := posTypes.insert (.goal, g, p) t
  for h : c in [0:C] do
    for (p, t) in P.clauses[c]!.headTypes do posTypes := posTypes.insert (.clause, c, p) t
  let varType := fun b => (varTypes.get? b).getD none
  let mut valTypes : Std.HashMap (Nat × Array Nat) (Option Term) := {}
  for h : c in [0:C] do
    for (p, t) in P.clauses[c]!.valueTypes do valTypes := valTypes.insert (c, p) t
  let values : Array (Nat × Term) := (Array.range C).filterMap fun c => (P.clauses[c]!.dataVal).map (c, ·)
  let isLevelVar := fun b => P.levelVars.contains b
  -- the typing clause can only be emitted for a pair whose types are not both closed (or
  -- for any pair when the static filter is off); without such a type it is never needed,
  -- and the type templates are left out of the tables (L1 keeps its pre-typing size)
  let someOpenType := P.varTypes.any (fun (_, t) => t.any (!·.isGround)) ||
    posTypes.toArray.any (fun (_, t) => t.any (!·.isGround)) ||
    valTypes.toArray.any (fun (_, t) => t.any (!·.isGround))
  let typingOn := opts.groundness && opts.typingClause && (someOpenType || !opts.staticTyping)
  -- the type templates that take part in the CNF: those of term variables and positions
  let allTypes : Array Term :=
    if !typingOn then #[] else
      (P.varTypes.filterMap (·.2)) ++ (posTypes.toArray.filterMap (·.2)) ++
      (valTypes.toArray.filterMap (·.2)) ++
      (P.groundTypes.filterMap fun (_, t) => t.filter (·.isGround))
  -- static tables: symbols, ground terms (atoms first, in the prototype's order, then
  -- ground terms that occur only in type templates: those are never candidates), widths
  let mut syms : Std.HashMap (Option (String × Nat)) Nat := ({} : Std.HashMap _ _).insert none 0
  let mut groundIds : Std.HashMap Term Nat := {}
  let mut groundList : Array Term := #[]
  let mut nrig := 0
  let mut maxh := 0
  let mut stack : Array Term := #[]
  let atoms := P.goals.map (·.tgt) ++ P.clauses.map (·.head)
  let nv := values.size
  for h : ti in [0:atoms.size + nv + allTypes.size] do
    -- atoms and data values count as "atoms" here: their ground subterms are candidates
    let isAtom := ti < atoms.size + nv
    let t := if ti < atoms.size then atoms[ti]! else if isAtom then values[ti - atoms.size]!.2
      else allTypes[ti - atoms.size - nv]!
    if ti < atoms.size then
      maxh := max maxh t.height
      -- pre-order scan of each argument, as enc.py `scan`
      for x in t.args.reverse do stack := stack.push x
    else if isAtom then
      -- a value is a per-node object; its subterms are scanned like atom arguments
      if !syms.contains t.symKey then syms := syms.insert t.symKey syms.size
      for x in t.args.reverse do stack := stack.push x
    else stack := stack.push t
    while !stack.isEmpty do
      let x := stack.back!
      stack := stack.pop
      if x.isVar then continue
      if !syms.contains x.symKey then syms := syms.insert x.symKey syms.size
      if x.isGround then
        if !groundIds.contains x then
          groundIds := groundIds.insert x groundIds.size
          if isAtom then groundList := groundList.push x
      else if isAtom then nrig := nrig + 1
      for a in x.args.reverse do stack := stack.push a
  let eigs := P.eigs
  -- per-node object graph: atoms, then (with the typing clause) the type templates of
  -- clause variables, eigenvariables and template positions that are not closed
  let nonGround := fun (t? : Option Term) => match t? with
    | some t => if t.isGround then none else some t
    | none => none
  let buildAll : StateM Struct Unit := do
    for a in [0:N] do
      for h : g in [0:G] do
        let args := P.goals[g]!.tgt.args
        let mut os := #[]
        for h : i in [0:args.size] do os := os.push (← build a .goal g gp[a]![g]! args[i] #[i])
        modify fun S => { S with root := S.root.insert (a, .goal, g) os }
      for h : c in [0:C] do
        let args := P.clauses[c]!.head.args
        let mut os := #[]
        for h : i in [0:args.size] do os := os.push (← build a .clause c cl[a]![c]! args[i] #[i])
        modify fun S => { S with root := S.root.insert (a, .clause, c) os }
      for (c, v) in values do
        let o ← buildValue a c cl[a]![c]! v #[] true
        modify fun S => { S with valueRoot := S.valueRoot.insert (a, c) o }
    for (t, _) in P.groundTypes do discard <| buildGround t
    if typingOn then
      for t in allTypes do
        if t.isGround then discard <| buildGround t
      for a in [0:N] do
        let addTy (owner : TyOwner) (side : Side) (al : BLit) (T : Term) : StateM Struct Unit := do
          let o ← buildType a owner side al T #[]
          modify fun S => { S with tyRoot := S.tyRoot.insert (a, owner) o }
        for h : c in [0:C] do
          for b in P.clauses[c]!.vars do
            if let some T := nonGround (varType b) then addTy (.var .clause b) .clause cl[a]![c]! T
          for (p, t) in P.clauses[c]!.headTypes do
            if let some T := nonGround t then addTy (.pos .clause c p) .clause cl[a]![c]! T
          for (p, t) in P.clauses[c]!.valueTypes do
            if let some T := nonGround t then addTy (.val c p) .clause cl[a]![c]! T
        for h : g in [0:G] do
          for b in P.goals[g]!.eig do
            if let some T := nonGround (varType b) then addTy (.var .goal b) .goal gp[a]![g]! T
          for (p, t) in P.goals[g]!.tgtTypes do
            if let some T := nonGround t then addTy (.pos .goal g p) .goal gp[a]![g]! T
  let ((), S) := buildAll.run {} |>.run
  let SB := max 1 (clog2 (syms.size + 1))
  -- idx: one code per rigid object (N·T in the prototype), ground term and eigenvariable
  let K := S.rigid.size + S.trigid.size + groundIds.size + N * eigs.size + 1
  let IB := max 1 (clog2 (K + 1))
  -- rank width (NOTES.md, milestones 2 and 4): every active rigid object of a node is a
  -- rigid position of its target or head, or of one of their type templates, so a chain
  -- of rigid classes above the ground terms has at most N·(rt + rh) members.
  let rc := fun (t? : Option Term) => match t? with | some t => t.rigidCount | none => 0
  let tyG := fun (g : GoalPos) => if !typingOn then 0 else
    g.eig.foldl (fun n b => n + rc (varType b)) 0 + g.tgtTypes.foldl (fun n (_, t) => n + rc t) 0
  let tyC := fun (c : Clause) => (if !typingOn then 0 else
    c.vars.foldl (fun n b => n + rc (varType b)) 0 + c.headTypes.foldl (fun n (_, t) => n + rc t) 0 +
    c.valueTypes.foldl (fun n (_, t) => n + rc t) 0) +
    -- a data value: its non-ground positions, and the value itself even if ground
    (match c.dataVal with | some v => v.rigidCount + (if v.isGround then 1 else 0) | none => 0)
  let rt := P.goals.foldl (fun m g => max m (g.tgt.args.foldl (· + ·.rigidCount) 0 + tyG g)) 0
  let rh := P.clauses.foldl (fun m c => max m (c.head.args.foldl (· + ·.rigidCount) 0 + tyC c)) 0
  let gh := groundIds.fold (fun m t _ => max m t.height) 0
  let RB := if opts.protoRank then max 1 (clog2 (N * (maxh + 1) + 2))
    else max 1 (clog2 (N * (rt + rh) + gh + 2))
  let anyOpen := (atoms ++ values.map (·.2) ++ allTypes).any (·.hasBVar)
  let L : Layout := { N, SB, IB, RB, syms, groundIds, OB := if anyOpen && opts.openBit then 1 else 0 }
  let W := L.W
  let actlit := fun o => S.actlit[o]!
  let kids := fun o => S.children[o]!
  let slot := fun a side n => Obj.slot a side n
  let neg := BLit.neg
  -- the type of a candidate or variable as (template, object at its node), if known
  let tyObj := fun (a : Nat) (owner : TyOwner) (side : Side) (t? : Option Term) => match t? with
    | none => none
    | some T => match T with
      | .var n => some (T, Obj.slot a side n)
      | _ => if T.isGround then some (T, Obj.ground T) else (S.tyRoot.get? (a, owner)).map (T, ·)
  let candTy : Obj → Option (Term × Obj)
    | .rigid β side tid path _ _ => tyObj β (.pos side tid path) side ((posTypes.get? (side, tid, path)).getD none)
    | .ground t => match (groundTypes.get? t).getD none with
      | some T => if T.isGround then some (T, Obj.ground T) else none
      | none => none
    | .slot β side b => tyObj β (.var side b) side (varType b)
    | .value β c path _ _ => tyObj β (.val c path) .clause ((valTypes.get? (c, path)).getD none)
    | .trigid .. => none
  let (belowG, belowC) := if opts.framePruning then P.varsBelow else (#[], #[])
  -- the static template of an object (pair pruning, 6.10)
  let subAt := fun (t : Term) (path : Array Nat) => path.foldlM (fun (t : Term) i => t.args[i]?) t
  let ownerType : TyOwner → Option Term
    | .var _ b => varType b
    | .pos side tid p => (posTypes.get? (side, tid, p)).getD none
    | .val c p => (valTypes.get? (c, p)).getD none
  let tmplOf : Obj → Option Term
    | .ground t => some t
    | .rigid _ side tid path _ _ =>
      subAt (if side == .goal then P.goals[tid]!.tgt else P.clauses[tid]!.head) path
    | .trigid _ owner path _ _ => (ownerType owner).bind (subAt · path)
    | .value _ c path _ _ => (P.clauses[c]!.dataVal).bind (subAt · path)
    | .slot .. => none
  let families : EncM (Nat × Nat × Std.HashMap (Nat × Nat × String) (Array (Obj × BLit × Bool))) := do
    let lab := Encode.lab L
    -- 6.1 node assignment
    setFamily "1 node assignment"
    for a in [0:N] do
      amo cl[a]! opts.ladderAmo; addClause (#[neg act[a]!] ++ cl[a]!)
      for c in [0:C] do addClause #[neg cl[a]![c]!, act[a]!]
      amo gp[a]! opts.ladderAmo; addClause (#[neg act[a]!] ++ gp[a]!)
      for g in [0:G] do addClause #[neg gp[a]![g]!, act[a]!]
      if a > 0 then addClause #[neg act[a]!, act[a-1]!]
    addClause #[act[0]!]; addClause #[gp[0]![0]!]
    -- 6.2 tree shape
    setFamily "2 tree shape"
    for b in [1:N] do
      let mut ps := #[]
      for a in [0:b] do
        for k in [0:A] do ps := ps.push (y a b k)
      addClause (#[neg act[b]!] ++ ps); amo ps opts.ladderAmo
      for a in [0:b] do
        for k in [0:A] do
          addClause #[neg (y a b k), act[b]!]; addClause #[neg (y a b k), act[a]!]
    for a in [0:N] do
      for k in [0:A] do
        let ys := (Array.range' (a+1) (N-(a+1))).map fun b => y a b k
        amo ys opts.ladderAmo
        for c in [0:C] do
          let prems := P.clauses[c]!.prems
          let dps := P.clauses[c]!.dataPos
          if k < prems.size then
            addClause (#[neg cl[a]![c]!] ++ ys)
            for b in [a+1:N] do addClause #[neg cl[a]![c]!, neg (y a b k), gp[b]![prems[k]!]!]
          else if k < prems.size + dps.size then
            -- a data position (6.9): at most one child, none required
            for b in [a+1:N] do
              addClause #[neg cl[a]![c]!, neg (y a b k), gp[b]![dps[k - prems.size]!.2]!]
          else
            for b in [a+1:N] do addClause #[neg cl[a]![c]!, neg (y a b k)]
    -- 6.10 symmetry breaking: breadth-first numbering. If y(α, β, k) and y(α', β+1, k')
    -- then (α, k) precedes (α', k') lexicographically.
    if opts.symmetry then
      setFamily "10 symmetry breaking"
      for b in [1:N-1] do
        for a in [0:b] do
          for k in [0:A] do
            for a' in [0:a+1] do
              for k' in [0:A] do
                if a' < a || (a' == a && k' < k) then
                  addClause #[neg (y a b k), neg (y a' (b+1) k')]
    -- 6.3 context
    setFamily "3 context (local hypotheses, ancestors)"
    for b in [0:N] do
      amo ((Array.range (b+1)).map fun g => u b g) opts.ladderAmo
      for c in [0:C] do
        match P.clauses[c]!.localOf with
        | none => for g in [0:b+1] do addClause #[neg cl[b]![c]!, neg (u b g)]
        | some lg =>
          addClause (#[neg cl[b]![c]!] ++ (Array.range (b+1)).map fun g => u b g)
          for g in [0:b+1] do addClause #[neg (u b g), neg cl[b]![c]!, gp[g]![lg]!]
          -- a built-in rule applies only at the node that owns its goal position
          if P.clauses[c]!.builtin then addClause #[neg cl[b]![c]!, u b b]
      for g in [0:b] do addClause #[neg (u b g), anc g b]
    for g in [0:N] do
      for b in [g+1:N] do
        addClause #[neg (anc g b), act[b]!]
        for a in [0:b] do
          for k in [0:A] do
            if a < g then addClause #[neg (anc g b), neg (y a b k)]
            else if a > g then addClause #[neg (anc g b), neg (y a b k), anc g a]
    -- 6.4 matching
    setFamily "4 matching"
    for a in [0:N] do
      for g in [0:G] do
        for c in [0:C] do
          let dataGoal := P.goals[g]!.dataVar
          let dataVal := P.clauses[c]!.dataVal
          -- 6.9 static filter: proof clauses only at proposition positions, data clauses only
          -- at data positions
          if opts.dataFilter && dataGoal.isSome != dataVal.isSome then
            addClause #[neg gp[a]![g]!, neg cl[a]![c]!]
          else if P.goals[g]!.tgt.symKey != P.clauses[c]!.head.symKey then
            addClause #[neg gp[a]![g]!, neg cl[a]![c]!]
          else
            let r1 := S.root[(a, Side.goal, g)]!
            let r2 := S.root[(a, Side.clause, c)]!
            for i in [0:r1.size] do
              eqUnder #[gp[a]![g]!, cl[a]![c]!] (← lab r1[i]!) (← lab r2[i]!)
            -- 6.9: the built variable equals the value of the data clause at this node
            if let (some b, some _) := (dataGoal, dataVal) then
              eqUnder #[gp[a]![g]!, cl[a]![c]!] (← lab (slot a .goal b)) (← lab S.valueRoot[(a, c)]!)
    -- 6.5 decomposition
    setFamily "5 decomposition"
    let mut keys : Array (String × Nat) := #[]
    let mut bysym : Std.HashMap (String × Nat) (Array Obj) := {}
    let symOf : Obj → String × Nat
      | .rigid _ _ _ _ s _ | .trigid _ _ _ s _ | .value _ _ _ s _ => s
      | .ground t => t.symKey.get!
      | .slot .. => ("", 0)
    for o in S.rigid ++ S.trigid ++ S.groundApps do
      let s := symOf o
      unless bysym.contains s do keys := keys.push s
      bysym := bysym.insert s ((bysym.getD s #[]).push o)
    let mut npairs := 0
    for s in keys do
      let os := bysym[s]!
      for i in [0:os.size] do
        for j in [i+1:os.size] do
          let o1 := os[i]!
          let o2 := os[j]!
          if (o1 matches .ground _) && (o2 matches .ground _) then continue
          let l1 ← lab o1
          let l2 ← lab o2
          -- 6.10 pair pruning: templates that do not unify (variables renamed apart) never
          -- have equal values, so only require their labels to differ, in the idx field
          if opts.pairPruning then
            if let (some t1, some t2) := (tmplOf o1, tmplOf o2) then
              if !t1.unifiableApart t2 then
                let mut ds := #[]
                let mut differ := false
                for q in [L.SB:L.SB + L.IB] do
                  match l1[q]!, l2[q]! with
                  | .const x, .const z => if x != z then differ := true
                  | .const x, z => ds := ds.push (if x then neg z else z)
                  | x, .const z => ds := ds.push (if z then neg x else x)
                  | x, z =>
                    let d ← (newLit : CnfM _)
                    addClause #[neg d, x, z]; addClause #[neg d, neg x, neg z]; ds := ds.push d
                unless differ do addClause (#[neg (actlit o1), neg (actlit o2)] ++ ds)
                continue
          let mut ds := #[]
          let mut ok := true
          for q in [0:l1.size] do
            match l1[q]!, l2[q]! with
            | .const x, .const z => if x != z then ok := false; break
            | .const x, z => ds := ds.push (if x then neg z else z)
            | x, .const z => ds := ds.push (if z then neg x else x)
            | x, z =>
              let d ← (newLit : CnfM _)
              addClause #[neg d, x, z]; addClause #[neg d, neg x, neg z]; ds := ds.push d
          if !ok then continue
          npairs := npairs + 1
          let m ← (newLit : CnfM _)
          addClause (#[neg (actlit o1), neg (actlit o2)] ++ ds ++ #[m])
          let k1 := kids o1
          let k2 := kids o2
          for q in [0:k1.size] do eqUnder #[m] (← lab k1[q]!) (← lab k2[q]!)
    -- 6.6 links
    setFamily "6 links (environment copies)"
    for a in [0:N] do
      for b in [a+1:N] do
        for c in [0:C] do
          -- every child: premises and data positions (a data child must see the variable
          -- it builds, 6.9)
          let cc := P.clauses[c]!
          for k in [0:cc.prems.size + cc.dataPos.size] do
            let child := if k < cc.prems.size then cc.prems[k]! else cc.dataPos[k - cc.prems.size]!.2
            -- 6.10 frame pruning: only the variables that occur below the child
            for v in P.clauseFrame c do
              if opts.framePruning && !(belowG[child]!.contains v) then continue
              eqUnder #[cl[a]![c]!, y a b k] (← lab (slot b .goal v)) (← lab (slot a .clause v))
    for b in [0:N] do
      for g in [0:b+1] do
        for c in [0:C] do
          if P.clauses[c]!.localOf.isSome then
            for v in P.clauses[c]!.env do
              -- 6.10 frame pruning: only the variables that occur in the clause
              if opts.framePruning && !(belowC[c]!.contains v) then continue
              eqUnder #[u b g, cl[b]![c]!] (← lab (slot b .clause v)) (← lab (slot g .goal v))
    -- 6.7 eigenvariables, occurs check, scope
    setFamily "7 eigenvariables, occurs check, scope"
    for a in [0:N] do
      for h : i in [0:eigs.size] do
        let (g, b) := eigs[i]
        let code := 1 + a * eigs.size + i
        let cst := constBits 0 SB ++ constBits code IB ++ constBits 0 RB ++
          (Array.range N).map (fun x => BLit.const (x == a)) ++ L.openBits false
        eqUnder #[gp[a]![g]!] (← lab (slot a .goal b)) cst
    for o in S.rigid ++ S.trigid do
      let al := actlit o
      let lo ← lab o
      for ch in kids o do
        let lc ← lab ch
        if opts.occurs then ltUnder #[al] (L.rank lc) (L.rank lo)
        for g in [0:N] do addClause #[neg al, neg (L.esc lc)[g]!, (L.esc lo)[g]!]
    if opts.scope then
      for a in [0:N] do
        for c in [0:C] do
          for b in P.clauses[c]!.vars do
            let E := L.esc (← lab (slot a .clause b))
            for g in [0:N] do
              if g > a then addClause #[neg cl[a]![c]!, neg E[g]!]
              else if g < a then addClause #[neg cl[a]![c]!, neg E[g]!, anc g a]
    -- 6.8 groundness and typing
    setFamily "8 groundness"
    let mut svMap : Std.HashMap (Nat × Nat × String) (Array (Obj × BLit × Bool)) := {}
    let mut ntyping := 0
    if opts.groundness then
      -- candidates (SPEC §6.8): non-open rigid objects of any node, ground objects, and
      -- eigenvariable goal slots, split by kind; type-template objects are never candidates
      let isLevelObj : Obj → Bool
        | .rigid _ _ _ _ (s, _) _ => s.startsWith Term.levelPrefix
        | .ground t => t.isLevel
        | _ => false
      let mut termCands : Array (Obj × BLit) := #[]
      let mut levelCands : Array (Obj × BLit) := #[]
      for o in S.rigid do
        if o matches .rigid _ _ _ _ _ true || o matches .value _ _ _ _ true then continue
        if isLevelObj o then levelCands := levelCands.push (o, actlit o)
        else termCands := termCands.push (o, actlit o)
      for t in groundList do
        if t.isLevel then levelCands := levelCands.push (.ground t, BLit.tt)
        else if t.isTermKind then termCands := termCands.push (.ground t, BLit.tt)
      for a in [0:N] do
        for (g, b) in eigs do termCands := termCands.push (slot a .goal b, gp[a]![g]!)
      for a in [0:N] do
        for c in [0:C] do
          for b in P.clauses[c]!.vars do
            let lv := isLevelVar b
            let tb := if lv then none else tyObj a (.var .clause b) .clause (varType b)
            let mut svs := #[]
            let mut kept := #[]
            for (o, al) in (if lv then levelCands else termCands) do
              let to := if lv then none else candTy o
              -- static decision when both types are closed
              let decided := match tb, to with
                | some (t1, _), some (t2, _) => t1.isGround && t2.isGround && opts.staticTyping
                | _, _ => false
              if decided then
                if let (some (t1, _), some (t2, _)) := (tb, to) then
                  if t1 != t2 then continue
              -- 6.10 candidate pruning: a candidate whose type cannot unify with the
              -- variable's type (variables renamed apart) can never be well typed
              if opts.candidatePruning && !decided then
                if let (some (t1, _), some (t2, _)) := (tb, to) then
                  if !t1.unifiableApart t2 then continue
              let sv ← (newLit : CnfM _)
              addClause #[neg sv, al]
              eqUnder #[sv] (← lab (slot a .clause b)) (← lab o)
              -- typing clause: sv ⇒ L(type of b at α) = L(type of o)
              let typed := lv || (tb.isSome && to.isSome)
              if typingOn && !decided then
                if let (some (_, ob), some (_, oo)) := (tb, to) then
                  eqUnder #[sv] (← lab ob) (← lab oo)
                  ntyping := ntyping + 1
              svs := svs.push sv
              kept := kept.push (o, sv, typed)
            addClause (#[neg cl[a]![c]!] ++ svs)
            svMap := svMap.insert (a, c, b) kept
    return (npairs, ntyping, svMap)
  let (((pairs, ntyping, svMap), ls), F) := (families.run {}).run F0
  return { cnf := F, vars := V, sv := svMap, labels := ls.labels, allocs := ls.allocs,
           info := { W, SB, IB, RB, pairs, rigid := S.rigid.size, ground := groundList.size,
                     typeRigid := S.trigid.size, typing := ntyping } }

/-! ## Reading the proof skeleton from a model (SPEC §8 step 1) -/

structure SkelNode where
  node : Nat
  goal : Nat
  clause : Nat
  /-- The child node proving each premise, in premise order. -/
  children : Array Nat
  /-- For a local clause, the node that introduced it. -/
  intro : Option Nat
  /-- For each data position of the clause, the child node that builds it, if any. -/
  dataChildren : Array (Option Nat) := #[]
  deriving Repr, Inhabited

/-- Read the tree from the structural variables. Fails if the model does not describe a
tree rooted at node 0; that would be an encoder bug. -/
def readSkeleton (P : Forest) (V : Vars) (m : Array Bool) : Except String (Array SkelNode) := do
  let val := BLit.eval m
  let mut out := #[]
  for a in [0:V.N] do
    unless val V.act[a]! do break
    let some c := (List.range P.clauses.size).find? (fun c => val V.cl[a]![c]!)
      | throw s!"active node {a} applies no clause"
    let some g := (List.range P.goals.size).find? (fun g => val V.gp[a]![g]!)
      | throw s!"active node {a} solves no goal position"
    let mut kids := #[]
    for k in [0:P.clauses[c]!.prems.size] do
      let some b := (List.range' (a+1) (V.N-(a+1))).find? (fun b => val V.y[(a, b, k)]!)
        | throw s!"node {a} has no child for premise {k}"
      kids := kids.push b
    let np := P.clauses[c]!.prems.size
    let mut dkids := #[]
    for j in [0:P.clauses[c]!.dataPos.size] do
      dkids := dkids.push ((List.range' (a+1) (V.N-(a+1))).find? (fun b => val V.y[(a, b, np + j)]!))
    let intro := (List.range (a+1)).find? (fun γ => val V.u[(a, γ)]!)
    out := out.push { node := a, goal := g, clause := c, children := kids, intro, dataChildren := dkids }
  return out

/-- Render a skeleton like the prototype's `term`: `fun eigs hyps => name(children)`. -/
partial def renderSkeleton (P : Forest) (sk : Array SkelNode) (a : Nat) : String :=
  let n := sk[a]!
  let c := P.clauses[n.clause]!
  let g := P.goals[n.goal]!
  let dkids := (c.dataPos.zip n.dataChildren).filterMap fun ((b, _), β?) =>
    β?.map fun β => (b.splitOn "#").head! ++ ":=" ++ renderSkeleton P sk β
  let kids := n.children.map (renderSkeleton P sk) ++ dkids
  let s := c.name ++ (if kids.isEmpty then "" else "(" ++ ", ".intercalate kids.toList ++ ")")
  let bs := g.eig ++ g.hyps.map (P.clauses[·]!.name)
  (if bs.isEmpty then "" else "fun " ++ " ".intercalate bs.toList ++ " => ") ++ s

end SolveBySat
