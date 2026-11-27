/-
SolveBySat.Decode: from a model to a checked proof term (SPEC §8).

1. Read the skeleton (`readSkeleton`, pure, in Encode.lean).
2. Replay each node in `MetaM`: introduce the goal position's binders, build the head term
   (constant with fresh level metavariables, or the free variable of the introducing
   node), open its binders as metavariables, unify its conclusion with the target under
   reducible transparency, and replay each child on its premise's metavariable.
3. Ground what unification left open: a clause variable that no equation determines is
   still grounded by the model (SPEC §2.2, "Determined arguments"; §6.8). Its value is read
   from the model's groundness witness `sv`, translated back to an expression (a ground
   term, an eigenvariable of some node, or a position of some node's instantiated target
   or head), and assigned after a type check. See NOTES.md, milestone 2.
4. Instantiate, fail if any metavariable remains, and type-check.
Any failure on a satisfiable CNF is a bug and is reported with the skeleton.
-/
import Lean
import SolveBySat.Compile
import SolveBySat.Encode

namespace SolveBySat

open Lean Meta

structure DState where
  /-- Free variables introduced at each node, by binder index. -/
  nodeFVars : Std.HashMap Nat (Array Expr) := {}
  /-- Metavariables of the clause slots, `(α, static name)`. -/
  slotMVars : Array ((Nat × String) × Expr) := #[]
  /-- Level metavariables of the level-variable slots, `(α, static name)`. -/
  slotLevels : Array ((Nat × String) × Level) := #[]
  /-- The target atom at each node, and the conclusion of its clause. -/
  nodeTarget : Std.HashMap Nat Expr := {}
  nodeHead : Std.HashMap Nat Expr := {}
  /-- The value built at each data node (SPEC §6.9). -/
  nodeValue : Std.HashMap Nat Expr := {}

abbrev DecodeM := StateRefT DState MetaM

/-- Follow a template path through an instantiated expression (see `decompose`), into
universe levels where the path continues there. -/
def navigatePiece (e : Expr) (path : Array Nat) (atom : Bool := true) : MetaM Piece := do
  let mut cur := Piece.expr (← instantiateMVars e)
  let mut first := atom
  for i in path do
    match cur with
    | .expr e =>
      match decompose e (atom := first) with
      | .error msg => throwError "cannot follow template path {path} into {e}: {msg}"
      | .ok (_, pieces) =>
        let some p := pieces[i]? | throwError "template path {path} leaves {e}"
        cur := p
    | .level l =>
      let l ← instantiateLevelMVars l
      let kids := match l with
        | .succ a => #[a]
        | .max a b | .imax a b => #[a, b]
        | _ => #[]
      let some k := kids[i]? | throwError "template path {path} leaves the level {l}"
      cur := .level k
    first := false
  return cur

def navigate (e : Expr) (path : Array Nat) (atom : Bool := true) : MetaM Expr := do
  match ← navigatePiece e path atom with
  | .expr x => return x
  | .level _ => throwError "template path {path} ends in a universe level"

def navigateLevel (e : Expr) (path : Array Nat) : MetaM Level := do
  match ← navigatePiece e path with
  | .level l => return l
  | .expr x => throwError "template path {path} ends in the term {x}, not a level"

/-- A ground level template as a level (`lvl:param:p` is a universe parameter of the goal). -/
partial def termToLevel? : Term → Option Level
  | .app "lvl:zero" #[] => some .zero
  | .app "lvl:succ" #[a] => (termToLevel? a).map .succ
  | .app "lvl:max" #[a, b] => do return .max (← termToLevel? a) (← termToLevel? b)
  | .app "lvl:imax" #[a, b] => do return .imax (← termToLevel? a) (← termToLevel? b)
  | .app s #[] => if s.startsWith "lvl:param:" then some (.param (s.drop 10).toString.toName) else none
  | _ => none

/-- Replay a built-in connective rule (SPEC §4.2 table) on the target `tgt`. Returns the
proof term and the metavariable of each premise, in premise order. -/
def replayBuiltin (k : Builtin) (tgt : Expr) (a : Nat) (vars : Array String) : DecodeM (Expr × Array Expr) := do
  let tgt := tgt.consumeMData
  let bad {α} : DecodeM α := throwError "node {a}: built-in rule {repr k} does not fit the target {tgt}"
  match k with
  | .andIntro =>
    let some (A, B) := binApp? ``And tgt | bad
    let pa ← mkFreshExprMVar A
    let pb ← mkFreshExprMVar B
    return (mkApp4 (mkConst ``And.intro) A B pa pb, #[pa, pb])
  | .orInl =>
    let some (A, B) := binApp? ``Or tgt | bad
    let pa ← mkFreshExprMVar A
    return (mkApp3 (mkConst ``Or.inl) A B pa, #[pa])
  | .orInr =>
    let some (A, B) := binApp? ``Or tgt | bad
    let pb ← mkFreshExprMVar B
    return (mkApp3 (mkConst ``Or.inr) A B pb, #[pb])
  | .iffIntro =>
    let some (A, B) := binApp? ``Iff tgt | bad
    let h1 ← mkFreshExprMVar (← mkArrow A B)
    let h2 ← mkFreshExprMVar (← mkArrow B A)
    return (mkApp4 (mkConst ``Iff.intro) A B h1 h2, #[h1, h2])
  | .trueIntro =>
    unless tgt.isConstOf ``True do bad
    return (mkConst ``True.intro, #[])
  | .existsIntro =>
    unless tgt.isAppOfArity ``Exists 2 do bad
    let .const _ us := tgt.getAppFn | bad
    let α := tgt.appFn!.appArg!
    let p := tgt.appArg!
    let w ← mkFreshExprMVar α
    let some b := vars[0]? | bad
    modify fun s => { s with slotMVars := s.slotMVars.push ((a, b), w) }
    let h ← mkFreshExprMVar (p.beta #[w])
    return (mkApp4 (mkConst ``Exists.intro us) α p w h, #[h])

/-- Build the proof (or, for a data clause, the value) of node `a`'s clause: its head term
(a constant with fresh level metavariables, or the free variable of the introducing node),
then the clause's recipe (open binders, project out of `∧`, apply `↔`). Returns the term,
its type (the clause's head, instantiated), the premise metavariables, and the
metavariables of the clause's variables by static name. -/
def instantiateClause (C : Compiled) (n : SkelNode) : DecodeM (Expr × Expr × Array Expr × Std.HashMap String Expr) := do
  let a := n.node
  let cinfo := C.clauseInfo[n.clause]!
  let cl := C.forest.clauses[n.clause]!
  let head ← match cinfo.origin with
    | .localHyp _ idx => do
      let some γ := n.intro | throwError "node {a} applies a local clause but has no introducing node"
      let some fs := (← get).nodeFVars[γ]? | throwError "introducing node {γ} of node {a} was not replayed"
      pure fs[idx]!
    | .global c => do
      let info ← getConstInfo c
      let us ← info.levelParams.mapM fun _ => mkFreshLevelMVar
      for (v, u) in cinfo.levelVars.zip us.toArray do
        modify fun s => { s with slotLevels := s.slotLevels.push ((a, v), u) }
      pure (mkConst c us)
    | .builtin _ => throwError "internal: a built-in rule has no head term"
  -- the statement as compiled: a constant's type is preprocessed (levels normalised with
  -- its own parameter names) before its parameters become level metavariables
  let mut T ← match cinfo.origin with
    | .global c => do
      let info ← getConstInfo c
      let .const _ us := head | throwError "internal: constant expected"
      pure ((← preprocess info.type).instantiateLevelParams info.levelParams us)
    | _ => do preprocess (← inferType head)
  let mut e := head
  let mut prems : Array (Option Expr) := Array.replicate cl.prems.size none
  let mut vmap : Std.HashMap String Expr := {}
  for st in cinfo.steps do
    match st with
    | .binders uses =>
      let (mvs, _, body) ← forallMetaTelescopeReducing T (some uses.size)
      unless mvs.size == uses.size do throwError "clause {cl.name} has fewer than {uses.size} binders here"
      e := mkAppN e mvs
      T := body
      for (u, mv) in uses.zip mvs do
        match u with
        | .static b =>
          modify fun s => { s with slotMVars := s.slotMVars.push ((a, b), mv) }
          vmap := vmap.insert b mv
        | .prem j =>
          -- a premise is filled only by its child. The clause's head may mention the premise
          -- (a proof inside a term, compiled to `⟨proof⟩`), and unifying it with the target
          -- would otherwise assign the premise to the target's proof before the child is
          -- replayed. As synthetic opaque, it is compared by proof irrelevance instead, which
          -- still unifies its type. (Full run of 7b, `List.getLast_eq_head_reverse`.)
          mv.mvarId!.setKind .syntheticOpaque
          prems := prems.set! j (some mv)
        | .hyp => throwError "internal: a clause binder marked as a hypothesis"
    | .andLeft | .andRight =>
      let some (A, B) := binApp? ``And T | throwError "clause {cl.name}: {T} is not a conjunction"
      let left := st matches .andLeft
      e := mkApp3 (mkConst (if left then ``And.left else ``And.right)) A B e
      T := if left then A else B
    | .iffMp j | .iffMpr j =>
      let some (A, B) := binApp? ``Iff T | throwError "clause {cl.name}: {T} is not an iff"
      let mp := st matches .iffMp _
      let p ← mkFreshExprMVar (if mp then A else B) (kind := .syntheticOpaque)
      e := mkApp4 (mkConst (if mp then ``Iff.mp else ``Iff.mpr)) A B e p
      T := if mp then B else A
      prems := prems.set! j (some p)
    | .propEq | .propEqSymm =>
      -- M9_PLAN 2.1: `propext : (A ↔ B) → A = B` (`{a b : Prop}`), and `Eq.symm` of it
      -- (`Eq.symm.{u} {α : Sort u} {a b : α}`, here at `α := Prop`, `u := 1`)
      let some (A, B) := binApp? ``Iff T | throwError "clause {cl.name}: {T} is not an iff"
      let pe := mkApp3 (mkConst ``propext) A B e
      if st == .propEq then
        e := pe
        T := mkPropEq A B
      else
        e := mkApp4 (mkConst ``Eq.symm [Level.one]) (mkSort Level.zero) A B pe
        T := mkPropEq B A
  let premMVs ← prems.mapIdxM fun j p? => match p? with
    | some p => pure p
    | none => throwError "clause {cl.name}: premise {j} was never opened"
  return (e, T, premMVs, vmap)

mutual
/-- Replay the children of node `a`: each premise on its metavariable, and each data
position that has a child on the metavariable of its variable. -/
partial def replayChildren (C : Compiled) (sk : Array SkelNode) (a : Nat) (prems : Array Expr)
    (vmap : Std.HashMap String Expr) : DecodeM Unit := do
  let n := sk[a]!
  let cl := C.forest.clauses[n.clause]!
  for h : j in [0:prems.size] do
    let some β := n.children[j]? | throwError "node {a} has no child for premise {j}"
    replay C sk β prems[j].mvarId!
  for ((b, _), β?) in cl.dataPos.zip n.dataChildren do
    let some β := β? | continue
    let some mv := vmap[b]? | throwError "node {a}: no metavariable for the built variable {b}"
    replayData C sk β mv

/-- Replay a proof node on the metavariable `m` of its goal. -/
partial def replay (C : Compiled) (sk : Array SkelNode) (a : Nat) (m : MVarId) : DecodeM Unit := do
  let n := sk[a]!
  let ginfo := C.goalInfo[n.goal]!
  let cinfo := C.clauseInfo[n.clause]!
  let cl := C.forest.clauses[n.clause]!
  let (fvs, m') ← m.introN ginfo.binders.size
  modify fun s => { s with nodeFVars := s.nodeFVars.insert a (fvs.map mkFVar) }
  let (prems, vmap) ← m'.withContext do
    let tgt ← instantiateMVars (← m'.getType)
    if let .builtin k := cinfo.origin then
      let (pf, prems) ← replayBuiltin k tgt a cl.vars
      m'.assign pf
      modify fun s => { s with nodeTarget := s.nodeTarget.insert a tgt, nodeHead := s.nodeHead.insert a tgt }
      -- the witness of `Exists.intro` is the only variable of a built-in rule
      let st ← get
      let vmap := cl.vars.foldl (fun (m : Std.HashMap String Expr) b =>
        match st.slotMVars.find? (·.1 == (a, b)) with
        | some (_, mv) => m.insert b mv
        | none => m) {}
      return (prems, vmap)
    let (e, T, prems, vmap) ← instantiateClause C n
    unless ← withTransparency .reducible (isDefEq T tgt) do
      throwError "node {a}: the head {T} of {cl.name} does not unify with the target {tgt}"
    m'.assign e
    modify fun s => { s with nodeTarget := s.nodeTarget.insert a tgt, nodeHead := s.nodeHead.insert a T }
    return (prems, vmap)
  replayChildren C sk a prems vmap

/-- Replay a data node (SPEC §6.9) that builds the value of the variable metavariable `mv`:
apply the data clause, unify its result type with the variable's type and its value with
the variable. -/
partial def replayData (C : Compiled) (sk : Array SkelNode) (a : Nat) (mv : Expr) : DecodeM Unit := do
  let n := sk[a]!
  let cl := C.forest.clauses[n.clause]!
  unless C.clauseInfo[n.clause]!.isData do
    throwError "node {a} is on a data position but applies {cl.name}, which is not a data clause"
  modify fun s => { s with nodeFVars := s.nodeFVars.insert a #[] }
  let (prems, vmap) ← mv.mvarId!.withContext do
    let tgt ← instantiateMVars (← inferType mv)
    let (e, T, prems, vmap) ← instantiateClause C n
    unless ← withTransparency .reducible (isDefEq T tgt) do
      throwError "node {a}: the result type {T} of {cl.name} does not unify with the type {tgt}"
    unless ← isDefEq mv e do
      throwError "node {a}: the value {e} built by {cl.name} does not unify with {← instantiateMVars mv}"
    modify fun s => { s with nodeTarget := s.nodeTarget.insert a tgt, nodeHead := s.nodeHead.insert a T,
                             nodeValue := s.nodeValue.insert a e }
    return (prems, vmap)
  replayChildren C sk a prems vmap
end

/-- Paths (from the atom) at which the template `tmpl` has the subterm `t`. -/
partial def occurrences (t tmpl : Term) : Array (Array Nat) :=
  go tmpl #[] (top := true)
where
  go (u : Term) (path : Array Nat) (top : Bool) : Array (Array Nat) :=
    let here := if !top && u == t then #[path] else #[]
    let args := u.args
    (Array.range args.size).foldl (fun acc i => acc ++ go args[i]! (path.push i) false) here

/-- The possible expressions of a grounding candidate, read from the replayed nodes. A
ground term uses its closed representative if it has one; otherwise (it contains a proof
that mentions a hypothesis, or a variable bound around it) every occurrence of the term
in a replayed target or head is offered, and the caller keeps the first one that is in
scope and well typed. Proofs are irrelevant, so any occurrence is a correct value. -/
def candidateExprs (C : Compiled) (sk : Array SkelNode) (o : Obj) : DecodeM (Array Expr) := do
  match o with
  | .ground t =>
    if let some e := C.groundExprs[t]? then return #[e]
    let st ← get
    let mut out := #[]
    for n in sk do
      let sides := #[(C.forest.goals[n.goal]!.tgt, st.nodeTarget[n.node]?),
                     (C.forest.clauses[n.clause]!.head, st.nodeHead[n.node]?)]
      for (tmpl, base?) in sides do
        let some base := base? | continue
        for path in occurrences t tmpl do
          let v ← navigate base path
          unless v.hasLooseBVars do out := out.push v
    if out.isEmpty then throwError "the ground term {t} occurs in no replayed node"
    return out
  | .slot β _ b =>
    let some n := sk[β]? | throwError "candidate {repr o} is at an unused node"
    let some idx := C.goalInfo[n.goal]!.binders.findIdx? (· == .static b)
      | throwError "candidate {repr o}: {b} is not a binder of the goal position of node {β}"
    let some fs := (← get).nodeFVars[β]? | throwError "node {β} was not replayed"
    return #[fs[idx]!]
  | .rigid β side _ path _ _ =>
    let st ← get
    let base := match side with
      | .goal => st.nodeTarget[β]?
      | .clause => st.nodeHead[β]?
    let some base := base | throwError "candidate {repr o} is at a node that was not replayed"
    return #[← navigate base path]
  | .trigid .. => throwError "internal: a type-template object is never a grounding candidate"
  | .value β _ path _ _ =>
    let some v := (← get).nodeValue[β]? | throwError "value candidate {repr o} is at a node that built nothing"
    return #[← navigate v path (atom := false)]

/-- Prefix of the error for a decoder failure caused by a grounding candidate whose type,
or whose variable's type, the encoder could not compile ("unknown"): no typing clause
constrained that pair (SPEC §6.8; NOTES.md, milestone 4). Not reported as a bug. -/
def limitationPrefix : String := "solve_by_sat: documented limitation"

/-- Assign every clause-variable metavariable that unification left open, from the
model's groundness witnesses. Repeats until nothing changes: a candidate's value may
itself contain open metavariables (another grounded variable), which a later round
assigns; the rank order of the model makes this terminate. Level variables are grounded
the same way from level candidates. -/
def groundOpen (C : Compiled) (E : Encoding) (sk : Array SkelNode) (model : Array Bool) : DecodeM Unit := do
  let mut progress := true
  while progress do
    progress := false
    for ((a, b), mv) in (← get).slotMVars do
      if ← mv.mvarId!.isAssigned then continue
      let c := sk[a]!.clause
      let some cands := E.sv[(a, c, b)]? | throwError "no groundness witnesses for {b} at node {a}"
      let some (o, _, typed) := cands.find? fun (_, sv, _) => BLit.eval model sv
        | throwError "no true groundness witness for {b} at node {a}"
      let vs ← candidateExprs C sk o
      let mut done := false
      let mut lastErr : MessageData := m!""
      for v in vs do
        let v ← instantiateMVars v
        if v.getAppFn.isMVar && v.getAppFn == mv then continue
        -- in the variable's own local context, so its scope is what the unifier checks
        let saved ← (Meta.saveState : MetaM _)
        try
          mv.mvarId!.withContext do
            let mty ← inferType mv
            let vty ← try inferType v catch _ =>
              throwError "grounding of {b} at node {a} to {v} mentions a variable out of its scope"
            unless ← isDefEq mty vty do
              throwError "ill-typed grounding of {b} at node {a}: the model gives {v} : {vty}, the variable has type {mty}"
            unless ← isDefEq mv v do
              throwError "grounding of {b} at node {a} to {v} was rejected by the unifier (scope or occurs)"
          done := true
          break
        catch ex =>
          (saved.restore : MetaM Unit)
          lastErr := ex.toMessageData
      if done then progress := true
      else if !vs.isEmpty && !(← mv.mvarId!.isAssigned) then
        unless (vs.any fun v => v.getAppFn == mv) do
          if typed then throwError lastErr
          throwError "{limitationPrefix} (NOTES.md, milestone 4): the model grounds {b} at node {a} \
            to a candidate whose type, or the variable's type, is unknown to the encoder, so no \
            typing clause applied to the pair; Lean rejects it: {lastErr}"
    for ((a, v), u) in (← get).slotLevels do
      let u ← instantiateLevelMVars u
      unless u.hasMVar do continue
      let c := sk[a]!.clause
      let some cands := E.sv[(a, c, v)]? | throwError "no groundness witnesses for level {v} at node {a}"
      let some (o, _, _) := cands.find? fun (_, sv, _) => BLit.eval model sv
        | throwError "no true groundness witness for level {v} at node {a}"
      let l ← match o with
        | .ground t => match termToLevel? t with
          | some l => pure l
          | none => throwError "level candidate {t} is not a level"
        | .rigid β side _ path _ _ =>
          let st ← get
          let some base := (match side with | .goal => st.nodeTarget[β]? | .clause => st.nodeHead[β]?)
            | throwError "level candidate {repr o} is at a node that was not replayed"
          navigateLevel base path
        | _ => throwError "level candidate {repr o} is not a level object"
      let l ← instantiateLevelMVars l
      if l == u then continue
      unless ← isLevelDefEq u l do
        throwError "grounding of level {v} at node {a} to {l} was rejected"
      progress := true

/-- Decode a model into a proof of the preprocessed goal type.

The unifier runs with the approximations a tactic gets from the elaborator (`foApprox`,
`ctxApprox`), whatever the caller's configuration. Without `ctxApprox`, a clause variable
created under a hypothesis that a node introduced cannot be the value of a variable from
outside that node, even when its own value will be in scope (and the encoder's scope
clauses, SPEC §6.7, say it will). The decoder then failed on a satisfiable CNF when called
from a bare `MetaM`, as the evaluation harness does, but not from the tactic. (Full run of
7b, `Nat.pred_eq_self_iff`; see NOTES.md.) -/
def decode (C : Compiled) (E : Encoding) (model : Array Bool) : MetaM Expr :=
  withConfig (fun c => { c with foApprox := true, ctxApprox := true }) do
  let sk ← match readSkeleton C.forest E.vars model with
    | .ok sk => pure sk
    | .error e => throwError "solve_by_sat: decoder failed on a satisfiable CNF (bug): {e}"
  let shown := renderSkeleton C.forest sk 0
  try
    let root ← mkFreshExprMVar C.goalType
    let go : DecodeM Expr := do
      replay C sk 0 root.mvarId!
      groundOpen C E sk model
      instantiateMVars root
    let (t, _) ← go.run {}
    if t.hasMVar then
      throwError "metavariables remain in the decoded term {t}"
    Meta.check t
    return t
  catch ex =>
    if (← ex.toMessageData.toString).startsWith limitationPrefix then
      throwError "{ex.toMessageData}\nskeleton: {shown}"
    throwError "solve_by_sat: decoder failed on a satisfiable CNF (bug).\nskeleton: {shown}\nerror: {ex.toMessageData}"

end SolveBySat
