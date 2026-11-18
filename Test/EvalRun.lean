/-
Milestone 7b: the coverage harness (EVAL_PLAN §3.1, §3.2, §5, §10.3, §10.4).

  eval_run run <specs.jsonl> <results.jsonl> <started.jsonl> <warmup.jsonl>
  eval_run verify-removed <name…>

One process is one shard: it imports `Init` + `Std` (and `Test.EvalNamed` for the named
tests), skips specs whose key is already in `results.jsonl`, and for each remaining spec
appends a "started" line, runs the goal, and appends one result line. Exit codes: 0 done;
3 a decoder bug (stops the run); 4 a harness error (stops the run). Crashes (OOM, the
300 s watchdog) are recorded by `Test/eval_driver.py`, which runs the shards under the
cgroup cap.

The harness does not change what the encoder or decoder accept: it calls `compile`,
`encode` and `decode` of the library with the tactic's default options. Only the solver
call is its own, to add CaDiCaL's time limit (`-t`) and measure the solver's memory.
-/
import Lean
import SolveBySat
import Test.EvalCommon

open Lean Meta SolveBySat Eval

/-! ## Fixed limits (pre-registered, NOTES.md milestone 7) -/

def nMax : Nat := 10
def solverSeconds : Nat := 20
def loopSeconds : Nat := 120
def baselineHeartbeats : Nat := 200000
def sbeDepth : Nat := 10

/-! ## Process utilities -/

unsafe def importEnv (mods : Array Name) : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot) [".lake/build/lib/lean"]
  importModules (mods.map fun m => { module := m }) {} (loadExts := true)

/-- `VmRSS` and `VmHWM` of this process, in MB. -/
def memMB : IO (Nat × Nat) := do
  let s ← IO.FS.readFile "/proc/self/status"
  let get := fun (k : String) => Id.run do
    for l in s.splitOn "\n" do
      if l.startsWith k then
        let digits := (l.drop k.length).toString.toList.filter Char.isDigit
        return (String.ofList digits).toNat! / 1024
    return 0
  return (get "VmRSS:", get "VmHWM:")

def appendLine (path : System.FilePath) (line : String) : IO Unit := do
  let h ← IO.FS.Handle.mk path .append
  h.putStr (line ++ "\n")
  h.flush

def msSince (t0 : Nat) : IO Nat := return (← IO.monoMsNow) - t0

def runMeta {α} (env : Environment) (x : MetaM α) : IO α := do
  -- unlimited heartbeats for solve_by_sat itself (limited by time instead); baselines set
  -- their own budget
  let ctx : Core.Context := { fileName := "<eval>", fileMap := default, maxHeartbeats := 0 }
  let (a, _) ← (x.run' {} {}).toIO ctx { env }
  return a

/-! ## Specs -/

structure Spec where
  key : String
  id : String
  run : String
  tier : String
  thm : Name
  pos : Nat := 0
  nctx : Nat := 0
  H : Array Name
  opts : Array String := #[]
  baselines : Bool
  expect : String := ""

def parseSpec (names : Std.HashMap String Name) (j : Json) : Except String Spec := do
  let name := fun (s : String) => match names[s]? with
    | some n => pure n
    | none => throw s!"unknown constant {s}"
  let H ← (← j.getObjValAs? (Array String) "H").mapM name
  return { key := ← j.getObjValAs? String "key", id := ← j.getObjValAs? String "id",
           run := ← j.getObjValAs? String "run", tier := ← j.getObjValAs? String "tier",
           thm := ← name (← j.getObjValAs? String "thm"),
           pos := (j.getObjValAs? Nat "pos").toOption.getD 0,
           nctx := (j.getObjValAs? Nat "nctx").toOption.getD 0,
           H, opts := (j.getObjValAs? (Array String) "opts").toOption.getD #[],
           baselines := (j.getObjValAs? Bool "baselines").toOption.getD false,
           expect := (j.getObjValAs? String "expect").toOption.getD "" }

/-- The closed goal type and its binder count (the Tier B context). -/
def goalOf (s : Spec) : MetaM (Expr × Nat) := do
  let some ci := (← getEnv).find? s.thm | throwError "unknown {s.thm}"
  match s.tier with
  | "A" => return (ci.type, 0)
  | "B" =>
    let (cands, _) ← candidates s.thm
    let some (g, _, k) := cands[s.pos]? | throwError "{s.id}: no candidate at position {s.pos}"
    unless k == s.nctx do throwError "{s.id}: rebuilt goal has {k} binders, the corpus says {s.nctx}"
    return (g, k)
  | _ =>
    let some v := ci.value? | throwError "{s.thm} has no value"
    return (v, 0)

/-! ## The SAT solver with a time limit -/

inductive SolveRes where
  | sat (m : Array Bool) | unsat | timeout | killed (sig : Int) | error (msg : String)

/-- Run CaDiCaL with `-t limit` through `Test/memrun.py` (peak RSS and wall time). -/
def solveLimited (F : CNF) (limit : Nat) : IO (SolveRes × Float × Nat) := do
  let solver ← findSolver
  let (h, path) ← IO.FS.createTempFile
  try
    h.putStr F.toDimacs
    h.flush
    let args := #["Test/memrun.py", solver, "-q", "-t", toString limit, path.toString]
    let out ← IO.Process.output { cmd := "python3", args }
    -- memrun's last stderr line: "[memrun] peak X MB, wall Y s, status S"
    let some line := (out.stderr.splitOn "\n").reverse.find? (·.startsWith "[memrun]")
      | return (.error s!"no memrun line: {out.stderr}", 0, 0)
    let ws := line.splitOn " "
    let peak := (ws[2]!).toNat!
    let wall := (ws[5]!).toNat?.map (·.toFloat) |>.getD ((ws[5]!.splitOn ".").head!.toNat!.toFloat)
    let wall := match (ws[5]!).splitOn "." with
      | [a, b] => a.toNat!.toFloat + b.toNat!.toFloat / 10.0
      | _ => wall
    let status := (ws[8]!).toInt!
    if status < 0 then return (.killed (-status), wall, peak)
    -- CaDiCaL 2.1.2 at its `-t` limit prints the comment line `c UNKNOWN` and exits 0
    if status == 0 && (out.stdout.splitOn "UNKNOWN").length > 1 then return (.timeout, wall, peak)
    unless status == 10 || status == 20 do
      return (.error s!"solver status {status}: {out.stderr.take 300}", wall, peak)
    match parseSolverOutput F.nVars out.stdout with
    | .error e => return (.error e, wall, peak)
    | .ok .unsat => return (.unsat, wall, peak)
    | .ok (.sat m) =>
      unless F.satisfiedBy m do return (.error "model violates the CNF", wall, peak)
      return (.sat m, wall, peak)
  finally
    IO.FS.removeFile path

/-! ## solve_by_sat: the N loop of §3.1 -/

def jStr (s : String) : Json := Json.str s

def msgOf (e : Exception) : MetaM String := do
  return (← e.toMessageData.toString)

/-- Kernel-check `t : goal` without changing the environment. -/
def kernelCheck (goal t : Expr) : MetaM (Option String) := do
  let lps := (collectLevelParams (collectLevelParams {} goal) t).params
  let decl := Declaration.thmDecl { name := `_eval_kernel_check, levelParams := lps.toList,
                                    type := goal, value := t }
  match (← getEnv).toKernelEnv.addDecl {} decl with
  | .ok _ => return none
  | .error e => return some (← (e.toMessageData {}).toString)

/-- Returns the result object and whether it is a decoder bug. -/
def runSat (goal : Expr) (H : Array Name) (opts : Array String) (progress : Nat → IO Unit) :
    MetaM (Json × Bool) := do
  let t0 ← IO.monoMsNow
  -- 1. the goal
  try discard <| compile goal #[]
  catch e => return (Json.mkObj [("outcome", jStr "goal_rejected"), ("reason", jStr (← msgOf e))], false)
  -- 2. each H constant on its own
  let mut acc := #[]
  let mut rej := #[]
  for c in H do
    try discard <| compile goal #[c]; acc := acc.push c
    catch e => rej := rej.push (Json.arr #[c.toString, ← msgOf e])
  let base := [("H_accepted", Json.arr (acc.map (Json.str ·.toString))), ("H_rejected", Json.arr rej)]
  let C ← try compile goal acc
    catch e => return (Json.mkObj (base ++ [("outcome", jStr "compile_error"), ("reason", jStr (← msgOf e))]), false)
  let C := if opts.contains "forgettypes" then { C with forest := C.forest.forgetTypes } else C
  let eopts : EncodeOptions := { staticTyping := !opts.contains "nostatic" }
  -- 3. N = 1 … Nmax
  let mut log := #[]
  for N in [1:nMax+1] do
    let elapsed ← msSince t0
    if elapsed ≥ loopSeconds * 1000 then
      return (Json.mkObj (base ++ [("outcome", jStr "timeout"), ("N", toJson (N)), ("timeout_kind", jStr "loop"),
        ("per_N", Json.arr log), ("loop_ms", toJson (elapsed))]), false)
    progress N   -- a marker, so that a shard crash records the N it reached
    let te ← IO.monoMsNow
    let E := encode C.forest N eopts
    let nCl := E.cnf.clauses.size   -- forces the encoding
    let encMs ← msSince te
    let remaining := (loopSeconds * 1000 - (← msSince t0)) / 1000
    if remaining == 0 then
      return (Json.mkObj (base ++ [("outcome", jStr "timeout"), ("N", toJson (N)), ("timeout_kind", jStr "loop"),
        ("per_N", Json.arr log), ("loop_ms", toJson (← msSince t0))]), false)
    let limit := min solverSeconds remaining
    -- spawning the solver (or writing its input) can fail with ENOMEM near the cgroup cap:
    -- that is a resource limit, recorded as memout(N, spawn), not a harness error
    let (r, wall, peak) ← match ← (solveLimited E.cnf limit).toBaseIO with
      | .ok r => pure r
      | .error e =>
        if (toString e).contains "error code: 12" then pure (SolveRes.killed 0, 0.0, 0)
        else throwError "solver call failed: {e}"
    let row := fun (res : String) => Json.mkObj [("N", toJson (N)), ("vars", toJson (E.cnf.nVars)), ("clauses", toJson (nCl)),
      ("encode_ms", toJson (encMs)), ("solve_s", toJson wall), ("solver_peak_mb", toJson (peak)), ("result", res)]
    let final := fun (outcome : String) (extra : List (String × Json)) =>
      let fams := Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, Json.num k))
      Json.mkObj (base ++ [("outcome", jStr outcome), ("N", toJson (N)), ("vars", toJson (E.cnf.nVars)),
        ("clauses", toJson (nCl)), ("families", fams), ("encode_ms", toJson (encMs)), ("solve_s", toJson wall),
        ("solver_peak_mb", toJson (peak)), ("per_N", Json.arr (log.push (row outcome)))] ++ extra)
    match r with
    | .unsat =>
      log := log.push (row "unsat")
      -- §3.1 step 4: if every N is UNSAT, the statistics at the final N (= Nmax)
      if N == nMax then
        return (Json.mkObj (base ++ [("outcome", jStr "no_proof_le_Nmax"), ("N", toJson N),
          ("vars", toJson E.cnf.nVars), ("clauses", toJson nCl),
          ("families", Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, Json.num k))),
          ("encode_ms", toJson encMs), ("solve_s", toJson wall), ("solver_peak_mb", toJson peak),
          ("per_N", Json.arr log), ("loop_ms", toJson (← msSince t0))]), false)
    | .timeout =>
      return (final "timeout" [("timeout_kind", jStr (if limit < solverSeconds then "loop" else "solver")),
        ("loop_ms", toJson (← msSince t0))], false)
    | .killed sig =>
      return (final "memout" [("memout_kind", jStr (if sig == 0 then "spawn" else "solver")),
        ("signal", toJson (sig)), ("loop_ms", toJson (← msSince t0))], false)
    | .error msg => return (final "solver_error" [("reason", jStr msg)], true)
    | .sat model =>
      let td ← IO.monoMsNow
      let t? ← try pure (Except.ok (← decode C E model)) catch e => pure (Except.error (← msgOf e))
      let decMs ← msSince td
      match t? with
      | .error msg =>
        if msg.startsWith limitationPrefix then
          return (final "limitation" [("reason", jStr msg), ("decode_ms", toJson (decMs)), ("loop_ms", toJson (← msSince t0))], false)
        return (final "decoder_bug" [("reason", jStr msg)], true)
      | .ok t =>
        let t ← instantiateMVars t
        if t.hasMVar then return (final "decoder_bug" [("reason", jStr "the decoded term has metavariables")], true)
        unless ← isDefEq (← inferType t) goal do
          return (final "decoder_bug" [("reason", jStr "the decoded term does not have the goal type")], true)
        if let some err ← kernelCheck goal t then
          return (final "decoder_bug" [("reason", jStr s!"kernel: {err}")], true)
        let sk := match readSkeleton C.forest E.vars model with
          | .ok sk => renderSkeleton C.forest sk 0
          | .error e => s!"(skeleton: {e})"
        return (final "proved" [("skeleton", jStr sk), ("decode_ms", toJson (decMs)), ("loop_ms", toJson (← msSince t0))], false)
  return (Json.mkObj (base ++ [("outcome", jStr "no_proof_le_Nmax"), ("N", toJson (nMax)), ("per_N", Json.arr log),
    ("loop_ms", toJson (← msSince t0))]), false)

/-! ## Baselines (§3.2, §10.3, §10.4) -/

/-- Run `x` from a fresh state with the baseline heartbeat budget; restore the state. -/
def baseline (x : MetaM (List (String × Json))) : MetaM Json := do
  let s ← saveState
  let t0 ← IO.monoMsNow
  -- `try … catch` does not catch runtime exceptions (heartbeats, recursion depth); a
  -- baseline that runs out of its budget is an outcome, so use `tryCatchRuntimeEx`
  let r ← tryCatchRuntimeEx
    (withTheReader Core.Context (fun c => { c with maxHeartbeats := baselineHeartbeats * 1000 }) <|
      withCurrHeartbeats x)
    fun e => do
      if e.isMaxHeartbeat then pure [("outcome", jStr "heartbeats")]
      else if e.isMaxRecDepth then pure [("outcome", jStr "max_rec_depth")]
      else pure [("outcome", jStr "failed"), ("reason", jStr ((← msgOf e).take 200).toString)]
  let ms ← msSince t0
  s.restore
  return Json.mkObj (r ++ [("ms", toJson ms)])

/-- `solve_by_elim [H]` on the goal. With `useDefaults := false` (like-for-like, §10.5
decision 3) the lemmas are `H` alone: `rfl`, `trivial`, `congrFun` and `congrArg` are left out.
The local hypotheses are kept in both cases. `mkAssumptionSet true …` (`only`) is not used
because in 4.36 it also drops the local hypotheses. -/
def sbe (goal : Expr) (nctx : Nat) (H : Array Name) (cfg : SolveByElim.SolveByElimConfig)
    (useDefaults : Bool) : MetaM (List (String × Json)) := do
  let m ← mkFreshExprMVar goal
  let (_, g) ← m.mvarId!.introNP nctx
  g.withContext do
    let ⟨defaults, ctx⟩ ← SolveByElim.mkAssumptionSet false false [] [] #[]
    let lemmas := H.toList.map (fun c => (mkConstWithFreshMVarLevels c : Elab.TermElabM Expr)) ++
      (if useDefaults then defaults else [])
    let rest ← SolveByElim.solveByElim cfg lemmas ctx [g]
    let closed := rest.isEmpty && !(← instantiateMVars m).hasExprMVar
    return [("outcome", jStr (if closed then "closed" else "open"))]

def libSearch (goal : Expr) (nctx : Nat) (self : Name) : MetaM (List (String × Json)) := do
  let m ← mkFreshExprMVar goal
  let (_, g) ← m.mvarId!.introNP nctx
  let (_, g) ← g.intros
  g.withContext do
    let tactic := fun gs => LibrarySearch.solveByElim [] (exfalso := false) gs (maxDepth := 6)
    match ← LibrarySearch.librarySearch g tactic (fun _ => pure true) (includeStar := true)
        (collectAll := false) with
    | none =>
      let t ← instantiateMVars m
      let cl := if t.getUsedConstants.contains self then "closed_self" else "closed_other"
      return [("exact", jStr cl), ("apply", jStr cl), ("term", jStr ((toString (← ppExpr t)).take 300).toString)]
    | some sugg =>
      if sugg.isEmpty then return [("exact", jStr "none"), ("apply", jStr "none")]
      let minRest := sugg.foldl (fun a (gs, _) => min a gs.length) 1000000
      return [("exact", jStr "none"), ("apply", jStr "partial"), ("suggestions", toJson sugg.size),
              ("min_remaining", toJson minRest)]

/-- The three baselines. They run before the `solve_by_sat` N loop (§10.5 decision 2). Each one
is a separate `MetaM` run that rebuilds the goal, so it starts from a fresh Core and Meta state
(`SavedState.restore` would keep `Meta.Cache`), and the N loop after them also starts fresh. -/
def runBaselines (env : Environment) (s : Spec) : IO Json := do
  let like : SolveByElim.SolveByElimConfig := { maxDepth := sbeDepth, symm := false, exfalso := false }
  let dflt : SolveByElim.SolveByElimConfig := { maxDepth := sbeDepth }
  let one (x : Expr → Nat → MetaM (List (String × Json))) : IO Json :=
    runMeta env do let (goal, nctx) ← goalOf s; baseline (x goal nctx)
  return Json.mkObj [
    ("sbe_like", ← one fun g n => sbe g n s.H like false),
    ("sbe_default", ← one fun g n => sbe g n s.H dflt true),
    ("library_search", ← one fun g n => libSearch g n s.thm)]

/-! ## Main -/

def nameTable (env : Environment) : Std.HashMap String Name :=
  env.constants.fold (fun m n _ => m.insert n.toString n) {}

def readKeys (path : System.FilePath) : IO (Std.HashSet String) := do
  if !(← path.pathExists) then return {}
  let mut ks := {}
  for l in (← IO.FS.readFile path).splitOn "\n" do
    if let .ok j := Json.parse l then
      if let .ok k := j.getObjValAs? String "key" then ks := ks.insert k
  return ks

unsafe def runShard (specsPath results started warmup : System.FilePath) : IO UInt32 := do
  let lines := (← IO.FS.readFile specsPath).splitOn "\n" |>.filter (· != "")
  let js ← lines.mapM fun l => IO.ofExcept (Json.parse l)
  let named := js.any fun j => j.getObjValD "run" == jStr "named"
  let env ← importEnv (if named then #[`Init, `Std, `Test.EvalNamed] else #[`Init, `Std])
  let names := nameTable env
  let specs ← js.mapM fun j => IO.ofExcept (parseSpec names j)
  let done ← readKeys results
  let todo := specs.filter (!done.contains ·.key)
  if todo.isEmpty then return 0
  let blPath := (results.parent.getD ".") / "baselines.jsonl"
  -- warm-up for exact?/apply? (§10.3): one untimed librarySearch, before the first goal
  if todo.any (·.baselines) then
    let t0 ← IO.monoMsNow
    let (rss0, _) ← memMB
    runMeta env do
      let m ← mkFreshExprMVar (mkConst ``True)
      discard <| LibrarySearch.librarySearch m.mvarId!
    let (rss1, hwm1) ← memMB
    appendLine warmup (Json.mkObj [("specs", specsPath.toString), ("ms", ← msSince t0),
      ("rss_before_mb", rss0), ("rss_after_mb", rss1), ("hwm_mb", hwm1)]).compress
  for s in todo do
    appendLine started (Json.mkObj [("key", s.key)]).compress
    let t0 ← IO.monoMsNow
    let phase := fun (p : String) =>
      appendLine started (Json.mkObj [("key", jStr s.key), ("phase", jStr p)]).compress
    let r ← (do
      -- baselines first (§10.5 decision 2), with the shard's RSS before and after them
      let mut blInfo : List (String × Json) := [("baselines", Json.null)]
      if s.baselines then
        phase "baselines"
        let (rssB0, _) ← memMB
        let bl ← runBaselines env s
        let (rssB1, hwmB1) ← memMB
        blInfo := [("baselines", bl), ("rss_before_baselines_mb", toJson rssB0),
                   ("rss_after_baselines_mb", toJson rssB1), ("hwm_after_baselines_mb", toJson hwmB1)]
        -- written now, so that a crash in the N loop keeps them (the driver merges this line
        -- into the crash record)
        appendLine blPath (Json.mkObj ([("key", jStr s.key)] ++ blInfo)).compress
      phase "sat"
      let (sat, bug) ← runMeta env do
        let (goal, _) ← goalOf s
        let progress := fun (N : Nat) =>
          appendLine started (Json.mkObj [("key", jStr s.key), ("N", toJson N)]).compress
        runSat goal s.H s.opts progress
      return (sat, Json.mkObj blInfo, bug)).toBaseIO
    let (rss, hwm) ← memMB
    let head := [("key", jStr s.key), ("id", jStr s.id), ("run", jStr s.run), ("tier", jStr s.tier),
                 ("H_size", Json.num s.H.size), ("expect", jStr s.expect)]
    match r with
    | .ok (sat, bl, bug) =>
      let j := (Json.mkObj head).mergeObj sat |>.mergeObj bl |>.mergeObj
        (Json.mkObj [("total_ms", Json.num (← msSince t0)),
                     ("rss_mb", Json.num rss), ("hwm_mb", Json.num hwm)])
      appendLine results j.compress
      if bug then
        IO.eprintln s!"STOP: {(sat.getObjValD "outcome").compress} on {s.key}: {(sat.getObjValD "reason").compress}"
        return 3
    | .error e =>
      appendLine results (Json.mkObj (head ++ [("outcome", jStr "harness_error"),
        ("reason", jStr (toString e))])).compress
      IO.eprintln s!"STOP: harness error on {s.key}: {e}"
      return 4
  return 0

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | ["run", specs, results, started, warmup] => runShard specs results started warmup
  | "verify-removed" :: cs =>
    let env ← importEnv #[`Init, `Std]
    let names := nameTable env
    for c in cs do
      let some n := names[c]? | IO.println s!"unknown {c}"; continue
      let r ← runMeta env do
        try discard <| compile (mkConst ``True) #[n]; pure "ACCEPTED"
        catch e => pure s!"rejected: {← msgOf e}"
      IO.println s!"{c}: {r}"
    return 0
  | _ => IO.println "usage: eval_run run <specs> <results> <started> <warmup> | verify-removed <names…>"; return 2
