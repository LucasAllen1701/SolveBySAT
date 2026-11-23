/-
Milestone 7c, EVAL_PLAN §4.2 and §10.9 (4.2 decisions 2 and 4): the distractor pool and the
predicate symbols for the "near" mode. Compilation only; nothing is encoded or solved.

  eval_pool pool OUT
      The 48,012 Tier A source theorems (EVAL_PLAN §2.1's filters, before sampling: the same
      constants, filters and name order as `eval_corpus extract`, whose `tierAReject` is copied
      here unchanged), each compiled on its own as an H constant against the goal `True`, as
      `eval_run verify-removed` does. One line per theorem: `name`, `accepted`, the rejection
      `reason`, and `heads`, the predicate symbols of the heads of all its clauses (every split
      path, the opaque head included). The first line is a header.
  eval_pool syms SPECS OUT
      For each spec (a goal with H = H_main), the predicate symbols S of 4.2 decision 4: the
      goal's root target and the heads of the clauses compiled from the accepted H_main.
-/
import Lean
import SolveBySat
import Test.EvalCommon

open Lean Meta SolveBySat Eval

unsafe def importEnv (mods : Array Name) : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot) [".lake/build/lib/lean"]
  importModules (mods.map fun m => { module := m }) {} (loadExts := true)

def runMeta {α} (env : Environment) (x : MetaM α) : IO α := do
  let ctx : Core.Context := { fileName := "<eval_pool>", fileMap := default, maxHeartbeats := 400000 * 1000 }
  let (a, _) ← (x.run' {} {}).toIO ctx { env }
  return a

/-- Copied unchanged from `Test/EvalCorpus.lean` (the name order of the extraction). -/
def nameLt (a b : Name) : Bool := decide (a.toString < b.toString)

/-- Copied unchanged from `Test/EvalCorpus.lean` (Tier A filters, in order). -/
def tierAReject (env : Environment) (n : Name) (ci : ConstantInfo) : MetaM (Option String) := do
  unless ci matches .thmInfo _ do return some "not a theorem"
  unless ← isProp ci.type do return some "type not a proposition"
  if isInternalAux n then return some "internal auxiliary name"
  let last := match (userName n) with | .str _ s => s | _ => ""
  if isEqnSuffix last || (← isEqnThm n) then return some "equation lemma"
  if underMatcher env n then return some "matcher-derived"
  if isRecursorLike env n then return some "recursor"
  if generatedSuffixes.contains last then return some "compiler-generated lemma"
  return none

def symOf (t : SolveBySat.Term) : Option String := t.symKey.map (·.1)

/-- The predicate symbols of the heads of the global clauses compiled from `c`. -/
def headSyms (C : Compiled) (c : Name) : Array String := Id.run do
  let mut out : Array String := #[]
  for h : i in [0:C.forest.clauses.size] do
    match C.clauseInfo[i]!.origin with
    | .global c' =>
      if c' == c then
        if let some s := symOf C.forest.clauses[i].head then
          unless out.contains s do out := out.push s
    | _ => pure ()
  return out

def msgOf (e : Exception) : MetaM String := do return (← e.toMessageData.toString)

def jStr (s : String) : Json := Json.str s

unsafe def pool (out : System.FilePath) : IO UInt32 := do
  let env ← importEnv sourceModules
  let inSource := fun (n : Name) => match env.getModuleIdxFor? n with
    | some i => sourceModules.any (·.isPrefixOf env.header.moduleNames[i.toNat]!)
    | none => false
  let all := (env.constants.map₁.toList.filter fun (n, _) => inSource n).toArray.qsort
    (fun a b => nameLt a.1 b.1)
  let verdicts ← runMeta env do all.mapM fun (n, ci) => return (n, ← tierAReject env n ci)
  let kept := verdicts.filterMap fun (n, r) => if r.isNone then some n else none
  IO.FS.writeFile out ((Json.mkObj [("header", toJson true), ("constants_in_source", toJson all.size),
    ("kept_after_filters", toJson kept.size), ("goal", jStr "True"),
    ("plan", jStr "EVAL_PLAN 4.2, 10.9 (4.2 decision 2)")]).compress ++ "\n")
  let h ← IO.FS.Handle.mk out .append
  let mut nAcc := 0
  for n in kept do
    let r ← runMeta env do
      tryCatchRuntimeEx
        (do let C ← compile (mkConst ``True) #[n]
            return [("accepted", toJson true), ("heads", toJson (headSyms C n))])
        fun e => do return [("accepted", toJson false), ("reason", jStr ((← msgOf e).take 200).toString)]
    if r.head? == some ("accepted", toJson true) then nAcc := nAcc + 1
    h.putStrLn (Json.mkObj ([("name", jStr n.toString)] ++ r)).compress
  h.flush
  IO.println s!"kept after filters {kept.size}; accepted {nAcc}"
  return 0

def nameTable (env : Environment) : Std.HashMap String Name :=
  env.constants.fold (fun m n _ => m.insert n.toString n) {}

unsafe def syms (specsPath out : System.FilePath) : IO UInt32 := do
  let env ← importEnv sourceModules
  let names := nameTable env
  let lines := (← IO.FS.readFile specsPath).splitOn "\n" |>.filter (· != "")
  let h ← IO.FS.Handle.mk out .write
  for l in lines do
    let j ← IO.ofExcept (Json.parse l)
    let get := fun (f : String) => (j.getObjValAs? String f).toOption.getD ""
    let some thm := names[get "thm"]? | throw (IO.userError s!"unknown {get "thm"}")
    let H := ((j.getObjValAs? (Array String) "H").toOption.getD #[]).filterMap (names[·]?)
    let r ← runMeta env do
      let some ci := (← getEnv).find? thm | throwError "unknown {thm}"
      let goal ← if get "tier" == "A" then pure ci.type else do
        let pos := (j.getObjValAs? Nat "pos").toOption.getD 0
        let some (g, _, _) := (← candidates thm).1[pos]? | throwError "no candidate"
        pure g
      let C0 ← compile goal #[]
      let root := (C0.forest.goals[0]?.bind (symOf ·.tgt)).toList
      let mut acc := #[]
      for c in H do
        try discard <| compile goal #[c]; acc := acc.push c catch _ => pure ()
      let C ← compile goal acc
      let hs := acc.foldl (fun s c => headSyms C c |>.foldl (fun s x => if s.contains x then s else s.push x) s) #[]
      return [("root", toJson root), ("H_heads", toJson hs), ("H_accepted", toJson (acc.map (·.toString)))]
    h.putStrLn (Json.mkObj ([("key", j.getObjValD "key")] ++ r)).compress
  h.flush
  return 0

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | ["pool", out] => pool out
  | ["syms", specs, out] => syms specs out
  | _ => IO.println "usage: eval_pool pool OUT | syms SPECS OUT"; return 2
