/-
Milestone 7d-1: corpus annotations computed from the corpus and the environment alone
(the tactic is not run).

  eval_numerals numerals <out.jsonl>   rule 4 of EVAL_PLAN §3.3, exactly as fixed in
                                       NOTES.md "7d-1: rule 4 … made exact"
  eval_numerals hcompile <out.jsonl>   for every goal: does the compiler accept the goal,
                                       and each H constant on its own (`compile goal [c]`)?
                                       H_main for all goals, H_full for the R1b sample. The
                                       full run records this for every goal except the 1,375
                                       crashes; this recomputes it, and `eval/report.py`
                                       checks it against the recorded results.

Both are deterministic (goals in corpus order). Run under `Test/capped.sh`.
-/
import Lean
import SolveBySat
import Test.EvalCommon

open Lean Meta SolveBySat Eval

unsafe def importEnv (mods : Array Name) : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules (mods.map fun m => { module := m }) {} (loadExts := true)

def runMeta {α} (env : Environment) (hb : Nat) (x : MetaM α) : IO α := do
  let ctx : Core.Context := { fileName := "<eval>", fileMap := default, maxHeartbeats := hb * 1000 }
  let (a, _) ← (x.run' {} {}).toIO ctx { env }
  return a

def jStr (s : String) : Json := Json.str s
def ppS (e : Expr) : MetaM String := do
  return ((toString (← ppExpr e)).take 300).toString

/-! ## Rule 4 -/

def isNumeral (e : Expr) : Bool :=
  e.isAppOf ``OfNat.ofNat || (match e with | .lit (.natVal _) => true | _ => false)

/-- SPEC 2.2 syntactic equality up to proof irrelevance. Returns the first differing pair in
a simultaneous pre-order traversal, and whether a numeral is on the path to it (on either
side), or `none` if equal. -/
partial def firstDiff (a b : Expr) (numPath : Bool) : MetaM (Option (Expr × Expr × Bool)) := do
  let np := numPath || isNumeral a || isNumeral b
  if a == b then return none
  if (← isProofSafe a) && (← isProofSafe b) then return none
  match a, b with
  | .app .., .app .. =>
    let fa := a.getAppFn
    let fb := b.getAppFn
    let xs := a.getAppArgs
    let ys := b.getAppArgs
    if xs.size != ys.size then return some (a, b, np)
    -- differing heads (kinds, constants, levels, fvars) make the applications the pair
    if fa.isConst || fb.isConst || fa.isFVar || fb.isFVar || fa.isBVar || fb.isBVar then
      if fa != fb then return some (a, b, np)
    else
      if let some d ← firstDiff fa fb np then return some d
    for i in [0:xs.size] do
      if let some d ← firstDiff xs[i]! ys[i]! np then return some d
    return none
  | .forallE n d₁ b₁ bi, .forallE _ d₂ b₂ _ | .lam n d₁ b₁ bi, .lam _ d₂ b₂ _ =>
    if (a.isForall != b.isForall) then return some (a, b, np)
    if let some d ← firstDiff d₁ d₂ np then return some d
    withLocalDecl n bi d₁ fun x => firstDiff (b₁.instantiate1 x) (b₂.instantiate1 x) np
  | .proj s₁ i₁ e₁, .proj s₂ i₂ e₂ =>
    if s₁ != s₂ || i₁ != i₂ then return some (a, b, np)
    firstDiff e₁ e₂ np
  | .mdata _ x, _ => firstDiff x b numPath
  | _, .mdata _ y => firstDiff a y numPath
  | _, _ => return some (a, b, np)

structure NumSt where
  visited : Nat := 0
  cut : Bool := false
  checked : Nat := 0
  skipped : Nat := 0
  firstNum : Option Json := none
  firstAny : Option Json := none
  /-- up to 6 mismatches, for the `inspect` mode -/
  all : Array Json := #[]

abbrev NumM := StateRefT NumSt MetaM

/-- Compare expected `A` with inferred `T` at one checked position. -/
def checkPos (A T : Expr) : NumM Unit := do
  modify fun s => { s with checked := s.checked + 1 }
  let A ← preprocess A
  let T ← preprocess T
  match ← firstDiff A T false with
  | none => pure ()
  | some (x, y, num) =>
    let j := Json.mkObj [("expected", jStr (← ppS A)), ("inferred", jStr (← ppS T)),
      ("at_expected", jStr (← ppS x)), ("at_inferred", jStr (← ppS y))]
    let s ← get
    if s.all.size < 6 then set { s with all := s.all.push (j.mergeObj (Json.mkObj [("numeral", toJson num)])) }
    let s ← get
    if s.firstAny.isNone then set { s with firstAny := some j }
    if num && (← get).firstNum.isNone then modify fun s => { s with firstNum := some j }

/-- The 7a walker's traversal, checking every proof argument of every application. -/
partial def walkNum (e : Expr) : NumM Unit := do
  if (← get).visited ≥ walkBudget then
    modify fun s => { s with cut := true }
    return
  modify fun s => { s with visited := s.visited + 1 }
  match e with
  | .lam n t b bi => withLocalDecl n bi t fun x => walkNum (b.instantiate1 x)
  | .letE _ _ v b _ => walkNum v; walkNum (b.instantiate1 v)
  | .mdata _ b | .proj _ _ b => walkNum b
  | .app .. =>
    let f := e.getAppFn
    let args := e.getAppArgs
    -- expected types of the arguments, from the head's type
    let fty? ← try some <$> inferType f catch _ => pure none
    let mut ty? := fty?
    for a in args do
      let mut exp? : Option Expr := none
      if let some ty := ty? then
        let ty ← (if ty.isForall then pure ty else (try whnf ty catch _ => pure ty))
        match ty with
        | .forallE _ d b _ => exp? := some d; ty? := some (b.instantiate1 a)
        | _ => ty? := none
      if ← isProofSafe a then
        match exp? with
        | some A =>
          let ok ← tryCatchRuntimeEx (do checkPos A (← inferType a); pure true) (fun _ => pure false)
          unless ok do modify fun s => { s with skipped := s.skipped + 1 }
        | none => modify fun s => { s with skipped := s.skipped + 1 }
    match f with
    | .const .. | .fvar .. => pure ()
    | _ => walkNum f
    for a in args do walkNum a
  | _ => pure ()

/-- Rule 4 for one goal: oracle term `p`, the goal's closed type `g`. -/
def rule4 (p g : Expr) : MetaM Json := do
  let act : NumM Unit := do
    let ok ← tryCatchRuntimeEx (do checkPos g (← inferType p); pure true) (fun _ => pure false)
    unless ok do modify fun (s : NumSt) => { s with skipped := s.skipped + 1 }
    walkNum p
  let ((), s) ← act.run {}
  return Json.mkObj [("rule4", toJson s.firstNum.isSome), ("mismatch_any", toJson s.firstAny.isSome),
    ("checked", toJson s.checked), ("skipped", toJson s.skipped), ("cut", toJson s.cut),
    ("first_numeral_mismatch", s.firstNum.getD Json.null),
    ("first_mismatch", s.firstAny.getD Json.null)]

/-! ## Corpus access -/

def readCorpus (tier : String) : IO (Array Json) := do
  let ls := (← IO.FS.readFile s!"eval/corpus_{tier}.jsonl").splitOn "\n" |>.filter (· != "")
  let js ← ls.toArray.mapM fun l => IO.ofExcept (Json.parse l)
  return js.filter fun j => !(j.getObjVal? "header").toBool

def nameTable (env : Environment) : Std.HashMap String Name :=
  env.constants.fold (fun m n _ => m.insert n.toString n) {}

def appendLine (h : IO.FS.Handle) (j : Json) : IO Unit := do
  h.putStr (j.compress ++ "\n"); h.flush

/-- For every goal of both tiers in corpus order: (record, oracle term, closed goal). Tier B
candidates are closed terms, so one walk per theorem serves all its goals. -/
def forGoals (env : Environment) (names : Std.HashMap String Name)
    (k : Json → Expr → Expr → MetaM Json) (out : IO.FS.Handle) : IO Unit := do
  for tier in ["A", "B"] do
    let recs ← readCorpus tier
    let mut cache : Name × Array (Expr × Expr × Nat) := (.anonymous, #[])
    let mut n := 0
    for r in recs do
      let id := (r.getObjValAs? String "id").toOption.getD ""
      let some thm := names[(r.getObjValAs? String "thm").toOption.getD ""]?
        | throw (IO.userError s!"{id}: unknown theorem")
      if tier == "B" && cache.1 != thm then
        cache := (thm, ← runMeta env 400000 (do return (← candidates thm).1))
      let cands := cache.2
      let res ← (runMeta env 400000 do
        let some (.thmInfo t) := (← getEnv).find? thm | throwError "not a theorem"
        if tier == "A" then k r t.value t.type
        else
          let pos := (r.getObjValAs? Nat "pos").toOption.getD 0
          let some (g, p, _) := cands[pos]? | throwError "no candidate {pos}"
          k r p g).toBaseIO
      let j := match res with
        | .ok j => j
        | .error e => Json.mkObj [("error", jStr (toString e))]
      appendLine out (Json.mkObj [("id", jStr id)] |>.mergeObj j)
      n := n + 1
      if n % 500 == 0 then IO.eprintln s!"{tier}: {n}"

/-! ## H acceptance -/

def hcompile (H : Array Name) (g : Expr) : MetaM Json := do
  let msg := fun (e : Exception) => do return (← e.toMessageData.toString)
  let goalOk ← try discard <| compile g #[]; pure none catch e => some <$> msg e
  if let some m := goalOk then
    return Json.mkObj [("goal_rejected", jStr m)]
  let mut acc := #[]
  let mut rej := #[]
  for c in H do
    try discard <| compile g #[c]; acc := acc.push (jStr c.toString)
    catch e => rej := rej.push (Json.arr #[jStr c.toString, jStr (← msg e)])
  return Json.mkObj [("accepted", Json.arr acc), ("rejected", Json.arr rej)]

def namesOf (names : Std.HashMap String Name) (r : Json) (field : String) : Array Name :=
  ((r.getObjValAs? (Array String) field).toOption.getD #[]).filterMap (names[·]?)

/-! ## Inspection of single goals (7d-1 hand reviews) -/

/-- All mismatches (≤ 6) of a term `p` against the closed goal `g`, by the rule 4 check. -/
def mismatches (p g : Expr) : MetaM (Array Json × Nat) := do
  let act : NumM Unit := do
    let ok ← tryCatchRuntimeEx (do checkPos g (← inferType p); pure true) (fun _ => pure false)
    unless ok do modify fun (s : NumSt) => { s with skipped := s.skipped + 1 }
    walkNum p
  let ((), s) ← act.run {}
  return (s.all, s.checked)

/-- Like-for-like `solve_by_elim` as in the harness (`Test/EvalRun.lean`, §10.5 decision 3):
H alone with the local hypotheses, `symm`/`exfalso` off, depth 10, 200,000 heartbeats. Returns
the closed proof term, or the outcome. -/
def sbeLike (goal : Expr) (nctx : Nat) (H : Array Name) : MetaM (Except String Expr) := do
  let cfg : SolveByElim.SolveByElimConfig := { maxDepth := 10, symm := false, exfalso := false }
  tryCatchRuntimeEx
    (withTheReader Core.Context (fun c => { c with maxHeartbeats := 200000 * 1000 }) <| withCurrHeartbeats do
      let m ← mkFreshExprMVar goal
      let (_, g) ← m.mvarId!.introNP nctx
      g.withContext do
        let ⟨_, ctx⟩ ← SolveByElim.mkAssumptionSet false false [] [] #[]
        let lemmas := H.toList.map (fun c => (mkConstWithFreshMVarLevels c : Elab.TermElabM Expr))
        let rest ← SolveByElim.solveByElim cfg lemmas ctx [g]
        let t ← instantiateMVars m
        if rest.isEmpty && !t.hasExprMVar then return .ok t else return .error "open")
    fun e => do
      if e.isMaxHeartbeat then return .error "heartbeats"
      if e.isMaxRecDepth then return .error "max_rec_depth"
      return .error s!"failed: {((← e.toMessageData.toString).take 150).toString}"

/-- The heads of the proof nodes of `p` (proof-valued spines headed by a constant or a local
hypothesis, as in the node estimate), each with what it is: `H` (in H), `builtin`, a §2.3
drop reason, or `hyp` (a local hypothesis, with its user name). -/
partial def proofHeads (H : Array Name) (e : Expr) (acc : IO.Ref (Array (String × String))) : MetaM Unit := do
  match e with
  | .lam n t b bi => withLocalDecl n bi t fun x => proofHeads H (b.instantiate1 x) acc
  | .letE _ _ v b _ => proofHeads H v acc; proofHeads H (b.instantiate1 v) acc
  | .mdata _ b | .proj _ _ b => proofHeads H b acc
  | .const .. | .fvar .. | .app .. =>
    let f := e.getAppFn
    if (f.isConst || f.isFVar) && (← Eval.isProofSafe e) then
      match f with
      | .const c _ =>
        let k ← if H.contains c then pure "H" else classifyH c
        acc.modify (·.push (c.toString, k))
      | .fvar fv => acc.modify (·.push (s!"{(← fv.getDecl).userName}", "hyp"))
      | _ => pure ()
    match f with
    | .const .. | .fvar .. => pure ()
    | _ => proofHeads H f acc
    for a in e.getAppArgs do proofHeads H a acc
  | _ => pure ()

def inspectGoal (spec : Json) (names : Std.HashMap String Name) (withSbe : Bool) : MetaM Json := do
  let get := fun (f : String) => (spec.getObjValAs? String f).toOption.getD ""
  let some thm := names[get "thm"]? | throwError "unknown theorem"
  let some (.thmInfo t) := (← getEnv).find? thm | throwError "not a theorem"
  let H := ((spec.getObjValAs? (Array String) "H").toOption.getD #[]).filterMap (names[·]?)
  let (g, p, nctx) ← if get "tier" == "A" then pure (t.type, t.value, 0) else do
    let pos := (spec.getObjValAs? Nat "pos").toOption.getD 0
    let some c := (← candidates thm).1[pos]? | throwError "no candidate"
    pure c
  let (om, ochecked) ← mismatches p g
  let acc ← IO.mkRef #[]
  proofHeads H p acc
  let heads := (← acc.get).map fun (c, k) => Json.arr #[jStr c, jStr k]
  let mut accH := #[]
  for c in H do
    if ← (try discard <| compile g #[c]; pure true catch _ => pure false) then accH := accH.push c
  let notes ← try (do
      let C ← compile g accH
      C.notes.mapM fun m => do return jStr ((← m.toString).take 200).toString)
    catch e => pure #[jStr s!"(compile with H failed: {((← e.toMessageData.toString).take 120).toString})"]
  let mut fields : List (String × Json) := [("key", spec.getObjValD "key"), ("goal", jStr ((toString (← ppExpr g)).take 400).toString),
    ("oracle", jStr ((toString (← ppExpr p)).take 700).toString), ("oracle_checked", toJson ochecked),
    ("oracle_mismatches", Json.arr om), ("oracle_heads", Json.arr heads), ("dropped_hyps", Json.arr notes)]
  if withSbe then
    match ← sbeLike g nctx H with
    | .ok sp =>
      let (sm, schecked) ← mismatches sp g
      fields := fields ++ [("sbe", jStr ((toString (← ppExpr sp)).take 700).toString), ("sbe_checked", toJson schecked),
        ("sbe_mismatches", Json.arr sm)]
    | .error e => fields := fields ++ [("sbe", jStr s!"({e})")]
  return Json.mkObj fields

/-- The compiled forest of one goal with its accepted H (debugging the reviews). -/
def forestOf (spec : Json) (names : Std.HashMap String Name) : MetaM Json := do
  let get := fun (f : String) => (spec.getObjValAs? String f).toOption.getD ""
  let some thm := names[get "thm"]? | throwError "unknown theorem"
  let some (.thmInfo t) := (← getEnv).find? thm | throwError "not a theorem"
  let H := ((spec.getObjValAs? (Array String) "H").toOption.getD #[]).filterMap (names[·]?)
  let g ← if get "tier" == "A" then pure t.type else do
    let pos := (spec.getObjValAs? Nat "pos").toOption.getD 0
    let some c := (← candidates thm).1[pos]? | throwError "no candidate"
    pure c.1
  let mut accH := #[]
  for c in H do
    if ← (try discard <| compile g #[c]; pure true catch _ => pure false) then accH := accH.push c
  let C ← compile g accH
  let F := C.forest
  let goals := F.goals.mapIdx fun i gp => jStr s!"g{i}: tgt {gp.tgt}  eig {gp.eig}  hyps {gp.hyps}  types {gp.tgtTypes.map fun (p, t) => s!"{p}:{t.map toString}"}"
  let cls := F.clauses.mapIdx fun i c => jStr s!"c{i} {c.name}: head {c.head}  vars {c.vars}  prems {c.prems}  local {c.localOf}  builtin {c.builtin}  data {c.dataVal.map toString}  types {c.headTypes.map fun (p, t) => s!"{p}:{t.map toString}"}"
  return Json.mkObj [("key", spec.getObjValD "key"), ("goals", Json.arr goals), ("clauses", Json.arr cls),
    ("varTypes", jStr s!"{F.varTypes.map fun (v, t) => s!"{v}:{t.map toString}"}"),
    ("groundTypes", Json.arr (F.groundTypes.map fun (t, ty) => jStr s!"{t} : {ty.map toString}")),
    ("notes", Json.arr (← C.notes.mapM fun m => do return jStr (← m.toString)))]

/-- Encode and solve one goal at node bound `N` under the run's options, with the static typing
filter off, and with every type template forgotten (the tactic's `forgetTypes` testing option).
Library `encode` and `runSolver`, unchanged. -/
def diag (spec : Json) (names : Std.HashMap String Name) (N : Nat) : MetaM Json := do
  let get := fun (f : String) => (spec.getObjValAs? String f).toOption.getD ""
  let some thm := names[get "thm"]? | throwError "unknown theorem"
  let some (.thmInfo t) := (← getEnv).find? thm | throwError "not a theorem"
  let H := ((spec.getObjValAs? (Array String) "H").toOption.getD #[]).filterMap (names[·]?)
  let g ← if get "tier" == "A" then pure t.type else do
    let pos := (spec.getObjValAs? Nat "pos").toOption.getD 0
    let some c := (← candidates thm).1[pos]? | throwError "no candidate"
    pure c.1
  let mut accH := #[]
  for c in H do
    if ← (try discard <| compile g #[c]; pure true catch _ => pure false) then accH := accH.push c
  let C ← compile g accH
  let mut out := #[]
  for (name, F, o) in [("as run", C.forest, ({} : EncodeOptions)),
                       ("static typing off", C.forest, ({ staticTyping := false } : EncodeOptions)),
                       ("types forgotten", C.forest.forgetTypes, ({} : EncodeOptions))] do
    let E := encode F N o
    let r ← runSolver E.cnf
    let sk := match r with
      | .sat m => match readSkeleton F E.vars m with
        | .ok sk => renderSkeleton F sk 0
        | .error e => s!"(skeleton: {e})"
      | .unsat => ""
    out := out.push (jStr s!"{name}: {if r.isSat then "SAT " ++ sk else "UNSAT"}")
  return Json.mkObj [("key", spec.getObjValD "key"), ("N", toJson N), ("results", Json.arr out)]

/-! ## Reach of the type-template issue (7d-1 stop): does preprocessing change the inferred
type of some term position of the goal or of an accepted `H_main` constant? -/

structure ScanSt where
  visited : Nat := 0
  hit : Option String := none

partial def scanTerm (e : Expr) : StateRefT ScanSt MetaM Unit := do
  if (← get).hit.isSome || (← get).visited ≥ 5000 then return
  modify fun s => { s with visited := s.visited + 1 }
  match e with
  | .forallE n d b bi | .lam n d b bi =>
    scanTerm d
    withLocalDecl n bi d fun x => scanTerm (b.instantiate1 x)
  | .mdata _ b => scanTerm b
  | .app .. | .const .. | .fvar .. | .proj .. =>
    unless e.hasLooseBVars do
      unless ← Eval.isProofSafe e do
        let ok ← tryCatchRuntimeEx (do
            let T ← instantiateMVars (← inferType e)
            -- `compileType` strips metadata itself; compare what it does not do
            let T ← Core.transform T (pre := fun x => match x with
              | .mdata _ y => return .visit y
              | _ => return .continue)
            let P ← preprocess T
            if P != T then
              -- which step changes it: level normalisation, unfolding, β
              let lv := T.replaceLevel (fun l => some l.normalize)
              let bT ← Core.betaReduce T
              let kind := if lv == P then "levels" else if bT == P then "beta" else "unfolding or mixed"
              let msg := s!"[{kind}] {← ppS e} : {← ppS T}  ⇒  {← ppS P}"
              modify fun s => { s with hit := some msg }
            pure true) (fun _ => pure false)
        discard <| pure ok
    match e with
    | .app .. => for a in e.getAppArgs do scanTerm a
    | .proj _ _ b => scanTerm b
    | _ => pure ()
  | _ => pure ()

def tmplScan (H : Array Name) (g : Expr) : MetaM Json := do
  let mut acc := #[]
  for c in H do
    if ← (try discard <| compile g #[c]; pure true catch _ => pure false) then acc := acc.push c
  let mut exprs := #[(← preprocess g)]
  for c in acc do
    let ci ← getConstInfo c
    exprs := exprs.push (← preprocess ci.type)
  for e in exprs do
    let ((), s) ← (scanTerm e).run {}
    if let some h := s.hit then return Json.mkObj [("affected", toJson true), ("example", jStr h)]
  return Json.mkObj [("affected", toJson false)]

unsafe def main (args : List String) : IO UInt32 := do
  if let ["tmplscan", outPath] := args then
    let env ← importEnv sourceModules
    let names := nameTable env
    let out ← IO.FS.Handle.mk outPath .write
    forGoals env names (fun r _ g => tmplScan (namesOf names r "H_main") g) out
    return 0
  if let "diag" :: nStr :: keys := args then
    let env ← importEnv sourceModules
    let names := nameTable env
    let specs ← ((← IO.FS.readFile "eval/specs_full.jsonl").splitOn "\n").filter (· != "") |>.mapM (IO.ofExcept ∘ Json.parse)
    for k in keys do
      let some sp := specs.find? (·.getObjValD "key" == jStr k) | IO.println s!"unknown key {k}"; continue
      match ← (runMeta env 0 (diag sp names nStr.toNat!)).toBaseIO with
      | .ok j => IO.println j.compress
      | .error e => IO.println s!"{k}: error {e}"
    return 0
  if let "forest" :: keys := args then
    let env ← importEnv sourceModules
    let names := nameTable env
    let specs ← ((← IO.FS.readFile "eval/specs_full.jsonl").splitOn "\n").filter (· != "") |>.mapM (IO.ofExcept ∘ Json.parse)
    for k in keys do
      let some sp := specs.find? (·.getObjValD "key" == jStr k) | IO.println s!"unknown key {k}"; continue
      match ← (runMeta env 400000 (forestOf sp names)).toBaseIO with
      | .ok j => IO.println (j.pretty 200)
      | .error e => IO.println s!"{k}: error {e}"
    return 0
  if let "inspect" :: withSbe :: keys := args then
    let env ← importEnv sourceModules
    let names := nameTable env
    let specs ← ((← IO.FS.readFile "eval/specs_full.jsonl").splitOn "\n").filter (· != "") |>.mapM (IO.ofExcept ∘ Json.parse)
    for k in keys do
      let some sp := specs.find? (·.getObjValD "key" == jStr k) | IO.println s!"unknown key {k}"; continue
      let r ← (runMeta env 400000 (inspectGoal sp names (withSbe == "sbe"))).toBaseIO
      match r with
      | .ok j => IO.println j.compress
      | .error e => IO.println (Json.mkObj [("key", jStr k), ("error", jStr (toString e))]).compress
    return 0
  match args with
  | [mode, outPath] =>
    let env ← importEnv sourceModules
    let names := nameTable env
    let out ← IO.FS.Handle.mk outPath .write
    match mode with
    | "numerals" =>
      forGoals env names (fun _ p g => rule4 p g) out
    | "hcompile" =>
      let r1b : Std.HashSet String := Std.HashSet.ofList <|
        ((← IO.FS.readFile "eval/specs_full.jsonl").splitOn "\n").filterMap fun l =>
          match Json.parse l with
          | .ok j => if j.getObjValD "run" == jStr "r1b" then (j.getObjValAs? String "id").toOption else none
          | .error _ => none
      forGoals env names (fun r _ g => do
        let main ← hcompile (namesOf names r "H_main") g
        let id := (r.getObjValAs? String "id").toOption.getD ""
        if r1b.contains id then
          return Json.mkObj [("main", main), ("r1b", ← hcompile (namesOf names r "H_full") g)]
        return Json.mkObj [("main", main)]) out
    | _ => IO.println "usage: eval_numerals numerals|hcompile <out>"; return 2
    return 0
  | _ => IO.println "usage: eval_numerals numerals|hcompile <out>"; return 2
