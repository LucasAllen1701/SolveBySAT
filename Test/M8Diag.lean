/-
Milestone 8b (M8_PLAN.md §4.3): measurements of the CNF's structure, M1 to M5. Read-only: nothing
in `SolveBySat/` changes, and the CNF the tactic builds is never touched.

The analysis takes a forest, N, the options and the `Encoding` that `encode` returned, and
recounts the groundness (6.8) and decomposition (6.5) clauses one candidate or one pair at a time,
attributing each to the classes of §4.3. To count exactly, it
- rebuilds the per-node object graph with the encoder's own builders (`Encode.build`,
  `buildValue`, `buildGround`, `buildType`), in the encoder's order;
- copies the encoder's candidate lists, typing decisions and pair loop (`encode`, families 6.5 and
  6.8), and replays each candidate's or pair's clauses with the encoder's own gadgets (`addClause`,
  `eqUnder`) in a scratch counting CNF, with the encoding's real labels (`Encoding.labels`) and
  `sv` literals (`Encoding.sv`), so constant folding is identical.
Each recount is checked against the encoder: the replayed totals must equal the encoding's own
family counts, and the kept candidates must equal `Encoding.sv`. A mismatch is reported in the
output (`check_*` fields) and means the copy has drifted from `encode`.
-/
import SolveBySat
import Lean.Data.Json

open Lean (Json toJson)
open SolveBySat SolveBySat.Encode SolveBySat.CNF

namespace M8Diag

/-! ## The encoder's static tables, as in `encode` -/

structure Tables where
  P : Forest
  N : Nat
  opts : EncodeOptions
  varTypes : Std.HashMap String (Option Term)
  groundTypes : Std.HashMap Term (Option Term)
  posTypes : Std.HashMap (Side × Nat × Array Nat) (Option Term)
  valTypes : Std.HashMap (Nat × Array Nat) (Option Term)
  values : Array (Nat × Term)
  typingOn : Bool
  allTypes : Array Term
  groundList : Array Term
  S : Struct
  V : Vars

def tables (P : Forest) (N : Nat) (opts : EncodeOptions) (V : Vars) : Tables := Id.run do
  let C := P.clauses.size
  let G := P.goals.size
  let varTypes : Std.HashMap String (Option Term) := P.varTypes.foldl (fun m (b, t) => m.insert b t) {}
  let groundTypes : Std.HashMap Term (Option Term) := P.groundTypes.foldl (fun m (g, t) => m.insert g t) {}
  let mut posTypes : Std.HashMap (Side × Nat × Array Nat) (Option Term) := {}
  for g in [0:G] do
    for (p, t) in P.goals[g]!.tgtTypes do posTypes := posTypes.insert (.goal, g, p) t
  for c in [0:C] do
    for (p, t) in P.clauses[c]!.headTypes do posTypes := posTypes.insert (.clause, c, p) t
  let varType := fun b => (varTypes.get? b).getD none
  let mut valTypes : Std.HashMap (Nat × Array Nat) (Option Term) := {}
  for c in [0:C] do
    for (p, t) in P.clauses[c]!.valueTypes do valTypes := valTypes.insert (c, p) t
  let values : Array (Nat × Term) := (Array.range C).filterMap fun c => (P.clauses[c]!.dataVal).map (c, ·)
  let someOpenType := P.varTypes.any (fun (_, t) => t.any (!·.isGround)) ||
    posTypes.toArray.any (fun (_, t) => t.any (!·.isGround)) ||
    valTypes.toArray.any (fun (_, t) => t.any (!·.isGround))
  let typingOn := opts.groundness && opts.typingClause && (someOpenType || !opts.staticTyping)
  let allTypes : Array Term :=
    if !typingOn then #[] else
      (P.varTypes.filterMap (·.2)) ++ (posTypes.toArray.filterMap (·.2)) ++
      (valTypes.toArray.filterMap (·.2)) ++
      (P.groundTypes.filterMap fun (_, t) => t.filter (·.isGround))
  -- ground terms that occur in atoms or values (the encoder's scan; only these are candidates)
  let mut groundIds : Std.HashSet Term := {}
  let mut groundList : Array Term := #[]
  let mut stack : Array Term := #[]
  let atoms := P.goals.map (·.tgt) ++ P.clauses.map (·.head)
  let nv := values.size
  for ti in [0:atoms.size + nv + allTypes.size] do
    let isAtom := ti < atoms.size + nv
    let t := if ti < atoms.size then atoms[ti]! else if isAtom then values[ti - atoms.size]!.2
      else allTypes[ti - atoms.size - nv]!
    if isAtom then
      for x in t.args.reverse do stack := stack.push x
    else stack := stack.push t
    while !stack.isEmpty do
      let x := stack.back!
      stack := stack.pop
      if x.isVar then continue
      if x.isGround then
        if !groundIds.contains x then
          groundIds := groundIds.insert x
          if isAtom then groundList := groundList.push x
      for a in x.args.reverse do stack := stack.push a
  let gp := V.gp
  let cl := V.cl
  let nonGround := fun (t? : Option Term) => match t? with
    | some t => if t.isGround then none else some t
    | none => none
  -- 8c-1, R1: an owner whose literal the encoder made the constant false gets only the shared
  -- ground objects (as `encode`)
  let dead := fun (l : BLit) => l == BLit.ff
  let buildAll : StateM Struct Unit := do
    for a in [0:N] do
      for g in [0:G] do
        let args := P.goals[g]!.tgt.args
        if dead gp[a]![g]! then
          for x in args do buildGroundParts x
          continue
        let mut os := #[]
        for i in [0:args.size] do os := os.push (← build a .goal g gp[a]![g]! args[i]! #[i])
        modify fun S => { S with root := S.root.insert (a, .goal, g) os }
      for c in [0:C] do
        let args := P.clauses[c]!.head.args
        if dead cl[a]![c]! then
          for x in args do buildGroundParts x
          continue
        let mut os := #[]
        for i in [0:args.size] do os := os.push (← build a .clause c cl[a]![c]! args[i]! #[i])
        modify fun S => { S with root := S.root.insert (a, .clause, c) os }
      for (c, v) in values do
        if dead cl[a]![c]! then
          for x in v.args do buildGroundParts x
          continue
        let o ← buildValue a c cl[a]![c]! v #[] true
        modify fun S => { S with valueRoot := S.valueRoot.insert (a, c) o }
    for (t, _) in P.groundTypes do discard <| buildGround t
    if typingOn then
      for t in allTypes do
        if t.isGround then discard <| buildGround t
      for a in [0:N] do
        let addTy (owner : TyOwner) (side : Side) (al : BLit) (T : Term) : StateM Struct Unit := do
          if dead al then buildGroundParts T; return
          let o ← buildType a owner side al T #[]
          modify fun S => { S with tyRoot := S.tyRoot.insert (a, owner) o }
        for c in [0:C] do
          for b in P.clauses[c]!.vars do
            if let some T := nonGround (varType b) then addTy (.var .clause b) .clause cl[a]![c]! T
          for (p, t) in P.clauses[c]!.headTypes do
            if let some T := nonGround t then addTy (.pos .clause c p) .clause cl[a]![c]! T
          for (p, t) in P.clauses[c]!.valueTypes do
            if let some T := nonGround t then addTy (.val c p) .clause cl[a]![c]! T
        for g in [0:G] do
          for b in P.goals[g]!.eig do
            if let some T := nonGround (varType b) then addTy (.var .goal b) .goal gp[a]![g]! T
          for (p, t) in P.goals[g]!.tgtTypes do
            if let some T := nonGround t then addTy (.pos .goal g p) .goal gp[a]![g]! T
  let ((), S) := buildAll.run {} |>.run
  return { P, N, opts, varTypes, groundTypes, posTypes, valTypes, values, typingOn, allTypes, groundList, S, V }

namespace Tables
def varType (T : Tables) (b : String) : Option Term := (T.varTypes.get? b).getD none

def tyObj (T : Tables) (a : Nat) (owner : TyOwner) (side : Side) (t? : Option Term) : Option (Term × Obj) :=
  match t? with
  | none => none
  | some Ty => match Ty with
    | .var n => some (Ty, Obj.slot a side n)
    | _ => if Ty.isGround then some (Ty, Obj.ground Ty) else (T.S.tyRoot.get? (a, owner)).map (Ty, ·)

def candTy (T : Tables) : Obj → Option (Term × Obj)
  | .rigid β side tid path _ _ => T.tyObj β (.pos side tid path) side ((T.posTypes.get? (side, tid, path)).getD none)
  | .ground t => match (T.groundTypes.get? t).getD none with
    | some Ty => if Ty.isGround then some (Ty, Obj.ground Ty) else none
    | none => none
  | .slot β side b => T.tyObj β (.var side b) side (T.varType b)
  | .value β c path _ _ => T.tyObj β (.val c path) .clause ((T.valTypes.get? (c, path)).getD none)
  | .trigid .. => none

def subAt (t : Term) (path : Array Nat) : Option Term := path.foldlM (fun (t : Term) i => t.args[i]?) t

def ownerType (T : Tables) : TyOwner → Option Term
  | .var _ b => T.varType b
  | .pos side tid p => (T.posTypes.get? (side, tid, p)).getD none
  | .val c p => (T.valTypes.get? (c, p)).getD none

def tmplOf (T : Tables) : Obj → Option Term
  | .ground t => some t
  | .rigid _ side tid path _ _ =>
    subAt (if side == .goal then T.P.goals[tid]!.tgt else T.P.clauses[tid]!.head) path
  | .trigid _ owner path _ _ => (T.ownerType owner).bind (subAt · path)
  | .value _ c path _ _ => (T.P.clauses[c]!.dataVal).bind (subAt · path)
  | .slot .. => none

/-- The candidate lists of 6.8 (terms, levels), in the encoder's order. -/
def candidates (T : Tables) : Array (Obj × BLit) × Array (Obj × BLit) := Id.run do
  let isLevelObj : Obj → Bool
    | .rigid _ _ _ _ (s, _) _ => s.startsWith Term.levelPrefix
    | .ground t => t.isLevel
    | _ => false
  let mut termCands : Array (Obj × BLit) := #[]
  let mut levelCands : Array (Obj × BLit) := #[]
  for o in T.S.rigid do
    if o matches .rigid _ _ _ _ _ true || o matches .value _ _ _ _ true then continue
    if isLevelObj o then levelCands := levelCands.push (o, T.S.actlit[o]!)
    else termCands := termCands.push (o, T.S.actlit[o]!)
  for t in T.groundList do
    if t.isLevel then levelCands := levelCands.push (.ground t, BLit.tt)
    else if t.isTermKind then termCands := termCands.push (.ground t, BLit.tt)
  for a in [0:T.N] do
    for (g, b) in T.P.eigs do
      unless T.V.gp[a]![g]! == BLit.ff do termCands := termCands.push (Obj.slot a .goal b, T.V.gp[a]![g]!)
  return (termCands, levelCands)
end Tables

/-- Run a gadget in a scratch counting CNF and return the clauses and variables it adds. -/
def replay (m : CnfM Unit) : Nat × Nat :=
  let ((), F) := buildCNF m { countOnly := true, nVars := 1000000000 }
  (F.nClauses, F.nVars - 1000000000)

/-! ## Object classes -/

def nodeOf : Obj → Option Nat
  | .ground _ => none
  | .rigid a .. | .slot a .. | .trigid a .. | .value a .. => some a

def kindOf : Obj → String
  | .ground _ => "ground object"
  | .slot .. => "eigenvariable slot"
  | .rigid .. => "rigid position"
  | .value .. => "value object"
  | .trigid .. => "type-template object"

/-- A static key: the template position of an object with all node copies identified. -/
inductive Key where
  | var (b : String)
  | pos (side : Side) (tid : Nat) (path : Array Nat)
  | ty (owner : TyOwner) (path : Array Nat)
  | val (c : Nat) (path : Array Nat)
  | ground (t : Term)
  deriving BEq, Hashable, Inhabited

def keyOf : Obj → Key
  | .ground t => .ground t
  | .rigid _ side tid path _ _ => .pos side tid path
  | .slot _ _ b => .var b
  | .trigid _ owner path _ _ => .ty owner path
  | .value _ c path _ _ => .val c path

/-- Union-find over keys. -/
structure UF where
  parent : Std.HashMap Key Key := {}

partial def UF.find (u : UF) (k : Key) : Key :=
  match u.parent.get? k with
  | some p => if p == k then k else u.find p
  | none => k

def UF.union (u : UF) (a b : Key) : UF × Bool :=
  let ra := u.find a
  let rb := u.find b
  if ra == rb then (u, false) else ({ parent := u.parent.insert ra rb }, true)

/-! ## The analysis -/

structure Counter where
  m : Std.HashMap String (Nat × Nat) := {}   -- label ↦ (clauses, variables)

def Counter.add (c : Counter) (k : String) (cl vs : Nat) : Counter :=
  let (a, b) := c.m.getD k (0, 0)
  { m := c.m.insert k (a + cl, b + vs) }

def Counter.json (c : Counter) : Json :=
  Json.mkObj ((c.m.toArray.qsort (·.1 < ·.1)).toList.map fun (k, (a, b)) =>
    (k, Json.mkObj [("clauses", toJson a), ("vars", toJson b)]))

/-- M1: the label fields. -/
def m1 (E : Encoding) (N : Nat) : Json :=
  let info := E.info
  Json.mkObj [("sym", toJson info.SB), ("idx", toJson info.IB), ("rank", toJson info.RB), ("esc", toJson N),
              ("open", toJson (info.W - info.SB - info.IB - info.RB - N)), ("W", toJson info.W),
              ("rigid_objects", toJson info.rigid), ("type_rigid_objects", toJson info.typeRigid),
              ("ground_candidates", toJson info.ground)]

/-- The static may-equal components (M3): keys joined by matching, by links (one key per variable
name), by groundness candidates and typing clauses, and closed under decomposition (two keys with
the same symbol and arity in one component join their children). -/
def components (T : Tables) (E : Encoding) : UF := Id.run do
  let P := T.P
  let mut u : UF := {}
  let keyAt (t : Term) (k : Key) : Key := match t with
    | .var b => .var b
    | _ => if t.isGround then .ground t else k
  -- matching
  for g in [0:P.goals.size] do
    for c in [0:P.clauses.size] do
      let G := P.goals[g]!
      let Cl := P.clauses[c]!
      if T.opts.dataFilter && G.dataVar.isSome != Cl.dataVal.isSome then continue
      if G.tgt.symKey != Cl.head.symKey then continue
      for i in [0:G.tgt.args.size] do
        u := (u.union (keyAt G.tgt.args[i]! (.pos .goal g #[i])) (keyAt Cl.head.args[i]! (.pos .clause c #[i]))).1
      if let (some b, some v) := (G.dataVar, Cl.dataVal) then
        u := (u.union (.var b) (keyAt v (.val c #[]))).1
  -- groundness candidates and typing clauses
  for ((a, c, b), kept) in E.sv.toArray do
    let tb := T.tyObj a (.var .clause b) .clause (T.varType b)
    for (o, _, _) in kept do
      u := (u.union (.var b) (keyOf o)).1
      if T.typingOn then
        if let (some (_, ob), some (_, oo)) := (tb, T.candTy o) then
          u := (u.union (keyOf ob) (keyOf oo)).1
  -- decomposition closure: same symbol and arity in one component join their children
  let objs := T.S.rigid ++ T.S.trigid ++ T.S.groundApps
  let mut bySym : Std.HashMap (String × Nat) (Array Obj) := {}
  for o in objs do
    let s := match o with
      | .rigid _ _ _ _ s _ | .trigid _ _ _ s _ | .value _ _ _ s _ => s
      | .ground t => t.symKey.get!
      | .slot .. => ("", 0)
    -- one representative object per key (node copies are identified)
    if nodeOf o == some 0 || nodeOf o == none then bySym := bySym.insert s ((bySym.getD s #[]).push o)
  let mut changed := true
  while changed do
    changed := false
    for (_, os) in bySym.toArray do
      let mut firstOf : Std.HashMap Key Obj := {}
      for o in os do
        let r := u.find (keyOf o)
        match firstOf.get? r with
        | none => firstOf := firstOf.insert r o
        | some o' =>
          let k1 := T.S.children[o]!
          let k2 := T.S.children[o']!
          for q in [0:min k1.size k2.size] do
            let (u', ch) := u.union (keyOf k1[q]!) (keyOf k2[q]!)
            u := u'
            if ch then changed := true
  return u

/-- M4: least depth d(g) and least proof size s(g), ignoring unification; and the minimal size of
each clause. `none` is infinity. -/
def bounds (P : Forest) (opts : EncodeOptions) : Array (Option Nat) × Array (Option Nat) × Array (Option Nat) := Id.run do
  let G := P.goals.size
  let C := P.clauses.size
  let matches_ := fun (g c : Nat) =>
    !(opts.dataFilter && P.goals[g]!.dataVar.isSome != P.clauses[c]!.dataVal.isSome) &&
    P.goals[g]!.tgt.symKey == P.clauses[c]!.head.symKey
  let lt := fun (a b : Option Nat) => match a, b with
    | some x, some y => x < y
    | some _, none => true
    | _, _ => false
  -- depth: Bellman-Ford from the root (goal 0)
  let mut d : Array (Option Nat) := (Array.range G).map fun g => if g == 0 then some 0 else none
  let mut ch := true
  while ch do
    ch := false
    for g in [0:G] do
      let some dg := d[g]! | continue
      for c in [0:C] do
        unless matches_ g c do continue
        for k in P.clauses[c]!.prems ++ P.clauses[c]!.dataPos.map (·.2) do
          if lt (some (dg + 1)) d[k]! then d := d.set! k (some (dg + 1)); ch := true
  -- sizes: least fixpoint from infinity
  let mut s : Array (Option Nat) := Array.replicate G none
  let mut cs : Array (Option Nat) := Array.replicate C none
  ch := true
  while ch do
    ch := false
    for c in [0:C] do
      let v := P.clauses[c]!.prems.foldl (fun acc p => match acc, s[p]! with
        | some x, some y => some (x + y)
        | _, _ => none) (some 1)
      if lt v cs[c]! then cs := cs.set! c v; ch := true
    for g in [0:G] do
      for c in [0:C] do
        if matches_ g c && lt cs[c]! s[g]! then s := s.set! g cs[c]!; ch := true
  return (d, s, cs)

/-- The M4 tests: `gp(α, g)` and `cl(α, c)` possible. -/
def gpOk (d s : Array (Option Nat)) (N α g : Nat) : Bool :=
  match d[g]!, s[g]! with
  | some dg, some sg => dg ≤ α && α + sg ≤ N
  | _, _ => false

def clOk (P : Forest) (opts : EncodeOptions) (d : Array (Option Nat)) (cs : Array (Option Nat)) (N α c : Nat) : Bool :=
  match cs[c]! with
  | none => false
  | some sc =>
    (List.range P.goals.size).any fun g =>
      !(opts.dataFilter && P.goals[g]!.dataVar.isSome != P.clauses[c]!.dataVal.isSome) &&
      P.goals[g]!.tgt.symKey == P.clauses[c]!.head.symKey &&
      (match d[g]! with | some dg => dg ≤ α && α + sc ≤ N | none => false)


/-! ## 8c-1 (M8_PLAN 3.9): helpers for M6 and M7 -/

/-- Unify `t₁` and `t₂` (first-order, occurs check; `bvar:i` leaves are constants) and return the
idempotent most general unifier as a list of equations `x = σ(x)`, or `none` if they do not
unify. Variables are compared by name, so the caller renames apart. -/
partial def mgu (t₁ t₂ : Term) : Option (Array (String × Term)) := do
  let s ← go t₁ t₂ {}
  let rec resolve (fuel : Nat) (t : Term) : Term :=
    match fuel with
    | 0 => t
    | f + 1 => match t with
      | .var n => match s[n]? with | some u => resolve f u | none => t
      | .app f' as => .app f' (as.map (resolve f))
  let keys := (s.toArray.map (·.1)).qsort (· < ·)
  return keys.map fun k => (k, resolve (s.size + 1) (.var k))
where
  walk (s : Std.HashMap String Term) : Term → Term
    | .var n => match s[n]? with
      | some t => walk s t
      | none => .var n
    | t => t
  occurs (s : Std.HashMap String Term) (v : String) (t : Term) : Bool :=
    match walk s t with
    | .var n => n == v
    | .app _ as => as.any (occurs s v)
  go (a b : Term) (s : Std.HashMap String Term) : Option (Std.HashMap String Term) :=
    match walk s a, walk s b with
    | .var x, .var y => if x == y then some s else some (s.insert x (.var y))
    | .var x, t | t, .var x => if occurs s x t then none else some (s.insert x t)
    | .app f as, .app g bs =>
      if f != g || as.size != bs.size then none
      else (as.zip bs).foldlM (fun s (x, z) => go x z s) s

/-- R3 (M8_PLAN 3.6.1) for one typing clause: the solved form of the two type templates, as
counts (slot equations, ground equations, residual equations, residual objects), or `none` if the
templates do not unify. -/
def r3Counts (Tb To : Term) (sameFrame : Bool) : Option (Nat × Nat × Nat × Nat) := do
  let l := Tb.subst fun n => some (.var ("L|" ++ n))
  let r := To.subst fun n => some (.var ((if sameFrame then "L|" else "R|") ++ n))
  let eqs ← mgu l r
  return eqs.foldl (fun (a, b, c, d) (_, u) =>
    if u.isVar then (a + 1, b, c, d)
    else if u.isGround then (a, b + 1, c, d)
    else (a, b, c + 1, d + u.rigidCount)) (0, 0, 0, 0)

/-- All subterms of a term. -/
partial def subterms (t : Term) : Array Term :=
  #[t] ++ t.args.flatMap subterms

/-- R4 (M8_PLAN 3.6.2): the closure Λ. Λ₀ is the set of ground level terms that occur in the
forest (targets, heads, values and every type template); the level templates are its non-ground
level subterms. Each round adds every instance of every level template with its variables taken
from the current Λ. There are N rounds (a value can be rebuilt at most once per node), and the
closure stops early when a round adds nothing. If Λ exceeds `cap`, it stops and reports `none`
with the round reached. -/
def lambdaClosure (P : Forest) (N : Nat) (cap : Nat := 100000) : Option Nat × Nat × Nat × Nat := Id.run do
  let mut all : Array Term := P.goals.map (·.tgt) ++ P.clauses.map (·.head)
  for c in P.clauses do
    if let some v := c.dataVal then all := all.push v
    for (_, t) in c.headTypes ++ c.valueTypes do if let some t := t then all := all.push t
  for g in P.goals do
    for (_, t) in g.tgtTypes do if let some t := t then all := all.push t
  for (_, t) in P.varTypes do if let some t := t then all := all.push t
  for (g, t) in P.groundTypes do
    all := all.push g
    if let some t := t then all := all.push t
  let mut lam : Std.HashSet Term := {}
  let mut tmpls : Std.HashSet Term := {}
  for t in all do
    for u in subterms t do
      if u.isLevel then
        if u.isGround then lam := lam.insert u else tmpls := tmpls.insert u
  let n0 := lam.size
  let tl := tmpls.toArray
  let mut rounds := 0
  for _ in [0:N] do
    let cur := lam.toArray
    let mut next := lam
    for tm in tl do
      let vs := tm.varsOf.toArray
      -- every assignment of the template's variables from the current Λ
      let mut asg : Array (Std.HashMap String Term) := #[{}]
      for v in vs do
        -- check the size before building the product (8c-1: building it first ran out of memory)
        if asg.size * cur.size > cap then return (none, n0, tl.size, rounds)
        asg := asg.flatMap fun σ => cur.map (σ.insert v)
      for σ in asg do
        next := next.insert (tm.subst (σ.get? ·))
        if next.size > cap then return (none, n0, tl.size, rounds)
    rounds := rounds + 1
    if next.size == lam.size then break
    lam := next
  return (some lam.size, n0, tl.size, rounds)

/-- The paths of variable `b` in `t`. -/
partial def varPaths (b : String) (t : Term) (π : Array Nat) : Array (Array Nat) := match t with
  | .var n => if n == b then #[π] else #[]
  | .app _ as => (List.range as.size).toArray.flatMap fun i => varPaths b as[i]! (π.push i)

/-- M7 (M8_PLAN 3.7.3): is clause variable `b` of clause `c` rigidly matched? Some occurrence of
`b` in head(c), at path π, is such that for every goal position g with c ▷ g, tgt(g) has a
subterm at π that is not a variable and not open. -/
def rigidlyMatched (P : Forest) (dataFilter : Bool) (c : Nat) (b : String) : String := Id.run do
  let head := P.clauses[c]!.head
  let gs := (List.range P.goals.size).filter (P.canMatch dataFilter · c)
  let ps := varPaths b head #[]
  if ps.isEmpty then return "not in head"
  if gs.isEmpty then return "no goal position matches"
  let ok := ps.any fun π => gs.all fun g =>
    match π.foldlM (fun (t : Term) i => t.args[i]?) P.goals[g]!.tgt with
    | some u => !u.isVar && !u.isOpen
    | none => false
  return if ok then "rigidly matched" else "in head, not rigidly matched"

/-- M1 to M4 for one encoding. `emit` receives each section as it is finished, so a run that is
killed keeps the sections it completed. -/
def analyze (P : Forest) (N : Nat) (opts : EncodeOptions) (E : Encoding) (emit : String → Json → IO Unit) : IO Unit := do
  let fam := fun (f : String) => (E.cnf.familyCounts.find? (·.1 == f)).map (·.2) |>.getD 0
  -- 8c-1: R1's own record (and the early exit, after which nothing else was encoded)
  let r1 := fun (extra : List (String × Json)) => Json.mkObj ([("early_exit", toJson E.info.earlyExit),
    ("root_size", toJson E.info.rootSize), ("gp_dead", toJson E.info.gpDead), ("cl_dead", toJson E.info.clDead),
    ("unit_clauses", toJson (fam "11 node bounds")),
    ("check_units_equal", toJson (E.info.earlyExit || fam "11 node bounds" == E.info.gpDead + E.info.clDead)),
    ("exclusive_skipped", toJson E.info.exclusiveSkipped)] ++ extra)
  if E.info.earlyExit then
    emit "r1" (r1 [])
    return
  emit "m1" (m1 E N)
  let T := tables P N opts E.vars
  -- reverse map from activation literal to (node, goal) or (node, clause)
  let mut litPair : Std.HashMap BLit (String × Nat × Nat) := {}
  for a in [0:N] do
    for g in [0:P.goals.size] do litPair := litPair.insert E.vars.gp[a]![g]! ("gp", a, g)
    for c in [0:P.clauses.size] do litPair := litPair.insert E.vars.cl[a]![c]! ("cl", a, c)
  -- M4 bounds
  let (d, s, cs) := bounds P opts
  let gpX := fun (a g : Nat) => !gpOk d s N a g
  let clX := fun (a c : Nat) => !clOk P opts d cs N a c
  let excludedLit := fun (l : BLit) => match litPair.get? l with
    | some ("gp", a, g) => gpX a g
    | some ("cl", a, c) => clX a c
    | _ => false
  let nGpX := (List.range N).foldl (fun n a => n + ((List.range P.goals.size).filter (gpX a ·)).length) 0
  let nClX := (List.range N).foldl (fun n a => n + ((List.range P.clauses.size).filter (clX a ·)).length) 0
  -- M2 groundness
  let (termCands, levelCands) := T.candidates
  let mut g2 : Counter := {}
  let mut gTot := 0
  let mut gDead := 0
  let mut dropsStatic := 0
  let mut dropsPrune := 0
  let mut keptMismatch := 0
  let mut nCands := 0
  -- M6 for R3 (memoised on the static templates) and M7
  let mut r3memo : Std.HashMap (String × Term × Bool) (Option (Nat × Nat × Nat × Nat)) := {}
  let mut r3 : Counter := {}
  let mut m7 : Counter := {}
  let mut m7class : Std.HashMap (Nat × String) String := {}
  for c in [0:P.clauses.size] do
    for b in P.clauses[c]!.vars do m7class := m7class.insert (c, b) (rigidlyMatched P opts.dataFilter c b)
  if opts.groundness then
    for a in [0:N] do
      for c in [0:P.clauses.size] do
        -- R1: a dead `cl(α, c)` has no groundness clauses
        if E.vars.cl[a]![c]! == BLit.ff then continue
        let dead := clX a c
        for b in P.clauses[c]!.vars do
          let m7k := m7class.getD (c, b) "?"
          let mut m7n := 0
          let lv := P.levelVars.contains b
          let tb := if lv then none else T.tyObj a (.var .clause b) .clause (T.varType b)
          let kept := E.sv.getD (a, c, b) #[]
          let mut ki := 0
          let mut svs := #[]
          for (o, al) in (if lv then levelCands else termCands) do
            nCands := nCands + 1
            let to := if lv then none else T.candTy o
            let decided := match tb, to with
              | some (t1, _), some (t2, _) => t1.isGround && t2.isGround && opts.staticTyping
              | _, _ => false
            if decided then
              if let (some (t1, _), some (t2, _)) := (tb, to) then
                if t1 != t2 then dropsStatic := dropsStatic + 1; continue
            if opts.candidatePruning && !decided then
              if let (some (t1, _), some (t2, _)) := (tb, to) then
                if !t1.unifiableApart t2 then dropsPrune := dropsPrune + 1; continue
            let some (ko, sv, _) := kept[ki]? | keptMismatch := keptMismatch + 1; continue
            unless ko == o do keptMismatch := keptMismatch + 1
            ki := ki + 1
            svs := svs.push sv
            let ls := E.labels[Obj.slot a .clause b]!
            let lo := E.labels[o]!
            let (n, _) := replay do
              addClause #[sv.neg, al]
              eqUnder #[sv] ls lo
              if T.typingOn && !decided then
                if let (some (_, ob), some (_, oo)) := (tb, to) then
                  eqUnder #[sv] E.labels[ob]! E.labels[oo]!
            -- M6 for R3: the solved form that would replace this typing clause
            if T.typingOn && !decided then
              if let (some (Tb, _), some (To, _)) := (tb, to) then
                let same := match o with
                  | .rigid β .clause .. | .slot β .clause _ | .value β .. => β == a
                  | _ => false
                let key := (b, To, same)
                let res ← match r3memo.get? key with
                  | some r => pure r
                  | none => do
                    let r := r3Counts Tb To same
                    r3memo := r3memo.insert key r
                    pure r
                let lv := if P.levelVars.contains b then "level" else "term"
                match res with
                | none => r3 := r3.add "typing clauses, templates do not unify" 1 0
                | some (sl, gr, re, ro) =>
                  r3 := (r3.add "typing clauses" 1 0).add "equations:slot" sl 0 |>.add "equations:ground" gr 0
                    |>.add "equations:residual" re 0 |>.add "residual objects" ro 0
                    |>.add s!"var:{lv}" 1 0
                  if re == 0 then r3 := r3.add "typing clauses without residual" 1 0
            m7n := m7n + n
            let rel := match nodeOf o with
              | none => "no node"
              | some β => if β == a then "same node" else if β < a then "smaller index" else "larger index"
            g2 := (g2.add s!"kind:{kindOf o}" n 1).add s!"node:{rel}" n 1 |>.add s!"kind:{kindOf o}|node:{rel}" n 1
            gTot := gTot + n
            if dead then gDead := gDead + n
          if ki != kept.size then keptMismatch := keptMismatch + 1
          let (n, _) := replay (addClause (#[E.vars.cl[a]![c]!.neg] ++ svs))
          g2 := g2.add "at-least-one per slot" n 0
          gTot := gTot + n
          if dead then gDead := gDead + n
          m7 := m7.add m7k (m7n + n) 1
  emit "m2" (Json.mkObj [("by", g2.json), ("total", toJson gTot), ("family", toJson (fam "8 groundness")),
    ("check_total_equal", toJson (gTot == fam "8 groundness")), ("check_kept_mismatch", toJson keptMismatch),
    ("candidates_considered", toJson nCands), ("dropped_static_typing", toJson dropsStatic),
    ("dropped_candidate_pruning", toJson dropsPrune)])
  emit "m6_r3" (Json.mkObj [("by", r3.json), ("distinct_template_pairs", toJson r3memo.size)])
  emit "m7" (Json.mkObj [("by", m7.json), ("note", toJson "clauses: groundness clauses of the slot; vars: slots")])
  let (lamSize, lam0, nTmpl, rounds) := lambdaClosure P N
  emit "m6_r4" (Json.mkObj [("lambda", toJson lamSize), ("lambda0", toJson lam0), ("level_templates", toJson nTmpl),
    ("rounds", toJson rounds), ("cap", toJson (100000 : Nat))])
  -- M3 decomposition
  let uf := components T E
  let symOf : Obj → String × Nat
    | .rigid _ _ _ _ s _ | .trigid _ _ _ s _ | .value _ _ _ s _ => s
    | .ground t => t.symKey.get!
    | .slot .. => ("", 0)
  let mut keys : Array (String × Nat) := #[]
  let mut bysym : Std.HashMap (String × Nat) (Array Obj) := {}
  for o in T.S.rigid ++ T.S.trigid ++ T.S.groundApps do
    let sk := symOf o
    unless bysym.contains sk do keys := keys.push sk
    bysym := bysym.insert sk ((bysym.getD sk #[]).push o)
  let mut d3 : Counter := {}
  let mut perSym : Std.HashMap String Nat := {}
  let mut dTot := 0
  let mut dDead := 0
  -- R2, as `encode`
  let mut group : Std.HashMap BLit (Bool × Nat × Nat) := {}
  if opts.exclusivePairs then
    for a in [0:N] do
      for g in [0:P.goals.size] do
        unless E.vars.gp[a]![g]! == BLit.ff do group := group.insert E.vars.gp[a]![g]! (true, a, g)
      for c in [0:P.clauses.size] do
        unless E.vars.cl[a]![c]! == BLit.ff do group := group.insert E.vars.cl[a]![c]! (false, a, c)
  let mut nExcl := 0
  for sk in keys do
    let os := bysym[sk]!
    for i in [0:os.size] do
      for j in [i+1:os.size] do
        let o1 := os[i]!
        let o2 := os[j]!
        if (o1 matches .ground _) && (o2 matches .ground _) then continue
        let a1 := T.S.actlit[o1]!
        let a2 := T.S.actlit[o2]!
        if opts.exclusivePairs then
          let excl := match group.get? a1, group.get? a2 with
            | some (k1, x1, i1), some (k2, x2, i2) =>
              x1 == x2 && ((k1 == k2 && i1 != i2) || (opts.exclusiveMutant && k1 != k2))
            | _, _ => false
          if excl then nExcl := nExcl + 1; continue
        let l1 := E.labels[o1]!
        let l2 := E.labels[o2]!
        let pruned := opts.pairPruning && (match T.tmplOf o1, T.tmplOf o2 with
          | some t1, some t2 => !t1.unifiableApart t2
          | _, _ => false)
        let (n, _) := replay do
          if pruned then
            let mut ds := #[]
            let mut differ := false
            for q in [E.info.SB:E.info.SB + E.info.IB] do
              match l1[q]!, l2[q]! with
              | .const x, .const z => if x != z then differ := true
              | .const x, z => ds := ds.push (if x then z.neg else z)
              | x, .const z => ds := ds.push (if z then x.neg else x)
              | x, z =>
                let dl ← newLit
                addClause #[dl.neg, x, z]; addClause #[dl.neg, x.neg, z.neg]; ds := ds.push dl
            unless differ do addClause (#[a1.neg, a2.neg] ++ ds)
          else
            let mut ds := #[]
            let mut ok := true
            for q in [0:l1.size] do
              match l1[q]!, l2[q]! with
              | .const x, .const z => if x != z then ok := false; break
              | .const x, z => ds := ds.push (if x then z.neg else z)
              | x, .const z => ds := ds.push (if z then x.neg else x)
              | x, z =>
                let dl ← newLit
                addClause #[dl.neg, x, z]; addClause #[dl.neg, x.neg, z.neg]; ds := ds.push dl
            if ok then
              let m ← newLit
              addClause (#[a1.neg, a2.neg] ++ ds ++ #[m])
              let k1 := T.S.children[o1]!
              let k2 := T.S.children[o2]!
              for q in [0:k1.size] do eqUnder #[m] E.labels[k1[q]!]! E.labels[k2[q]!]!
        if n == 0 then continue
        let rel := match nodeOf o1, nodeOf o2 with
          | some x, some y => if x == y then "same node" else "different nodes"
          | _, _ => "one ground"
        let comp := if uf.find (keyOf o1) == uf.find (keyOf o2) then "same component" else "different components"
        let br := if pruned then "pruned (idx differs)" else "full"
        -- M6: object kinds of the pair, crossed with level against term symbols
        let kk := if kindOf o1 ≤ kindOf o2 then s!"{kindOf o1}+{kindOf o2}" else s!"{kindOf o2}+{kindOf o1}"
        let lv := if sk.1.startsWith Term.levelPrefix then "level" else "term"
        d3 := ((d3.add s!"node:{rel}" n 0).add s!"component:{comp}" n 0).add s!"branch:{br}" n 0
          |>.add s!"node:{rel}|component:{comp}" n 0
          |>.add s!"kinds:{kk}|{lv}" n 0 |>.add s!"symclass:{lv}" n 0
          |>.add s!"kind:{kindOf o1}|{lv}" n 0 |>.add s!"kind:{kindOf o2}|{lv}" n 0
        perSym := perSym.insert s!"{sk.1}/{sk.2}" (perSym.getD s!"{sk.1}/{sk.2}" 0 + n)
        dTot := dTot + n
        if excludedLit a1 || excludedLit a2 then dDead := dDead + n
  let top := (perSym.toArray.qsort (fun x y => x.2 > y.2 || (x.2 == y.2 && x.1 < y.1))).extract 0 10
  emit "m3" (Json.mkObj [("by", d3.json), ("top_symbols", Json.arr (top.map fun (k, v) => Json.arr #[Json.str k, toJson v])),
    ("symbols", toJson perSym.size), ("total", toJson dTot), ("family", toJson (fam "5 decomposition")),
    ("check_total_equal", toJson (dTot == fam "5 decomposition")),
    ("exclusive_skipped", toJson nExcl), ("check_exclusive_equal", toJson (nExcl == E.info.exclusiveSkipped))])
  emit "r1" (r1 [])
  let total := E.cnf.numClauses
  emit "m4" (Json.mkObj [("gp_pairs", toJson (N * P.goals.size)), ("gp_excluded", toJson nGpX),
    ("cl_pairs", toJson (N * P.clauses.size)), ("cl_excluded", toJson nClX),
    ("groundness_clauses", toJson gTot), ("groundness_dead", toJson gDead),
    ("decomposition_clauses", toJson dTot), ("decomposition_dead", toJson dDead),
    ("total_clauses", toJson total),
    ("families", Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, toJson k)))])

/-- M5 on a model: the grounded slots' candidates and the pairs used, with the M4 test on each. -/
def models (P : Forest) (N : Nat) (opts : EncodeOptions) (E : Encoding) (model : Array Bool) : Except String Json := do
  let sk ← readSkeleton P E.vars model
  let val := BLit.eval model
  let mut parent : Std.HashMap Nat Nat := {}
  for n in sk do
    for ch in n.children ++ n.dataChildren.filterMap id do parent := parent.insert ch n.node
  let isAnc := fun (x y : Nat) => Id.run do   -- x a proper ancestor of y
    let mut z := y
    while true do
      match parent.get? z with
      | some p => if p == x then return true else z := p
      | none => return false
    return false
  let (d, s, cs) := bounds P opts
  -- 8c-1 (M8_PLAN 4.4): R1's bounds, with the scope term e(c) and the built-in restriction
  let B := NodeBounds.compute P opts.dataFilter true
  let mut rows : Counter := {}
  let mut viol := #[]
  let mut violE := #[]
  for n in sk do
    unless gpOk d s N n.node n.goal do viol := viol.push s!"gp({n.node}, {n.goal})"
    unless clOk P opts d cs N n.node n.clause do viol := viol.push s!"cl({n.node}, {n.clause})"
    unless B.gpLive N n.node n.goal do violE := violE.push s!"gp({n.node}, {n.goal})"
    unless B.clLive N n.node n.clause do violE := violE.push s!"cl({n.node}, {n.clause})"
    for b in P.clauses[n.clause]!.vars do
      let kept := E.sv.getD (n.node, n.clause, b) #[]
      match kept.find? (fun (_, sv, _) => val sv) with
      | none => rows := rows.add "slot without a true sv" 1 0
      | some (o, _, _) =>
        let rel := match nodeOf o with
          | none => "no node"
          | some β => if β == n.node then "same node" else if isAnc β n.node then "ancestor"
              else if isAnc n.node β then "descendant" else "neither"
        rows := (rows.add s!"kind:{kindOf o}" 1 0).add s!"node:{rel}" 1 0 |>.add s!"kind:{kindOf o}|node:{rel}" 1 0
  return Json.mkObj [("nodes", toJson sk.size), ("slots", rows.json), ("pairs_used", toJson (2 * sk.size)),
    ("bound_violations", toJson viol), ("bound_violations_e", toJson violE),
    ("local_nodes", toJson (sk.filter (P.clauses[·.clause]!.localOf.isSome)).size),
    ("skeleton", toJson (renderSkeleton P sk 0))]


/-! ## 8c-2a (M8_PLAN 4.5): R3 simulated with shared residual objects

Diagnostic code only: nothing in `SolveBySat/` changes, and the tactic never uses this.

- `triangular`: the triangular solved form of the two type templates of a typing clause, renamed apart
  as in 3.6.1 (and as `r3Counts`): the bindings that `mgu`'s `go` makes, in the order it makes them,
  before any binding is applied to another (`mgu` resolves them afterwards; this does not). `walk` only
  follows variable bindings, so every right side is a subterm of one of the two renamed templates.
- `bindingsOf`: each binding x ↦ t, with t located: a variable of either frame, a ground term, or a
  residual subterm at a path of one template. The path rule: the variable's template (L) is searched
  first, then the candidate's (R); within a template, the first occurrence in pre-order (a node before
  its arguments, arguments left to right).
- `simEncode`: a copy of `encode` in a `countOnly` CNF, with the same families in the same order and
  the same gadgets, and with an R3 switch. With R3 off it must give the encoder's counts exactly (the
  consistency check). With R3 on: the type-template objects that are no ⟦t⟧ and lie below none are left
  out of the pair loop (6.5) and of the occurs, escape and rank clauses (6.7); each typing clause is
  replaced by one `sv ⇒ L(x) = L(⟦t⟧)` per binding (`eqUnder`); a candidate whose templates do not unify
  gets no `sv`. The label widths are those of the encoder (built from every object of today's graph).
-/

/-- The triangular solved form of `t₁ = t₂`: the bindings in the order `go` makes them, or `none` if
the terms do not unify. Same algorithm as `mgu` (first order, occurs check), without the resolution. -/
partial def triangular (t₁ t₂ : Term) : Option (Array (String × Term)) := do
  let (_, out) ← go t₁ t₂ ({}, #[])
  return out
where
  walk (s : Std.HashMap String Term) : Term → Term
    | .var n => match s[n]? with
      | some t => walk s t
      | none => .var n
    | t => t
  occurs (s : Std.HashMap String Term) (v : String) (t : Term) : Bool :=
    match walk s t with
    | .var n => n == v
    | .app _ as => as.any (occurs s v)
  go (a b : Term) (st : Std.HashMap String Term × Array (String × Term)) :
      Option (Std.HashMap String Term × Array (String × Term)) :=
    let (s, out) := st
    match walk s a, walk s b with
    | .var x, .var y => if x == y then some st else some (s.insert x (.var y), out.push (x, .var y))
    | .var x, t | t, .var x => if occurs s x t then none else some (s.insert x t, out.push (x, t))
    | .app f as, .app g bs =>
      if f != g || as.size != bs.size then none
      else (as.zip bs).foldlM (fun st (x, z) => go x z st) st

/-- The first path (pre-order) at which `t` occurs in `tm`. -/
partial def firstPath (t tm : Term) (π : Array Nat := #[]) : Option (Array Nat) :=
  if tm == t then some π else
  match tm with
  | .var _ => none
  | .app _ as => Id.run do
    for h : i in [0:as.size] do
      if let some p := firstPath t as[i] (π.push i) then return some p
    return none

/-- The right side of a binding. `left`: of the variable's template L (else of the candidate's R). -/
inductive Rhs where
  | var (left : Bool) (n : String)
  | ground (t : Term)
  | sub (left : Bool) (path : Array Nat)
  /-- Not found in either template (impossible; counted as an anomaly). -/
  | missing
  deriving Inhabited, BEq

/-- One binding x ↦ t of the triangular solved form. `t` is the renamed right side. -/
structure Bind where
  left : Bool
  n : String
  rhs : Rhs
  t : Term
  deriving Inhabited

/-- A renamed variable: of L (prefix `L|`) or R (`R|`), and its name. -/
def unprefix (x : String) : Bool × String := (x.startsWith "L|", (x.drop 2).toString)

/-- R3's bindings for one typing clause: the variable's type template `Tb` (L) and the candidate's
`To` (R), renamed apart, with the same prefix when the candidate is in the same frame (as `r3Counts`).
`none` if they do not unify. -/
def bindingsOf (Tb To : Term) (same : Bool) : Option (Array Bind) := do
  let l := Tb.subst fun n => some (.var ("L|" ++ n))
  let r := To.subst fun n => some (.var ((if same then "L|" else "R|") ++ n))
  let eqs ← triangular l r
  return eqs.map fun (x, t) =>
    let (lx, nx) := unprefix x
    let rhs := match t with
      | .var y => let (ly, ny) := unprefix y; Rhs.var ly ny
      | _ => if t.isGround then .ground t else
        match firstPath t l with
        | some p => .sub true p
        | none => match firstPath t r with
          | some p => .sub false p
          | none => .missing
    { left := lx, n := nx, rhs, t }

/-- Is the candidate in the variable's frame (node `a`, clause side)? As `analyze`'s M6. -/
def sameFrame (a : Nat) : Obj → Bool
  | .rigid β .clause .. | .slot β .clause _ | .value β .. => β == a
  | _ => false

/-- A candidate's frame (node and side of its template variables) and the owner of its type. -/
def candFrame : Obj → Option (Nat × Side × TyOwner)
  | .rigid β side tid path _ _ => some (β, side, .pos side tid path)
  | .slot β side b => some (β, side, .var side b)
  | .value β c path _ _ => some (β, .clause, .val c path)
  | _ => none

def descend (S : Struct) (root : Obj) (path : Array Nat) : Option Obj :=
  path.foldlM (fun o i => (S.children.get? o).bind (·[i]?)) root

/-- The slot of a binding variable, for slot `b` at node `a` with candidate `o`. -/
def varObj (a : Nat) (o : Obj) (left : Bool) (n : String) : Option Obj :=
  if left then some (.slot a .clause n) else (candFrame o).map fun (β, side, _) => .slot β side n

/-- ⟦t⟧: the slot, the ground object, or the type-template object at the path (which must be one). -/
def rhsObj (S : Struct) (a : Nat) (b : String) (o : Obj) : Rhs → Option Obj
  | .var l n => varObj a o l n
  | .ground t => some (.ground t)
  | .sub l p =>
    let root := if l then S.tyRoot.get? (a, .var .clause b)
      else (candFrame o).bind fun (β, _, ow) => S.tyRoot.get? (β, ow)
    match root.bind (descend S · p) with
    | some x@(.trigid ..) => some x
    | _ => none
  | .missing => none

/-- Add `o` and every type-template object below it. -/
partial def closeBelow (S : Struct) (o : Obj) (acc : Std.HashSet Obj) : Std.HashSet Obj :=
  if !(o matches .trigid ..) || acc.contains o then acc else
  (S.children.getD o #[]).foldl (fun acc k => closeBelow S k acc) (acc.insert o)

/-- The kinds of M6, as `kindOf` names them. -/
def kindIdx : Obj → Nat
  | .ground _ => 0 | .rigid .. => 1 | .trigid .. => 2 | .value .. => 3 | .slot .. => 4

def kindNames : Array String :=
  #["ground object", "rigid position", "type-template object", "value object", "eigenvariable slot"]

structure SimSt where
  ls : Encode.LabState := {}
  fam : String := "0 structural"
  mark : Nat := 0
  famVars : Std.HashMap String Nat := {}

abbrev SimM := StateT SimSt CnfM

def cnfNow : SimM CNF := StateT.lift (get : CnfM CNF)

def simLab (L : Layout) (o : Obj) : SimM (Array BLit) := do
  let (l, ls) ← StateT.lift ((Encode.lab L o).run (← get).ls)
  modify fun s => { s with ls }
  return l

/-- Switch family, recording the variables allocated under the previous one. -/
def simFamily (f : String) : SimM Unit := do
  let nv := (← cnfNow).nVars
  modify fun s => { s with famVars := s.famVars.insert s.fam (s.famVars.getD s.fam 0 + (nv - s.mark)),
                           fam := f, mark := nv }
  StateT.lift (setFamily f)

structure SimOut where
  r3 : Bool
  earlyExit : Bool := false
  clauses : Nat := 0
  vars : Nat := 0
  famClauses : Array (String × Nat) := #[]
  famVars : Array (String × Nat) := #[]
  typeRigid : Nat := 0
  /-- Type-template objects kept (all, with R3 off). -/
  retained : Nat := 0
  /-- Of them, those that are some binding's ⟦t⟧ (the rest lie below one). -/
  residualTargets : Nat := 0
  /-- Typing clauses (today's) whose templates unify, and those whose templates do not. -/
  typing : Nat := 0
  typingNoUnify : Nat := 0
  bSlot : Nat := 0
  bGround : Nat := 0
  bResidual : Nat := 0
  resL : Nat := 0
  resR : Nat := 0
  anomalies : Nat := 0
  sv : Nat := 0
  pairs : Nat := 0
  exclusive : Nat := 0
  /-- Decomposition clauses by (kind, kind, level symbol): index (k₁ · 5 + k₂) · 2 + level. -/
  decomp : Array Nat := Array.replicate 50 0
  W : Nat := 0
  IB : Nat := 0
  RB : Nat := 0
  deriving Inhabited

def SimOut.json (o : SimOut) : Json := Id.run do
  let mut dk : Std.HashMap String Nat := {}
  let mut cls : Std.HashMap String Nat := {}
  for k1 in [0:5] do
    for k2 in [0:5] do
      for lv in [0:2] do
        let n := o.decomp[(k1 * 5 + k2) * 2 + lv]!
        if n == 0 then continue
        let (a, b) := (kindNames[k1]!, kindNames[k2]!)
        let kk := if a ≤ b then s!"{a}+{b}" else s!"{b}+{a}"
        let cl := if lv == 1 then "level" else "term"
        dk := dk.insert s!"{kk}|{cl}" (dk.getD s!"{kk}|{cl}" 0 + n)
        cls := cls.insert cl (cls.getD cl 0 + n)
  let obj := fun (m : Std.HashMap String Nat) =>
    Json.mkObj ((m.toArray.qsort (·.1 < ·.1)).toList.map fun (k, v) => (k, toJson v))
  return Json.mkObj [("r3", toJson o.r3), ("early_exit", toJson o.earlyExit), ("clauses", toJson o.clauses),
    ("vars", toJson o.vars), ("families", Json.mkObj (o.famClauses.toList.map fun (f, k) => (f, toJson k))),
    ("family_vars", Json.mkObj (o.famVars.toList.map fun (f, k) => (f, toJson k))),
    ("type_rigid_built", toJson o.typeRigid), ("type_rigid_retained", toJson o.retained),
    ("residual_targets", toJson o.residualTargets),
    ("typing_unify", toJson o.typing), ("typing_no_unify", toJson o.typingNoUnify),
    ("bindings", Json.mkObj [("slot", toJson o.bSlot), ("ground", toJson o.bGround), ("residual", toJson o.bResidual),
      ("residual_in_L", toJson o.resL), ("residual_in_R", toJson o.resR)]),
    ("anomalies", toJson o.anomalies), ("sv", toJson o.sv), ("full_pairs", toJson o.pairs),
    ("exclusive_skipped", toJson o.exclusive), ("decomposition_kinds", obj dk), ("decomposition_symclass", obj cls),
    ("W", toJson o.W), ("IB", toJson o.IB), ("RB", toJson o.RB)]

open Encode in
/-- A copy of `encode` (SolveBySat/Encode.lean) in a `countOnly` CNF, with R3 (M8_PLAN 4.5) as a
switch. Every family is emitted in the encoder's order with the encoder's gadgets; only the parts
marked "R3" differ, and only when `r3` is set. -/
def simEncode (P : Forest) (N : Nat) (opts : EncodeOptions) (r3 : Bool) : SimOut := Id.run do
  let C := P.clauses.size
  let G := P.goals.size
  let A := P.maxPrems
  let NB : Option NodeBounds := if opts.nodeBounds then some (opts.bounds P) else none
  if let some B := NB then
    if !B.gpLive N 0 0 opts.boundsTight then
      let ((), F) := buildCNF (do setFamily "11 node bounds"; addClause #[]) { countOnly := true }
      return { r3, earlyExit := true, clauses := F.numClauses, vars := F.nVars, famClauses := F.familyCounts }
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
    let mut cl := cl
    let mut gp := gp
    if let some B := NB then
      setFamily "11 node bounds"
      for a in [0:N] do
        for c in [0:C] do
          unless B.clLive N a c opts.boundsTight do
            let l ← kill cl[a]![c]!
            cl := cl.modify a fun r => r.set! c l
        for g in [0:G] do
          unless B.gpLive N a g opts.boundsTight do
            let l ← kill gp[a]![g]!
            gp := gp.modify a fun r => r.set! g l
    return { N, A, act, cl, gp, y, anc, u }
  let (V, F0) := buildCNF go { countOnly := true }
  let act := V.act
  let cl := V.cl
  let gp := V.gp
  let y := fun a b k => V.y[(a, b, k)]!
  let anc := fun g b => V.anc[(g, b)]!
  let u := fun b g => V.u[(b, g)]!
  -- the static tables, the object graph and the candidates: as `tables` (a copy of `encode`'s)
  let T := tables P N opts V
  let S := T.S
  let typingOn := T.typingOn
  let varType := T.varType
  let values := T.values
  let isLevelVar := fun b => P.levelVars.contains b
  -- the label layout, as `encode` (widths from today's graph, with every type-template object)
  let mut syms : Std.HashMap (Option (String × Nat)) Nat := ({} : Std.HashMap _ _).insert none 0
  let mut groundIds : Std.HashMap Term Nat := {}
  let mut maxh := 0
  let mut stack : Array Term := #[]
  let atoms := P.goals.map (·.tgt) ++ P.clauses.map (·.head)
  let nv := values.size
  let allTypes := T.allTypes
  for ti in [0:atoms.size + nv + allTypes.size] do
    let isAtom := ti < atoms.size + nv
    let t := if ti < atoms.size then atoms[ti]! else if isAtom then values[ti - atoms.size]!.2
      else allTypes[ti - atoms.size - nv]!
    if ti < atoms.size then
      maxh := max maxh t.height
      for x in t.args.reverse do stack := stack.push x
    else if isAtom then
      if !syms.contains t.symKey then syms := syms.insert t.symKey syms.size
      for x in t.args.reverse do stack := stack.push x
    else stack := stack.push t
    while !stack.isEmpty do
      let x := stack.back!
      stack := stack.pop
      if x.isVar then continue
      if !syms.contains x.symKey then syms := syms.insert x.symKey syms.size
      if x.isGround then
        if !groundIds.contains x then groundIds := groundIds.insert x groundIds.size
      for a in x.args.reverse do stack := stack.push a
  let eigs := P.eigs
  let SB := max 1 (clog2 (syms.size + 1))
  let K := S.rigid.size + S.trigid.size + groundIds.size + N * eigs.size + 1
  let IB := max 1 (clog2 (K + 1))
  let rc := fun (t? : Option Term) => match t? with | some t => t.rigidCount | none => 0
  let tyG := fun (g : GoalPos) => if !typingOn then 0 else
    g.eig.foldl (fun n b => n + rc (varType b)) 0 + g.tgtTypes.foldl (fun n (_, t) => n + rc t) 0
  let tyC := fun (c : Clause) => (if !typingOn then 0 else
    c.vars.foldl (fun n b => n + rc (varType b)) 0 + c.headTypes.foldl (fun n (_, t) => n + rc t) 0 +
    c.valueTypes.foldl (fun n (_, t) => n + rc t) 0) +
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
  let dead := fun (l : BLit) => l == BLit.ff
  let tyObj := T.tyObj
  let candTy := T.candTy
  let (belowG, belowC) := if opts.framePruning then P.varsBelow else (#[], #[])
  let tmplOf := T.tmplOf
  let (termCands, levelCands) := T.candidates
  -- R3: the retained type-template objects (a pass over the typing clauses of family 8, before it)
  let mut memo : Std.HashMap (String × Term × Bool) (Option (Array Bind)) := {}
  let mut retained : Std.HashSet Obj := {}
  let mut targets : Std.HashSet Obj := {}
  if r3 && typingOn && opts.groundness then
    for a in [0:N] do
      for c in [0:C] do
        if dead cl[a]![c]! then continue
        for b in P.clauses[c]!.vars do
          if isLevelVar b then continue
          let some (Tb, _) := tyObj a (.var .clause b) .clause (varType b) | continue
          for (o, _) in termCands do
            let some (To, _) := candTy o | continue
            let decided := Tb.isGround && To.isGround && opts.staticTyping
            if decided then continue
            if opts.candidatePruning && !Tb.unifiableApart To then continue
            let key := (b, To, sameFrame a o)
            let bs ← match memo.get? key with
              | some r => pure r
              | none => do
                let r := bindingsOf Tb To key.2.2
                memo := memo.insert key r
                pure r
            let some bs := bs | continue
            for bd in bs do
              if let .sub .. := bd.rhs then
                if let some x := rhsObj S a b o bd.rhs then
                  targets := targets.insert x
                  retained := closeBelow S x retained
  let trig := if r3 then S.trigid.filter retained.contains else S.trigid
  let families : SimM (SimOut) := do
    let lab := simLab L
    let mut out : SimOut := { r3, typeRigid := S.trigid.size, retained := trig.size,
                              residualTargets := if r3 then targets.size else 0, W, IB, RB }
    -- 6.1 node assignment
    simFamily "1 node assignment"
    for a in [0:N] do
      amo (cl[a]!.filter (!dead ·)) opts.ladderAmo; addClause (#[neg act[a]!] ++ cl[a]!)
      for c in [0:C] do addClause #[neg cl[a]![c]!, act[a]!]
      amo (gp[a]!.filter (!dead ·)) opts.ladderAmo; addClause (#[neg act[a]!] ++ gp[a]!)
      for g in [0:G] do addClause #[neg gp[a]![g]!, act[a]!]
      if a > 0 then addClause #[neg act[a]!, act[a-1]!]
    addClause #[act[0]!]; addClause #[gp[0]![0]!]
    -- 6.2 tree shape
    simFamily "2 tree shape"
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
            for b in [a+1:N] do
              addClause #[neg cl[a]![c]!, neg (y a b k), gp[b]![dps[k - prems.size]!.2]!]
          else
            for b in [a+1:N] do addClause #[neg cl[a]![c]!, neg (y a b k)]
    if opts.symmetry then
      simFamily "10 symmetry breaking"
      for b in [1:N-1] do
        for a in [0:b] do
          for k in [0:A] do
            for a' in [0:a+1] do
              for k' in [0:A] do
                if a' < a || (a' == a && k' < k) then
                  addClause #[neg (y a b k), neg (y a' (b+1) k')]
    -- 6.3 context
    simFamily "3 context (local hypotheses, ancestors)"
    for b in [0:N] do
      amo ((Array.range (b+1)).map fun g => u b g) opts.ladderAmo
      for c in [0:C] do
        match P.clauses[c]!.localOf with
        | none => for g in [0:b+1] do addClause #[neg cl[b]![c]!, neg (u b g)]
        | some lg =>
          addClause (#[neg cl[b]![c]!] ++ (Array.range (b+1)).map fun g => u b g)
          for g in [0:b+1] do addClause #[neg (u b g), neg cl[b]![c]!, gp[g]![lg]!]
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
    simFamily "4 matching"
    for a in [0:N] do
      for g in [0:G] do
        for c in [0:C] do
          if dead gp[a]![g]! || dead cl[a]![c]! then continue
          let dataGoal := P.goals[g]!.dataVar
          let dataVal := P.clauses[c]!.dataVal
          if opts.dataFilter && dataGoal.isSome != dataVal.isSome then
            addClause #[neg gp[a]![g]!, neg cl[a]![c]!]
          else if P.goals[g]!.tgt.symKey != P.clauses[c]!.head.symKey then
            addClause #[neg gp[a]![g]!, neg cl[a]![c]!]
          else
            let r1 := S.root[(a, Side.goal, g)]!
            let r2 := S.root[(a, Side.clause, c)]!
            for i in [0:r1.size] do
              eqUnder #[gp[a]![g]!, cl[a]![c]!] (← lab r1[i]!) (← lab r2[i]!)
            if let (some b, some _) := (dataGoal, dataVal) then
              eqUnder #[gp[a]![g]!, cl[a]![c]!] (← lab (slot a .goal b)) (← lab S.valueRoot[(a, c)]!)
    -- 6.5 decomposition (R3: the dropped type-template objects are not in the pair loop)
    simFamily "5 decomposition"
    let mut keys : Array (String × Nat) := #[]
    let mut bysym : Std.HashMap (String × Nat) (Array Obj) := {}
    let symOf : Obj → String × Nat
      | .rigid _ _ _ _ s _ | .trigid _ _ _ s _ | .value _ _ _ s _ => s
      | .ground t => t.symKey.get!
      | .slot .. => ("", 0)
    for o in S.rigid ++ trig ++ S.groundApps do
      let s := symOf o
      unless bysym.contains s do keys := keys.push s
      bysym := bysym.insert s ((bysym.getD s #[]).push o)
    let mut group : Std.HashMap BLit (Bool × Nat × Nat) := {}
    if opts.exclusivePairs then
      for a in [0:N] do
        for g in [0:G] do
          unless dead gp[a]![g]! do group := group.insert gp[a]![g]! (true, a, g)
        for c in [0:C] do
          unless dead cl[a]![c]! do group := group.insert cl[a]![c]! (false, a, c)
    let exclusive := fun (o1 o2 : Obj) => match group.get? (actlit o1), group.get? (actlit o2) with
      | some (k1, a1, i1), some (k2, a2, i2) =>
        a1 == a2 && ((k1 == k2 && i1 != i2) || (opts.exclusiveMutant && k1 != k2))
      | _, _ => false
    let mut decomp := out.decomp
    for s in keys do
      let os := bysym[s]!
      let lv := if s.1.startsWith Term.levelPrefix then 1 else 0
      for i in [0:os.size] do
        for j in [i+1:os.size] do
          let o1 := os[i]!
          let o2 := os[j]!
          if (o1 matches .ground _) && (o2 matches .ground _) then continue
          if opts.exclusivePairs && exclusive o1 o2 then out := { out with exclusive := out.exclusive + 1 }; continue
          let n0 := (← cnfNow).nClauses
          let l1 ← lab o1
          let l2 ← lab o2
          let pruned := opts.pairPruning && (match tmplOf o1, tmplOf o2 with
            | some t1, some t2 => !t1.unifiableApart t2
            | _, _ => false)
          if pruned then
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
          else
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
            if ok then
              out := { out with pairs := out.pairs + 1 }
              let m ← (newLit : CnfM _)
              addClause (#[neg (actlit o1), neg (actlit o2)] ++ ds ++ #[m])
              let k1 := kids o1
              let k2 := kids o2
              for q in [0:k1.size] do eqUnder #[m] (← lab k1[q]!) (← lab k2[q]!)
          let dn := (← cnfNow).nClauses - n0
          if dn > 0 then
            let ix := (kindIdx o1 * 5 + kindIdx o2) * 2 + lv
            decomp := decomp.modify ix (· + dn)
    out := { out with decomp }
    -- 6.6 links
    simFamily "6 links (environment copies)"
    for a in [0:N] do
      for b in [a+1:N] do
        for c in [0:C] do
          if dead cl[a]![c]! then continue
          let cc := P.clauses[c]!
          for k in [0:cc.prems.size + cc.dataPos.size] do
            let child := if k < cc.prems.size then cc.prems[k]! else cc.dataPos[k - cc.prems.size]!.2
            for v in P.clauseFrame c do
              if opts.framePruning && !(belowG[child]!.contains v) then continue
              eqUnder #[cl[a]![c]!, y a b k] (← lab (slot b .goal v)) (← lab (slot a .clause v))
    for b in [0:N] do
      for g in [0:b+1] do
        for c in [0:C] do
          if P.clauses[c]!.localOf.isSome && !dead cl[b]![c]! then
            for v in P.clauses[c]!.env do
              if opts.framePruning && !(belowC[c]!.contains v) then continue
              eqUnder #[u b g, cl[b]![c]!] (← lab (slot b .clause v)) (← lab (slot g .goal v))
    -- 6.7 eigenvariables, occurs check, scope (R3: only the retained type-template objects)
    simFamily "7 eigenvariables, occurs check, scope"
    for a in [0:N] do
      for i in [0:eigs.size] do
        let (g, b) := eigs[i]!
        if dead gp[a]![g]! then continue
        let code := 1 + a * eigs.size + i
        let cst := constBits 0 SB ++ constBits code IB ++ constBits 0 RB ++
          (Array.range N).map (fun x => BLit.const (x == a)) ++ L.openBits false
        eqUnder #[gp[a]![g]!] (← lab (slot a .goal b)) cst
    for o in S.rigid ++ trig do
      let al := actlit o
      let lo ← lab o
      for ch in kids o do
        let lc ← lab ch
        if opts.occurs then ltUnder #[al] (L.rank lc) (L.rank lo)
        for g in [0:N] do addClause #[neg al, neg (L.esc lc)[g]!, (L.esc lo)[g]!]
    if opts.scope then
      for a in [0:N] do
        for c in [0:C] do
          if dead cl[a]![c]! then continue
          for b in P.clauses[c]!.vars do
            let E := L.esc (← lab (slot a .clause b))
            for g in [0:N] do
              if g > a then addClause #[neg cl[a]![c]!, neg E[g]!]
              else if g < a then addClause #[neg cl[a]![c]!, neg E[g]!, anc g a]
    -- 6.8 groundness and typing (R3: the bindings replace the typing clause)
    simFamily "8 groundness"
    let mut memo := memo
    if opts.groundness then
      for a in [0:N] do
        for c in [0:C] do
          if dead cl[a]![c]! then continue
          for b in P.clauses[c]!.vars do
            let lv := isLevelVar b
            let tb := if lv then none else tyObj a (.var .clause b) .clause (varType b)
            let mut svs := #[]
            for (o, al) in (if lv then levelCands else termCands) do
              let to := if lv then none else candTy o
              let decided := match tb, to with
                | some (t1, _), some (t2, _) => t1.isGround && t2.isGround && opts.staticTyping
                | _, _ => false
              if decided then
                if let (some (t1, _), some (t2, _)) := (tb, to) then
                  if t1 != t2 then continue
              if opts.candidatePruning && !decided then
                if let (some (t1, _), some (t2, _)) := (tb, to) then
                  if !t1.unifiableApart t2 then continue
              -- the typing clause's solved form (counted in both settings)
              let mut bs? : Option (Array Bind) := none
              let typed := typingOn && !decided && tb.isSome && to.isSome
              if typed then
                if let (some (Tb, _), some (To, _)) := (tb, to) then
                  let key := (b, To, sameFrame a o)
                  let r ← match memo.get? key with
                    | some r => pure r
                    | none => do
                      let r := bindingsOf Tb To key.2.2
                      memo := memo.insert key r
                      pure r
                  match r with
                  | none =>
                    out := { out with typingNoUnify := out.typingNoUnify + 1 }
                    -- R3: a candidate whose templates do not unify is dropped
                    if r3 then continue
                  | some bs =>
                    bs? := some bs
                    out := { out with typing := out.typing + 1 }
                    for bd in bs do
                      match bd.rhs with
                      | .var .. => out := { out with bSlot := out.bSlot + 1 }
                      | .ground _ => out := { out with bGround := out.bGround + 1 }
                      | .sub l _ =>
                        out := { out with bResidual := out.bResidual + 1 }
                        if l then out := { out with resL := out.resL + 1 }
                        else out := { out with resR := out.resR + 1 }
                      | .missing => out := { out with anomalies := out.anomalies + 1 }
              let sv ← (newLit : CnfM _)
              out := { out with sv := out.sv + 1 }
              addClause #[neg sv, al]
              eqUnder #[sv] (← lab (slot a .clause b)) (← lab o)
              if typed then
                if let (some (_, ob), some (_, oo)) := (tb, to) then
                  if r3 then
                    for bd in bs?.getD #[] do
                      match varObj a o bd.left bd.n, rhsObj S a b o bd.rhs with
                      | some x, some t => eqUnder #[sv] (← lab x) (← lab t)
                      | _, _ => out := { out with anomalies := out.anomalies + 1 }
                  else
                    eqUnder #[sv] (← lab ob) (← lab oo)
              svs := svs.push sv
            addClause (#[neg cl[a]![c]!] ++ svs)
    simFamily "end"
    return out
  let ((out, st), F) := (families.run {}).run F0
  let fv := st.famVars.toArray.filter (fun (f, n) => f != "end" && (n > 0 || f == "0 structural")) |>.qsort (·.1 < ·.1)
  return { out with clauses := F.numClauses, vars := F.nVars, famClauses := F.familyCounts, famVars := fv }

/-- 8c-2a: the projection at one point, R3 off (the consistency check) and on. -/
def r3sim (P : Forest) (N : Nat) (opts : EncodeOptions) (emit : String → Json → IO Unit) : IO Unit := do
  for r3 in [false, true] do
    let o := simEncode P N opts r3
    emit (if r3 then "r3_on" else "r3_off") o.json
    if o.earlyExit then return

/-! ### The model check (M8_PLAN 4.5, a stop rule) -/

/-- Read the terms of a model back from the labels: each label value names the term of an active
rigid, value, type-template or ground object with that label (its symbol applied to its children's
terms), or the eigenvariable whose code it is. -/
structure Readback where
  rep : Std.HashMap (Array Bool) Obj := {}
  eig : Std.HashMap (Array Bool) Term := {}
  conflicts : Nat := 0

partial def Readback.term (R : Readback) (E : Encoding) (S : Struct) (val : BLit → Bool) (fuel : Nat)
    (bits : Array Bool) : Option Term :=
  match fuel with
  | 0 => none
  | f + 1 =>
    if let some t := R.eig.get? bits then some t else
    match R.rep.get? bits with
    | some (.ground t) => some t
    | some o => do
      let s ← match o with
        | .rigid _ _ _ _ s _ | .trigid _ _ _ s _ | .value _ _ _ s _ => some s.1
        | _ => none
      -- a ground child is its own term (it may have no label: labels are allocated lazily)
      let ks ← (S.children.getD o #[]).mapM fun k => match k with
        | .ground t => some t
        | _ => do
          let l ← E.labels.get? k
          R.term E S val f (l.map val)
      return .app s ks
    | none => none

/-- The model check for one model: every triangular binding of every candidate with a true `sv` and a
typing clause must hold under the substitution read back from the model (σ(x) = σ(t), t read through
σ of its variables), and its label check L(x) = L(⟦t⟧) is reported too. -/
def r3ModelCheck (P : Forest) (N : Nat) (opts : EncodeOptions) (E : Encoding) (model : Array Bool) :
    Except String Json := do
  let sk ← readSkeleton P E.vars model
  let val := BLit.eval model
  let T := tables P N opts E.vars
  let S := T.S
  let bitsOf := fun (o : Obj) => (E.labels.get? o).map (·.map val)
  -- representatives
  let mut R : Readback := {}
  let objs := S.rigid ++ S.trigid ++ S.groundApps ++
    (S.children.toArray.filterMap fun (o, _) => if o matches .ground _ then some o else none)
  for o in objs do
    if !(val (S.actlit.getD o BLit.ff)) then continue
    if let some bs := bitsOf o then
      unless R.rep.contains bs do R := { R with rep := R.rep.insert bs o }
  let eigs := P.eigs
  for a in [0:N] do
    for (g, b) in eigs do
      if val E.vars.gp[a]![g]! then
        if let some bs := bitsOf (.slot a .goal b) then R := { R with eig := R.eig.insert bs (.app s!"eig:{a}:{b}" #[]) }
  let fuel := objs.size + 10
  -- consistency of the read-back: every active object reads back as its symbol over its children
  let mut conflicts := 0
  let mut conflictEx : Array String := #[]
  for o in S.rigid ++ S.trigid ++ S.groundApps do
    if !(val (S.actlit.getD o BLit.ff)) then continue
    let some bs := bitsOf o | continue
    let own := R.term E S val fuel bs
    let s := match o with
      | .rigid _ _ _ _ s _ | .trigid _ _ _ s _ | .value _ _ _ s _ => s.1
      | .ground t => (t.symKey.map (·.1)).getD ""
      | .slot .. => ""
    let ks := (S.children.getD o #[]).mapM fun k => match k with
      | .ground t => some t
      | _ => (bitsOf k).bind (R.term E S val fuel)
    if own != ks.map (.app s) then
      conflicts := conflicts + 1
      if conflictEx.size < 5 then
        conflictEx := conflictEx.push s!"{repr o}: label reads {(own.map (·.toString)).getD "?"}, children read {(ks.map (fun as => (Term.app s as).toString)).getD "?"}, representative {repr (R.rep.get? bs)}"
  let σslot := fun (o : Obj) => (bitsOf o).bind (R.term E S val fuel)
  let mut checked : Counter := {}
  let mut fails : Array String := #[]
  let mut labelMismatch := 0
  let mut unreadable := 0
  let mut chosenTyped := 0
  for n in sk do
    let a := n.node
    let c := n.clause
    for b in P.clauses[c]!.vars do
      if P.levelVars.contains b then continue
      let tb := T.tyObj a (.var .clause b) .clause (T.varType b)
      for (o, sv, _) in E.sv.getD (a, c, b) #[] do
        unless val sv do continue
        let to := T.candTy o
        let some (Tb, _) := tb | continue
        let some (To, _) := to | continue
        if (Tb.isGround && To.isGround && opts.staticTyping) || !T.typingOn then continue
        chosenTyped := chosenTyped + 1
        let some bs := bindingsOf Tb To (sameFrame a o)
          | fails := fails.push s!"node {a}, {b}, candidate {repr o}: templates do not unify"
        for bd in bs do
          let kind := match bd.rhs with
            | .var .. => "slot" | .ground _ => "ground" | .sub .. => "shared residual" | .missing => "missing"
          checked := checked.add kind 1 0
          let some x := varObj a o bd.left bd.n | fails := fails.push s!"node {a}, {b}: no slot for {bd.n}"
          let σx := σslot x
          let σt := (bd.t.varsOf.toArray.mapM fun v =>
            let (l, nm) := unprefix v
            (varObj a o l nm).bind σslot |>.map (v, ·))
          match σx, σt with
          | some sx, some st =>
            let m : Std.HashMap String Term := st.foldl (fun m (v, t) => m.insert v t) {}
            let tt := bd.t.subst (m.get? ·)
            if sx != tt then
              fails := fails.push s!"node {a}, {b}, candidate {repr o}: {bd.n} ↦ {bd.t.toString}: σ(x) = {sx.toString}, σ(t) = {tt.toString}"
          | _, _ => unreadable := unreadable + 1
          match rhsObj S a b o bd.rhs with
          | some t =>
            match bitsOf x, bitsOf t with
            | some l1, some l2 => if l1 != l2 then labelMismatch := labelMismatch + 1
            | _, _ => pure ()
          | none => fails := fails.push s!"node {a}, {b}: ⟦t⟧ not found for {bd.t.toString}"
  return Json.mkObj [("nodes", toJson sk.size), ("chosen_typed", toJson chosenTyped), ("checked", checked.json),
    ("failures", toJson fails), ("label_mismatch", toJson labelMismatch), ("unreadable", toJson unreadable),
    ("readback_conflicts", toJson conflicts), ("readback_conflict_examples", toJson conflictEx), ("skeleton", toJson (renderSkeleton P sk 0))]

end M8Diag
