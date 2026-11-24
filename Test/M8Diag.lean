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
  let buildAll : StateM Struct Unit := do
    for a in [0:N] do
      for g in [0:G] do
        let args := P.goals[g]!.tgt.args
        let mut os := #[]
        for i in [0:args.size] do os := os.push (← build a .goal g gp[a]![g]! args[i]! #[i])
        modify fun S => { S with root := S.root.insert (a, .goal, g) os }
      for c in [0:C] do
        let args := P.clauses[c]!.head.args
        let mut os := #[]
        for i in [0:args.size] do os := os.push (← build a .clause c cl[a]![c]! args[i]! #[i])
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
    for (g, b) in T.P.eigs do termCands := termCands.push (Obj.slot a .goal b, T.V.gp[a]![g]!)
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

/-- M1 to M4 for one encoding. `emit` receives each section as it is finished, so a run that is
killed keeps the sections it completed. -/
def analyze (P : Forest) (N : Nat) (opts : EncodeOptions) (E : Encoding) (emit : String → Json → IO Unit) : IO Unit := do
  let fam := fun (f : String) => (E.cnf.familyCounts.find? (·.1 == f)).map (·.2) |>.getD 0
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
  if opts.groundness then
    for a in [0:N] do
      for c in [0:P.clauses.size] do
        let dead := clX a c
        for b in P.clauses[c]!.vars do
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
  emit "m2" (Json.mkObj [("by", g2.json), ("total", toJson gTot), ("family", toJson (fam "8 groundness")),
    ("check_total_equal", toJson (gTot == fam "8 groundness")), ("check_kept_mismatch", toJson keptMismatch),
    ("candidates_considered", toJson nCands), ("dropped_static_typing", toJson dropsStatic),
    ("dropped_candidate_pruning", toJson dropsPrune)])
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
  for sk in keys do
    let os := bysym[sk]!
    for i in [0:os.size] do
      for j in [i+1:os.size] do
        let o1 := os[i]!
        let o2 := os[j]!
        if (o1 matches .ground _) && (o2 matches .ground _) then continue
        let l1 := E.labels[o1]!
        let l2 := E.labels[o2]!
        let a1 := T.S.actlit[o1]!
        let a2 := T.S.actlit[o2]!
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
        d3 := ((d3.add s!"node:{rel}" n 0).add s!"component:{comp}" n 0).add s!"branch:{br}" n 0
          |>.add s!"node:{rel}|component:{comp}" n 0
        perSym := perSym.insert s!"{sk.1}/{sk.2}" (perSym.getD s!"{sk.1}/{sk.2}" 0 + n)
        dTot := dTot + n
        if excludedLit a1 || excludedLit a2 then dDead := dDead + n
  let top := (perSym.toArray.qsort (fun x y => x.2 > y.2 || (x.2 == y.2 && x.1 < y.1))).extract 0 10
  emit "m3" (Json.mkObj [("by", d3.json), ("top_symbols", Json.arr (top.map fun (k, v) => Json.arr #[Json.str k, toJson v])),
    ("symbols", toJson perSym.size), ("total", toJson dTot), ("family", toJson (fam "5 decomposition")),
    ("check_total_equal", toJson (dTot == fam "5 decomposition"))])
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
  let mut rows : Counter := {}
  let mut viol := #[]
  for n in sk do
    unless gpOk d s N n.node n.goal do viol := viol.push s!"gp({n.node}, {n.goal})"
    unless clOk P opts d cs N n.node n.clause do viol := viol.push s!"cl({n.node}, {n.clause})"
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
    ("bound_violations", toJson viol), ("skeleton", toJson (renderSkeleton P sk 0))]

end M8Diag
