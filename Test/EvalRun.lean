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
import Test.M8Rules
import Test.M8Diag

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
  /-- 7c (EVAL_PLAN §4.2, §10.9 decision 6): the N loop's bound. Absent: `nMax`. -/
  nmax : Nat := nMax
  /-- 7c: the distractors appended to `H` (decision 6), watched in the decoded proof. -/
  distractors : Array Name := #[]
  /-- 7c: the goal's proved N and outcome in `eval/final/` (decision 9's stop rules).
  `none` for every spec that is not a 4.2 run. -/
  origN : Option Nat := none
  origOutcome : String := ""
  k : Nat := 0
  mode : String := ""
  /-- 8a (M8_PLAN §2.3): generate the rewriting rules for this goal and pass H as in §2.3.
  `H` is then the goal's accepted H_main constants. `false` for every other spec. -/
  probe : Bool := false
  /-- 8a: `rewrite_A`, `rewrite_B` or `control` (§2.2, §2.5's stop rules). -/
  probeGroup : String := ""

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
           expect := (j.getObjValAs? String "expect").toOption.getD "",
           nmax := (j.getObjValAs? Nat "nmax").toOption.getD nMax,
           distractors := ← ((j.getObjValAs? (Array String) "distractors").toOption.getD #[]).mapM name,
           origN := (j.getObjValAs? Nat "orig_N").toOption,
           origOutcome := (j.getObjValAs? String "orig_outcome").toOption.getD "",
           k := (j.getObjValAs? Nat "k").toOption.getD 0,
           mode := (j.getObjValAs? String "mode").toOption.getD "",
           probe := (j.getObjValAs? Bool "probe").toOption.getD false,
           probeGroup := (j.getObjValAs? String "probe_group").toOption.getD "" }

/-- 8c-1 (M8_PLAN 4.4): the milestone 8 flags of a run, from the environment variable
`SOLVE_BY_SAT_EVAL_FLAGS`, a comma list of `nodeBounds` and `exclusivePairs`. Unset or empty:
both off, whatever `EncodeOptions`' defaults are, so the milestone 7 and 8a harness keeps
building exactly the CNFs it built. -/
def evalFlags : IO (List String) := do
  let s := (← IO.getEnv "SOLVE_BY_SAT_EVAL_FLAGS").getD ""
  return (s.splitOn ",").filter (· != "")

def withEvalFlags (fl : List String) (o : EncodeOptions) : EncodeOptions :=
  { o with nodeBounds := fl.contains "nodeBounds", exclusivePairs := fl.contains "exclusivePairs" }

/-- 9a-1 (M9_PLAN 2.1): the compiler options of `eval_run run|sizes`, from the same variable:
`iffEq` in `SOLVE_BY_SAT_EVAL_FLAGS` turns `CompileOptions.iffEq` on. Unset or absent: every
compiler option off, the harness's own default, so earlier runs rebuild their forests. -/
def evalCompileOptions (fl : List String) : CompileOptions :=
  { iffEq := fl.contains "iffEq", rewrite := fl.contains "rewrite", eqTrans := !fl.contains "noEqTrans" }

/-- 9a-2 (M9_PLAN 3.1): counts by kind and row, `{kind: {row: n}}`, kinds and rows with none left out. -/
def ruleCounts (keys : Array Rules.Key) : Json :=
  let kinds := #[Rules.Kind.subst, .congr, .refl, .symm, .trans]
  let rows := #[Rules.Row.ground, .root, .hvars]
  Json.mkObj <| (kinds.filterMap fun k =>
    let cs := rows.filterMap fun r =>
      let n := (keys.filter fun key => key.kind == k && key.row == r).size
      if n == 0 then none else some (r.name, toJson n)
    if cs.isEmpty then none else some (k.name, Json.mkObj cs.toList)).toList

/-- 9a-2: the records of the rules a compilation made (M9_PLAN 3.3, "Recorded per point"). -/
def rulesJson (C : Compiled) : List (String × Json) :=
  [("rules", ruleCounts (C.rules.map (·.key))), ("rules_total", toJson C.rules.size),
   ("liberal_extra", ruleCounts C.ruleStats.liberalExtra), ("liberal_extra_total", toJson C.ruleStats.liberalExtra.size),
   ("rules_dropped", toJson (C.ruleStats.dropped.map fun (n, m) => Json.arr #[Json.str n, Json.str (m.take 300).toString])),
   ("rewrite_sources", toJson C.ruleStats.sources), ("rewrite_symbols", toJson C.ruleStats.symbols.size),
   ("spines_broken", toJson C.ruleStats.broken), ("spine_nodes_no_row", toJson C.ruleStats.noRow)]

/-- 9a-2: the rules a decoded proof uses (by name, in node order, with repeats), and their counts. -/
def rulesUsedJson (C : Compiled) (sk : Array SkelNode) : List (String × Json) :=
  let used := sk.filterMap fun n => match C.clauseInfo[n.clause]!.origin with
    | .rule k => C.rules[k]?
    | _ => none
  [("rules_used", toJson (used.map (·.name))), ("rules_used_by", ruleCounts (used.map (·.key)))]

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
def runSat (goal : Expr) (H : Array Name) (opts : Array String) (progress : Nat → IO Unit)
    (nmax : Nat := nMax) (watch : Array Name := #[]) :
    MetaM (Json × Bool) := do
  let t0 ← IO.monoMsNow
  let copts := evalCompileOptions (← evalFlags)
  -- 9a-2: acceptance is decided without the rules (a rule that cannot be made is dropped, never a
  -- reason to reject a constant); the whole is compiled with them
  let accOpts := { copts with rewrite := false }
  -- 1. the goal
  try discard <| compile goal #[] accOpts
  catch e => return (Json.mkObj [("outcome", jStr "goal_rejected"), ("reason", jStr (← msgOf e))], false)
  -- 2. each H constant on its own
  let mut acc := #[]
  let mut rej := #[]
  for c in H do
    try discard <| compile goal #[c] accOpts; acc := acc.push c
    catch e => rej := rej.push (Json.arr #[c.toString, ← msgOf e])
  let base := [("H_accepted", Json.arr (acc.map (Json.str ·.toString))), ("H_rejected", Json.arr rej)]
  let C ← try compile goal acc copts
    catch e =>
      -- an internal error of the rules' construction is a bug (M9_PLAN 3.1), not an outcome
      let m ← msgOf e
      return (Json.mkObj (base ++ [("outcome", jStr "compile_error"), ("reason", jStr m)]),
              copts.rewrite && (m.splitOn "solve_by_sat: internal").length > 1)
  let C := if opts.contains "forgettypes" then { C with forest := C.forest.forgetTypes } else C
  let base := if copts.iffEq then base ++ [("iffeq_paths", toJson [C.iffEqCounts.1, C.iffEqCounts.2])] else base
  let base := if copts.rewrite then base ++ rulesJson C ++ [("eqTrans", toJson copts.eqTrans)] else base
  let flags ← evalFlags
  let eopts : EncodeOptions := withEvalFlags flags { staticTyping := !opts.contains "nostatic" }
  let base := if flags.isEmpty then base else base ++ [("enc_flags", toJson flags)]
  -- 3. N = 1 … Nmax
  let mut log := #[]
  for N in [1:nmax+1] do
    let elapsed ← msSince t0
    if elapsed ≥ loopSeconds * 1000 then
      return (Json.mkObj (base ++ [("outcome", jStr "timeout"), ("N", toJson (N)), ("timeout_kind", jStr "loop"),
        ("per_N", Json.arr log), ("loop_ms", toJson (elapsed))]), false)
    progress N   -- a marker, so that a shard crash records the N it reached
    let te ← IO.monoMsNow
    let E := encode C.forest N eopts
    let nCl := E.cnf.clauses.size   -- forces the encoding
    let encMs ← msSince te
    -- R1's early exit (8c-1): s(root) > N, so no proof with N nodes; nothing is solved
    if E.info.earlyExit then
      log := log.push (Json.mkObj [("N", toJson N), ("vars", toJson E.cnf.nVars), ("clauses", toJson nCl),
        ("encode_ms", toJson encMs), ("solve_s", toJson (0.0 : Float)), ("solver_peak_mb", toJson (0 : Nat)),
        ("result", jStr "early_exit"), ("root_size", toJson E.info.rootSize)])
      if N == nmax then
        return (Json.mkObj (base ++ [("outcome", jStr "no_proof_le_Nmax"), ("N", toJson N),
          ("vars", toJson E.cnf.nVars), ("clauses", toJson nCl),
          ("families", Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, Json.num k))),
          ("encode_ms", toJson encMs), ("solve_s", toJson (0.0 : Float)), ("solver_peak_mb", toJson (0 : Nat)),
          ("per_N", Json.arr log), ("loop_ms", toJson (← msSince t0))]), false)
      continue
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
      if N == nmax then
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
        let skel := readSkeleton C.forest E.vars model
        let sk := match skel with
          | .ok sk => renderSkeleton C.forest sk 0
          | .error e => s!"(skeleton: {e})"
        let usedRules := match skel with
          | .ok nodes => if copts.rewrite then rulesUsedJson C nodes else []
          | .error _ => []
        -- 7c: which watched constants (the distractors of a 4.2 run) the proof uses
        let used := if watch.isEmpty then [] else
          [("distractors_used", toJson ((watch.filter t.getUsedConstants.contains).map (·.toString)))]
        return (final "proved" ([("skeleton", jStr sk), ("decode_ms", toJson (decMs)), ("loop_ms", toJson (← msSince t0))] ++ used ++ usedRules), false)
  return (Json.mkObj (base ++ [("outcome", jStr "no_proof_le_Nmax"), ("N", toJson (nmax)), ("per_N", Json.arr log),
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

/-- 8c-1 (M8_PLAN 4.4): one reference record's answers: the N where it was UNSAT (per-N rows
`unsat`; for a crash record, and (8d, M8_PLAN 4.6) for a timeout record without per-N rows, every N
below `last_N`) and the N of its proof, if any. -/
def referenceOf (j : Json) : Array Nat × Option Nat := Id.run do
  let outcome := (j.getObjValAs? String "outcome").toOption.getD ""
  let rows := (j.getObjValAs? (Array Json) "per_N").toOption.getD #[]
  let mut unsat : Array Nat := #[]
  if outcome == "crash" || (outcome == "timeout" && rows.isEmpty) then
    unsat := (List.range ((j.getObjValAs? Nat "last_N").toOption.getD 1)).toArray.filter (· ≥ 1)
  for r in rows do
    if (r.getObjValAs? String "result").toOption == some "unsat" then
      if let .ok n := r.getObjValAs? Nat "N" then unsat := unsat.push n
  let proved := if outcome == "proved" then (j.getObjValAs? Nat "N").toOption else none
  return (unsat, proved)

/-- 8c-1 (M8_PLAN 4.4): a reference run's answers per goal (`referenceOf`). -/
def loadReference (path : System.FilePath) : IO (Std.HashMap String (Array Nat × Option Nat)) := do
  let mut m := {}
  for l in (← IO.FS.readFile path).splitOn "\n" do
    let .ok j := Json.parse l | continue
    let .ok k := j.getObjValAs? String "key" | continue
    m := m.insert k (referenceOf j)
  return m

/-- The exactness stop rules of M8_PLAN 4.4 for one result against the reference: a proof at an N
where the reference was UNSAT; UNSAT or the early exit at the N of the reference's proof; both
proved at different N. -/
def exactnessStop (ref : Array Nat × Option Nat) (sat : Json) : Option String := Id.run do
  let (unsat, proved) := ref
  let outcome := (sat.getObjValAs? String "outcome").toOption.getD ""
  let nFound := if outcome == "proved" then (sat.getObjValAs? Nat "N").toOption else none
  if let some n := nFound then
    if unsat.contains n then return some s!"a proof at N = {n}, where the reference run was UNSAT"
    if let some p := proved then
      if p != n then return some s!"a proof at N = {n}, the reference run's proof is at N = {p}"
  for r in (sat.getObjValAs? (Array Json) "per_N").toOption.getD #[] do
    let res := (r.getObjValAs? String "result").toOption.getD ""
    let n := (r.getObjValAs? Nat "N").toOption.getD 0
    if (res == "unsat" || res == "early_exit") && proved == some n then
      return some s!"{res} at N = {n}, where the reference run found a proof"
  return none

/-- 8d (M8_PLAN 4.6): the exactness comparison must flag a hand-made disagreement in each of the
three stop cases, and must not flag agreements. Exit 1 on any failure. -/
def exactnessSelftest : IO UInt32 := do
  let pj := fun (s : String) => match Json.parse s with | .ok j => j | .error _ => Json.null
  let row := fun (n : Nat) (r : String) => s!"\{\"N\": {n}, \"result\": \"{r}\"}"
  let rec_ := fun (out : String) (n : Option Nat) (rows : List String) (lastN : Option Nat) =>
    pj ("{\"outcome\": \"" ++ out ++ "\"" ++ (match n with | some k => s!", \"N\": {k}" | none => "") ++
      (match lastN with | some k => s!", \"last_N\": {k}" | none => "") ++
      ", \"per_N\": [" ++ ", ".intercalate rows ++ "]}")
  -- references: proved at 3; no proof up to 4; a crash at last_N 4 (UNSAT at 1..3); a timeout without rows
  let refProved := referenceOf (rec_ "proved" (some 3) [row 1 "unsat", row 2 "unsat", row 3 "proved"] none)
  let refNoProof := referenceOf (rec_ "no_proof_le_Nmax" none [row 1 "unsat", row 2 "unsat", row 3 "unsat", row 4 "unsat"] none)
  let refCrash := referenceOf (pj "{\"outcome\": \"crash\", \"cause\": \"oom\", \"last_N\": 4}")
  let refTimeout := referenceOf (pj "{\"outcome\": \"timeout\", \"last_N\": 3}")
  let cases : List (String × (Array Nat × Option Nat) × Json × Bool) := [
    ("1 a proof where the reference was UNSAT", refNoProof, rec_ "proved" (some 2) [row 1 "unsat", row 2 "proved"] none, true),
    ("1 a proof below a reference crash's last_N", refCrash, rec_ "proved" (some 3) [row 1 "unsat", row 2 "unsat", row 3 "proved"] none, true),
    ("1 a proof below a reference timeout's last_N", refTimeout, rec_ "proved" (some 2) [row 1 "unsat", row 2 "proved"] none, true),
    ("2 UNSAT at the reference's proof N", refProved, rec_ "no_proof_le_Nmax" none [row 1 "unsat", row 2 "unsat", row 3 "unsat", row 4 "unsat"] none, true),
    ("2 the early exit at the reference's proof N", refProved, rec_ "no_proof_le_Nmax" none [row 1 "unsat", row 2 "unsat", row 3 "early_exit"] none, true),
    ("2 UNSAT at the reference's proof N, then a timeout", refProved, rec_ "timeout" none [row 1 "unsat", row 2 "unsat", row 3 "unsat", row 4 "timeout"] none, true),
    ("3 both prove, at different N", refProved, rec_ "proved" (some 4) [row 1 "unsat", row 2 "unsat", row 3 "unknown", row 4 "proved"] none, true),
    ("agree: proved at the reference's N", refProved, rec_ "proved" (some 3) [row 1 "unsat", row 2 "unsat", row 3 "proved"] none, false),
    ("agree: no proof against no proof", refNoProof, rec_ "no_proof_le_Nmax" none [row 1 "unsat", row 2 "unsat", row 3 "unsat", row 4 "unsat"] none, false),
    ("agree: a proof at a reference crash's last_N", refCrash, rec_ "proved" (some 4) [row 1 "unsat", row 2 "unsat", row 3 "unsat", row 4 "proved"] none, false),
    ("agree: a proof above a reference crash's last_N", refCrash, rec_ "proved" (some 6) [row 1 "unsat", row 5 "unsat", row 6 "proved"] none, false),
    ("agree: the early exit against a crash", refCrash, rec_ "no_proof_le_Nmax" none [row 1 "early_exit"] none, false),
    ("agree: a timeout below the reference's proof N", refProved, rec_ "timeout" none [row 1 "unsat", row 2 "timeout"] none, false)]
  let mut fails := 0
  for (name, ref, res, want) in cases do
    let got := exactnessStop ref res
    let ok := got.isSome == want
    unless ok do fails := fails + 1
    IO.println s!"{if ok then "PASS" else "FAIL"} {name}: {got.getD "no stop"}"
  IO.println s!"exactness (M8_PLAN 4.6): {cases.length - fails} passed, {fails} failed"
  return (if fails == 0 then 0 else 1)

unsafe def runShard (specsPath results started warmup : System.FilePath) : IO UInt32 := do
  -- 8c-1: the reference run for the exactness stop rules of M8_PLAN 4.4, if any
  let reference : Option (Std.HashMap String (Array Nat × Option Nat)) ← match (← IO.getEnv "SOLVE_BY_SAT_EVAL_COMPARE") with
    | some p => if p.isEmpty then pure none else some <$> loadReference p
    | none => pure none
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
        if s.probe then
          let tg ← IO.monoMsNow
          let R ← M8.generate goal s.H
          let genMs ← msSince tg
          let H := M8.probeH s.H R.rules
          let watch := H.filter (!s.H.contains ·)
          let (sat, bug) ← runSat goal H s.opts progress s.nmax watch
          let used := (sat.getObjValAs? (Array String) "distractors_used").toOption.getD #[]
          return (sat.mergeObj (Json.mkObj (M8.rulesJson R ++
            [("probe_group", jStr s.probeGroup), ("probe_H_size", toJson H.size), ("probe_gen_ms", toJson genMs),
             ("probe_extra_used", toJson used), ("uses_rule", toJson (used.any (·.startsWith "_probe."))),
             ("uses_propext", toJson (used.any fun u => (u.splitOn ".propext.").length > 1))])), bug)
        runSat goal s.H s.opts progress s.nmax s.distractors
      return (sat, Json.mkObj blInfo, bug)).toBaseIO
    let (rss, hwm) ← memMB
    let head := [("key", jStr s.key), ("id", jStr s.id), ("run", jStr s.run), ("tier", jStr s.tier),
                 ("H_size", Json.num s.H.size), ("expect", jStr s.expect)]
    match r with
    | .ok (sat, bl, bug) =>
      -- 7c, 4.2 runs only (EVAL_PLAN §10.9 decisions 6 and 9): the new record fields and the
      -- stop rules. Every other spec has `origN = none` and is unchanged.
      let outcome := (sat.getObjValAs? String "outcome").toOption.getD ""
      let nFound := (sat.getObjValAs? Nat "N").toOption
      let (scal, stop) := match s.origN with
        | none => ((Json.mkObj []), none)
        | some n0 =>
          let proved := outcome == "proved"
          let limits := ["timeout", "memout"]
          let f := Json.mkObj [("k", toJson s.k), ("mode", jStr s.mode), ("nmax", toJson s.nmax),
            ("orig_N", toJson n0), ("orig_outcome", jStr s.origOutcome),
            ("distractors", toJson (s.distractors.map (·.toString))),
            ("below_original", toJson (proved && nFound.getD n0 < n0)),
            ("feasible", toJson (proved && nFound.getD (n0 + 1) ≤ n0))]
          -- monotonicity (4.2): within every limit, there must be a proof at or below n0
          let stop1 := if !proved && !limits.contains outcome && !bug then
              some s!"monotonicity violation: {outcome} within the limits, original N {n0}" else none
          -- k = 0 builds the CNFs of the final results: same outcome and N (unless a limit)
          let stop2 := if s.k == 0 && !s.probe && !limits.contains outcome && !limits.contains s.origOutcome &&
              (outcome != s.origOutcome || (proved && nFound != some n0)) then
              some s!"k = 0 differs from eval/final/: {outcome} N {nFound} against {s.origOutcome} N {n0}" else none
          (f, stop1 <|> stop2)
      -- 8a (M8_PLAN §2.5): a rewriting goal proved with its H_main constants alone stops the run
      let stop := if s.probe && s.probeGroup.startsWith "rewrite" && outcome == "proved" &&
          ((sat.getObjValAs? (Array String) "probe_extra_used").toOption.getD #[]).isEmpty then
          stop <|> some "a rewriting goal proved with its H_main constants only (M8_PLAN 2.5)" else stop
      -- 8c-1 (M8_PLAN 4.4): the exactness stop rules against the reference run
      let exact : Option String := reference.bind fun m =>
        match m.get? s.key with
        | some ref => (exactnessStop ref sat).map ("exactness (M8_PLAN 4.4): " ++ ·)
        | none => some "exactness (M8_PLAN 4.4): the goal is not in the reference run"
      -- 8d (M8_PLAN 4.6): an exactness stop has its own exit code, 9 (8c-1 used 6)
      let stop := stop <|> exact
      let exactOnly := exact.isSome && stop == exact
      let j := (Json.mkObj head).mergeObj sat |>.mergeObj bl |>.mergeObj scal |>.mergeObj
        (Json.mkObj ([("total_ms", Json.num (← msSince t0)),
                     ("rss_mb", Json.num rss), ("hwm_mb", Json.num hwm)] ++
                     (match stop with | some m => [("stop", jStr m)] | none => [])))
      appendLine results j.compress
      if bug then
        IO.eprintln s!"STOP: {(sat.getObjValD "outcome").compress} on {s.key}: {(sat.getObjValD "reason").compress}"
        return 3
      if let some m := stop then
        IO.eprintln s!"STOP (EVAL_PLAN 10.9 decision 9, M8_PLAN 2.5, 4.4, 4.6): {m} on {s.key}"
        return (if exactOnly then 9 else 6)
    | .error e =>
      appendLine results (Json.mkObj (head ++ [("outcome", jStr "harness_error"),
        ("reason", jStr (toString e))])).compress
      IO.eprintln s!"STOP: harness error on {s.key}: {e}"
      return 4
  return 0

/-- 7c (EVAL_PLAN §10.9 decision 7): the `countOnly` sizes per family of each spec at its
`nmax` (the goal's original N), compiled exactly as `runSat` compiles. Nothing is solved.
A marker goes to `started` before each spec, so a wrapper can tell which spec a crash hit. -/
unsafe def runSizes (specsPath results started : System.FilePath) : IO UInt32 := do
  let lines := (← IO.FS.readFile specsPath).splitOn "\n" |>.filter (· != "")
  let js ← lines.mapM fun l => IO.ofExcept (Json.parse l)
  let env ← importEnv #[`Init, `Std]
  let names := nameTable env
  let specs ← js.mapM fun j => IO.ofExcept (parseSpec names j)
  let done ← readKeys results
  for s in specs.filter (!done.contains ·.key) do
    appendLine started (Json.mkObj [("key", s.key)]).compress
    let t0 ← IO.monoMsNow
    let r ← runMeta env do
      let (goal, _) ← goalOf s
      let (H, extra) : Array Name × List (String × Json) ← if s.probe then do
          let R ← M8.generate goal s.H
          pure (M8.probeH s.H R.rules, [("probe_rules", toJson R.rules.size)])
        else pure (s.H, [])
      let flags ← evalFlags
      let copts := evalCompileOptions flags
      let mut acc := #[]
      for c in H do
        try discard <| compile goal #[c] copts; acc := acc.push c catch _ => pure ()
      let C ← compile goal acc copts
      let E := encode C.forest s.nmax (withEvalFlags flags { countOnly := true })
      let extra := if flags.isEmpty then extra else extra ++ [("enc_flags", toJson flags),
        ("early_exit", toJson E.info.earlyExit), ("gp_dead", toJson E.info.gpDead), ("cl_dead", toJson E.info.clDead)]
      return Json.mkObj ([("N", toJson s.nmax), ("vars", toJson E.cnf.nVars), ("clauses", toJson E.cnf.numClauses),
        ("families", Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, Json.num k))),
        ("H_accepted", toJson acc.size)] ++ extra)
    let (_, hwm) ← memMB
    appendLine results ((Json.mkObj [("key", jStr s.key), ("status", jStr "ok")]).mergeObj r |>.mergeObj
      (Json.mkObj [("ms", toJson (← msSince t0)), ("hwm_mb", toJson hwm)])).compress
  return 0

/-- 8a (M8_PLAN §2.3, "Bookkeeping"): for each probe spec, the rules generated for its goal, the
rules that failed to build, and the H constants the compiler rejects (each compiled on its own, as
`runSat` does). Nothing is encoded or solved. -/
unsafe def runProbeRules (specsPath results : System.FilePath) : IO UInt32 := do
  let lines := (← IO.FS.readFile specsPath).splitOn "\n" |>.filter (· != "")
  let js ← lines.mapM fun l => IO.ofExcept (Json.parse l)
  let env ← importEnv #[`Init, `Std]
  let names := nameTable env
  let specs ← js.mapM fun j => IO.ofExcept (parseSpec names j)
  let done ← readKeys results
  for s in specs.filter (!done.contains ·.key) do
    let t0 ← IO.monoMsNow
    let r ← runMeta env do
      let (goal, _) ← goalOf s
      let R ← M8.generate goal s.H
      let H := M8.probeH s.H R.rules
      let mut rej := #[]
      for c in H do
        try discard <| compile goal #[c]
        catch e => rej := rej.push (Json.arr #[c.toString, ← msgOf e])
      return Json.mkObj (M8.rulesJson R ++ [("probe_H_size", toJson H.size), ("H_rejected", Json.arr rej)])
    appendLine results ((Json.mkObj [("key", jStr s.key), ("probe_group", jStr s.probeGroup)]).mergeObj r |>.mergeObj
      (Json.mkObj [("ms", toJson (← msSince t0))])).compress
  return 0

/-! ## 8b (M8_PLAN §4.3): measurements. Read-only; the CNF is built exactly as by `runSat`. -/

/-- The forest a spec's run builds: H as in `runSat` (probe rules when `probe`), each constant
compiled on its own and the rejected ones left out. -/
def specForest (s : Spec) (copts : CompileOptions := {}) : MetaM (Forest × Compiled) := do
  let (goal, _) ← goalOf s
  let H ← if s.probe then do
      let R ← M8.generate goal s.H
      pure (M8.probeH s.H R.rules)
    else pure s.H
  let mut acc := #[]
  -- 9a-2: acceptance without the rules, as in `runSat`
  for c in H do
    try discard <| compile goal #[c] { copts with rewrite := false }; acc := acc.push c catch _ => pure ()
  let C ← compile goal acc copts
  return (C.forest, C)

unsafe def specsEnv (specsPath : System.FilePath) : IO (Environment × Array Spec) := do
  let lines := (← IO.FS.readFile specsPath).splitOn "\n" |>.filter (· != "")
  let js ← lines.mapM fun l => IO.ofExcept (Json.parse l)
  let named := js.any fun j => j.getObjValD "run" == jStr "named"
  let env ← importEnv (if named then #[`Init, `Std, `Test.EvalNamed] else #[`Init, `Std])
  let names := nameTable env
  let specs ← js.mapM fun j => IO.ofExcept (parseSpec names j)
  return (env, specs.toArray)

/-- 9a-1 (M9_PLAN 2.2, "The 8a count"): for each spec, the `iffEq` paths the compiler makes with H
the spec's (each constant accepted on its own, as `runSat` does) and `iffEq` on: from constants of H
(in all, and per constant) and from local hypotheses, and the notes of dropped paths. Also whether
`iffEq` changes which constants are accepted. Nothing is encoded or solved. -/
unsafe def runIffEqCount (specsPath results : System.FilePath) : IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  for s in specs.filter (!done.contains ·.key) do
    let t0 ← IO.monoMsNow
    let r ← runMeta env do
      let (goal, _) ← goalOf s
      let on : CompileOptions := { iffEq := true }
      let mut acc := #[]
      let mut accOff := #[]
      for c in s.H do
        try discard <| compile goal #[c] on; acc := acc.push c catch _ => pure ()
        try discard <| compile goal #[c]; accOff := accOff.push c catch _ => pure ()
      let C ← compile goal acc on
      let (g, l) := C.iffEqCounts
      let perConst := acc.filterMap fun c =>
        let k := (C.clauseInfo.filter fun ci => ci.isIffEq && (match ci.origin with | .global c' => c' == c | _ => false)).size
        if k == 0 then none else some (c.toString, k)
      let mut dropped := #[]
      for n in C.notes do
        let m ← n.toString
        if (m.splitOn "propext").length > 1 then dropped := dropped.push m
      return Json.mkObj [("iffeq_global", toJson g), ("iffeq_local", toJson l),
        ("iffeq_per_constant", Json.mkObj (perConst.toList.map fun (c, k) => (c, toJson k))),
        ("dropped", toJson dropped), ("H_accepted", toJson (acc.map (·.toString))),
        ("acceptance_unchanged", toJson (acc == accOff))]
    appendLine results ((Json.mkObj [("key", jStr s.key)]).mergeObj r |>.mergeObj
      (Json.mkObj [("ms", toJson (← msSince t0))])).compress
  return 0

/-- 9a-2 (M9_PLAN 3.2, "The 8a proofs' rules"): for each spec, the rules the compiler makes with H the
spec's (accepted as `runSat` accepts it) and `iffEq` and `rewrite` on: the strict rules and every
liberal candidate, each as (kind, symbol, 8a position, row), the source symbols, and the rules dropped.
Nothing is encoded or solved. -/
unsafe def runRules9a (specsPath results : System.FilePath) : IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  for s in specs.filter (!done.contains ·.key) do
    let t0 ← IO.monoMsNow
    let r ← runMeta env do
      let (_, C) ← specForest s { iffEq := true, rewrite := true }
      let st := C.ruleStats
      let row := fun (k : Rules.Key) => Json.arr #[Json.str k.kind.name, Json.str k.symbol,
        toJson (k.pos8a st.sigs), Json.str k.row.name]
      return Json.mkObj ([("strict", Json.arr (C.rules.map fun R => Json.arr #[Json.str R.name, row R.key])),
        ("liberal", Json.arr (st.liberal.map row)), ("source_symbols", toJson st.symbols)] ++ rulesJson C)
    appendLine results ((Json.mkObj [("key", jStr s.key)]).mergeObj r |>.mergeObj
      (Json.mkObj [("ms", toJson (← msSince t0))])).compress
  return 0

/-- 8c-1 (M8_PLAN 4.4): the three settings of the size measurements, with `countOnly`: both
milestone 8 flags off, R1 on, R1 and R2 on; every other option at its default. -/
def settingOpts : String → Option EncodeOptions
  | "off" => some { countOnly := true, nodeBounds := false, exclusivePairs := false }
  | "r1" => some { countOnly := true, nodeBounds := true, exclusivePairs := false }
  | "r1r2" => some { countOnly := true, nodeBounds := true, exclusivePairs := true }
  | _ => none

/-- 8c-1 (M8_PLAN 4.4): `countOnly` sizes per family at node bound `N` in each setting. One line
per (point, setting), keyed `<point>|<setting>`; a marker goes to `started` before each, so a
wrapper can tell which one a crash hit. The forest is built once per point. -/
unsafe def runSizes8c (specsPath results started : System.FilePath) (N : Nat) (settings : List String) :
    IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  for s in specs do
    let todo := settings.filter fun st => !done.contains s!"{s.key}|{st}"
    if todo.isEmpty then continue
    appendLine started (Json.mkObj [("key", jStr s!"{s.key}|{todo.head!}"), ("phase", jStr "forest")]).compress
    let tf ← IO.monoMsNow
    let (P, _) ← runMeta env (specForest s)
    let forestMs ← msSince tf
    for st in todo do
      let some opts := settingOpts st | IO.eprintln s!"unknown setting {st}"; return 2
      appendLine started (Json.mkObj [("key", jStr s!"{s.key}|{st}")]).compress
      let t0 ← IO.monoMsNow
      let E := encode P N opts
      let n := E.cnf.numClauses
      let ms ← msSince t0
      let (_, hwm) ← memMB
      let i := E.info
      -- R1's excluded pairs from the bounds themselves (also at the early exit, where none is encoded)
      let (gx, cx) := if opts.nodeBounds then
          let B := opts.bounds P
          ((List.range N).foldl (fun n a => n + ((List.range P.goals.size).filter (!B.gpLive N a ·)).length) 0,
           (List.range N).foldl (fun n a => n + ((List.range P.clauses.size).filter (!B.clLive N a ·)).length) 0)
        else (0, 0)
      appendLine results (Json.mkObj [("key", jStr s!"{s.key}|{st}"), ("point", jStr s.key), ("setting", jStr st),
        ("status", jStr "ok"), ("N", toJson N), ("vars", toJson E.cnf.nVars), ("clauses", toJson n),
        ("families", Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, toJson k))),
        ("early_exit", toJson i.earlyExit), ("root_size", toJson i.rootSize), ("gp_dead", toJson i.gpDead),
        ("cl_dead", toJson i.clDead), ("gp_excluded", toJson gx), ("cl_excluded", toJson cx),
        ("exclusive_skipped", toJson i.exclusiveSkipped),
        ("gp_pairs", toJson (N * P.goals.size)), ("cl_pairs", toJson (N * P.clauses.size)),
        ("W", toJson i.W), ("IB", toJson i.IB), ("RB", toJson i.RB), ("rigid", toJson i.rigid),
        ("type_rigid", toJson i.typeRigid), ("full_pairs", toJson i.pairs),
        ("encode_ms", toJson ms), ("forest_ms", toJson forestMs), ("hwm_mb", toJson hwm)]).compress
  return 0

/-- 9a-2 (M9_PLAN 3.3, amendment 6.1 clarification 5): the compiler options of the measurement's
settings. `none` is the forest of 8c-1 (no rules: for a probe point, with 8a's rules as lemmas);
`rw` has `iffEq` and `rewrite`, `rwnt` the same with `eqTrans` off. Every setting encodes with R1
and R2 on. -/
def settings9a : String → Option CompileOptions
  | "none" => some {}
  | "rw" => some { iffEq := true, rewrite := true }
  | "rwnt" => some { iffEq := true, rewrite := true, eqTrans := false }
  | _ => none

/-- 9a-2 (M9_PLAN 3.3): `countOnly` sizes per family at node bound `N`, R1 and R2 on, in each of
`settings` (`settings9a`). A probe point (8a's rules as lemmas) is measured in `none` only, its
8c-1 setting; the rule settings are measured on the points without rules (milestone 7's H). One
line per (point, setting), keyed `<point>|<setting>`, with the rules made by kind and row, the
liberal variant's extra rules, and the rules dropped; a marker goes to `started` before each. -/
unsafe def runSizes9a (specsPath results started : System.FilePath) (N : Nat) (settings : List String) :
    IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  let some opts := settingOpts "r1r2" | return 2
  for s in specs do
    let sts := if s.probe then settings.filter (· == "none") else settings
    for st in sts.filter fun st => !done.contains s!"{s.key}|{st}" do
      let some copts := settings9a st | IO.eprintln s!"unknown setting {st}"; return 2
      appendLine started (Json.mkObj [("key", jStr s!"{s.key}|{st}")]).compress
      let tf ← IO.monoMsNow
      let r ← (runMeta env (specForest s copts)).toBaseIO
      if let .error e := r then
        let bug := ((toString e).splitOn "solve_by_sat: internal").length > 1
        appendLine results (Json.mkObj [("key", jStr s!"{s.key}|{st}"), ("point", jStr s.key), ("setting", jStr st),
          ("status", jStr (if bug then "internal_error" else "compile_error")), ("reason", jStr (toString e))]).compress
        if bug then
          IO.eprintln s!"STOP: internal error on {s.key}|{st}: {e}"
          return 3
        continue
      let .ok (P, C) := r | return 4
      let forestMs ← msSince tf
      let t0 ← IO.monoMsNow
      let E := encode P N opts
      let n := E.cnf.numClauses
      let ms ← msSince t0
      let (_, hwm) ← memMB
      let i := E.info
      let ruleRec := if copts.rewrite then rulesJson C else []
      appendLine results (Json.mkObj ([("key", jStr s!"{s.key}|{st}"), ("point", jStr s.key), ("setting", jStr st),
        ("status", jStr "ok"), ("N", toJson N), ("vars", toJson E.cnf.nVars), ("clauses", toJson n),
        ("families", Json.mkObj (E.cnf.familyCounts.toList.map fun (f, k) => (f, toJson k))),
        ("early_exit", toJson i.earlyExit), ("root_size", toJson i.rootSize), ("gp_dead", toJson i.gpDead),
        ("cl_dead", toJson i.clDead), ("exclusive_skipped", toJson i.exclusiveSkipped),
        ("forest_goals", toJson P.goals.size), ("forest_clauses", toJson P.clauses.size),
        ("W", toJson i.W), ("IB", toJson i.IB), ("RB", toJson i.RB), ("rigid", toJson i.rigid),
        ("type_rigid", toJson i.typeRigid), ("full_pairs", toJson i.pairs),
        ("encode_ms", toJson ms), ("forest_ms", toJson forestMs), ("hwm_mb", toJson hwm)] ++ ruleRec)).compress
  return 0

/-- M1 to M4 at node bound `N` with `countOnly`: one line per finished section, so a point that
runs out of memory keeps the sections it completed. -/
unsafe def runDiag (specsPath results started : System.FilePath) (N : Nat) (setting : String := "off") :
    IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  -- 8c-2a (M8_PLAN 4.5): `r3` replays the encoder with R1 and R2 on (the defaults), R3 off and on
  let r3 := setting == "r3"
  -- 9a-2 (M9_PLAN 3.3): `rw`, `rwnt` (`settings9a`) with R1 and R2 on, the decomposition count
  -- split by whether a pair involves a rule's object; measured on the points without rules only
  let rw := settings9a setting
  let rw := if setting == "none" then none else rw
  let some opts := settingOpts (if r3 || rw.isSome then "r1r2" else setting) | IO.eprintln s!"unknown setting {setting}"; return 2
  for s in specs.filter (!done.contains ·.key) do
    if rw.isSome && s.probe then continue
    appendLine started (Json.mkObj [("key", jStr s.key)]).compress
    let t0 ← IO.monoMsNow
    let (P, C) ← runMeta env (specForest s (rw.getD {}))
    let parts : Option M8Diag.RuleParts := rw.map fun _ =>
      M8Diag.RuleParts.ofForest P ((C.rules.map (·.clause)).foldl min P.clauses.size)
    let emit := fun (sec : String) (j : Json) => do
      let (_, hwm) ← memMB
      appendLine started (Json.mkObj [("key", jStr s.key), ("section", jStr sec), ("data", j),
        ("ms", toJson (← msSince t0)), ("hwm_mb", toJson hwm)]).compress
    if r3 then
      emit "forest" (Json.mkObj [("N", toJson N), ("goals", toJson P.goals.size),
        ("clauses_in_forest", toJson P.clauses.size)])
      M8Diag.r3sim P N opts emit
    else
      let E := encode P N opts
      emit "encode" (Json.mkObj [("N", toJson N), ("vars", toJson E.cnf.nVars), ("clauses", toJson E.cnf.numClauses),
        ("goals", toJson P.goals.size), ("clauses_in_forest", toJson P.clauses.size)])
      M8Diag.analyze P N opts E emit parts
    let (_, hwm) ← memMB
    appendLine results (Json.mkObj [("key", jStr s.key), ("status", jStr "ok"), ("ms", toJson (← msSince t0)),
      ("hwm_mb", toJson hwm)]).compress
  return 0

/-- M5 (and the M4 check on models): solve each spec at its `nmax`, decode and kernel-check the
proof, and classify the model. -/
unsafe def runDiagModels (specsPath results : System.FilePath) : IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  for s in specs.filter (!done.contains ·.key) do
    let t0 ← IO.monoMsNow
    let r ← runMeta env do
      let (P, C) ← specForest s
      let (goal, _) ← goalOf s
      -- the milestone 8 flags pinned off: the model check is of proofs found without R1
      let E := encode P s.nmax { nodeBounds := false, exclusivePairs := false }
      let (res, wall, _) ← solveLimited E.cnf solverSeconds
      match res with
      | .sat model =>
        let t? ← try pure (Except.ok (← decode C E model)) catch e => pure (Except.error (← msgOf e))
        let proof ← match t? with
          | .ok t =>
            let t ← instantiateMVars t
            if t.hasMVar then pure "decoded term has metavariables"
            else if let some err ← kernelCheck goal t then pure s!"kernel: {err}" else pure "ok"
          | .error m => pure m
        match M8Diag.models P s.nmax { nodeBounds := false, exclusivePairs := false } E model with
        | .ok j => return j.mergeObj (Json.mkObj [("result", jStr "sat"), ("proof", jStr proof), ("solve_s", toJson wall)])
        | .error m => return Json.mkObj [("result", jStr "sat"), ("proof", jStr proof), ("error", jStr m)]
      | .unsat => return Json.mkObj [("result", jStr "unsat")]
      | .timeout => return Json.mkObj [("result", jStr "timeout")]
      | .killed sig => return Json.mkObj [("result", jStr s!"killed {sig}")]
      | .error m => return Json.mkObj [("result", jStr "solver_error"), ("reason", jStr m)]
    appendLine results ((Json.mkObj [("key", jStr s.key), ("N", toJson s.nmax)]).mergeObj r |>.mergeObj
      (Json.mkObj [("ms", toJson (← msSince t0))])).compress
  return 0

/-- 8c-2a (M8_PLAN 4.5): the model check. Each spec is solved at its `nmax` with the milestone 8 flags
off, as 8c-1's models were (`runDiagModels`); the proof is decoded and kernel-checked, and every
triangular binding of every chosen candidate with a typing clause is checked under the substitution read
from the model (`M8Diag.r3ModelCheck`). -/
unsafe def runR3Models (specsPath results : System.FilePath) : IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  let done ← readKeys results
  for s in specs.filter (!done.contains ·.key) do
    let t0 ← IO.monoMsNow
    let r ← runMeta env do
      let (P, C) ← specForest s
      let (goal, _) ← goalOf s
      let o : EncodeOptions := { nodeBounds := false, exclusivePairs := false }
      let E := encode P s.nmax o
      let (res, wall, _) ← solveLimited E.cnf solverSeconds
      match res with
      | .sat model =>
        let t? ← try pure (Except.ok (← decode C E model)) catch e => pure (Except.error (← msgOf e))
        let proof ← match t? with
          | .ok t =>
            let t ← instantiateMVars t
            if t.hasMVar then pure "decoded term has metavariables"
            else if let some err ← kernelCheck goal t then pure s!"kernel: {err}" else pure "ok"
          | .error m => pure m
        match M8Diag.r3ModelCheck P s.nmax o E model with
        | .ok j => return j.mergeObj (Json.mkObj [("result", jStr "sat"), ("proof", jStr proof), ("solve_s", toJson wall)])
        | .error m => return Json.mkObj [("result", jStr "sat"), ("proof", jStr proof), ("error", jStr m)]
      | .unsat => return Json.mkObj [("result", jStr "unsat")]
      | .timeout => return Json.mkObj [("result", jStr "timeout")]
      | .killed sig => return Json.mkObj [("result", jStr s!"killed {sig}")]
      | .error m => return Json.mkObj [("result", jStr "solver_error"), ("reason", jStr m)]
    appendLine results ((Json.mkObj [("key", jStr s.key), ("N", toJson s.nmax)]).mergeObj r |>.mergeObj
      (Json.mkObj [("ms", toJson (← msSince t0))])).compress
  return 0

/-- Write the DIMACS file of one encoding, clause by clause. -/
def writeDimacs (F : CNF) (path : System.FilePath) : IO Unit := do
  let h ← IO.FS.Handle.mk path .write
  h.putStr s!"p cnf {F.nVars} {F.clauses.size}\n"
  for c in F.clauses do
    h.putStr (" ".intercalate (c.toList.map toString) ++ " 0\n")

/-- §4.3 "Rules": the DIMACS of each spec at its `nmax`, with the 8b analysis run on the encoding
first (`on`) or not (`off`). -/
unsafe def runDimacs (specsPath outdir : System.FilePath) (mode : String) : IO UInt32 := do
  let (env, specs) ← specsEnv specsPath
  IO.FS.createDirAll outdir
  for h : i in [0:specs.size] do
    let s := specs[i]
    match ← (runMeta env (specForest s)).toBaseIO with
    | .error e => IO.FS.writeFile (outdir / s!"{i}.rejected") s!"{e}\n"
    | .ok (P, _) =>
      -- the milestone 8 flags pinned off (8c-1: the off-switch test compares with 8b's DIMACS)
      let o : EncodeOptions := { nodeBounds := false, exclusivePairs := false }
      let E := encode P s.nmax o
      if mode == "on" then M8Diag.analyze P s.nmax o E (fun _ _ => pure ())
      writeDimacs E.cnf (outdir / s!"{i}.cnf")
  return 0

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | ["diag", specs, results, started, n] => runDiag specs results started n.toNat!
  | ["diag", specs, results, started, n, setting] => runDiag specs results started n.toNat! setting
  | ["rules9a", specs, results] => runRules9a specs results
  | ["sizes9a", specs, results, started, n, settings] =>
    runSizes9a specs results started n.toNat! (settings.splitOn ",")
  | ["sizes8c", specs, results, started, n, settings] =>
    runSizes8c specs results started n.toNat! (settings.splitOn ",")
  | ["diag-models", specs, results] => runDiagModels specs results
  | ["r3-models", specs, results] => runR3Models specs results
  | ["dimacs", specs, outdir, mode] => runDimacs specs outdir mode
  | ["iffeq-count", specs, results] => runIffEqCount specs results
  | ["probe-rules", specs, results] => runProbeRules specs results
  | ["run", specs, results, started, warmup] => runShard specs results started warmup
  | ["sizes", specs, results, started] => runSizes specs results started
  | ["exactness-selftest"] => exactnessSelftest
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
