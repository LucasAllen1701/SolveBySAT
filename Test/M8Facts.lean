/-
7d-2, E5 (EVAL_PLAN §10.10 decision 6): structural facts about obstacle constants, for the
fixed family table `eval/m8_families.json`. Read-only: it imports the corpus environment
(`Eval.sourceModules`) and prints one JSON line per constant. It decides no family itself.

  lake env lean --run Test/M8Facts.lean NAMES.txt OUT.jsonl

Per constant:
- `kind`: `recursor` (a `.rec`), `auxrec` (`casesOn`, `recOn`, `brecOn`, `below`, …, or
  `noConfusion`), `matcher` (a matcher, or a constant under one, such as `match_1.splitter`),
  `other`, or `missing` (not in the environment);
- `inductive`: for a recursor or auxiliary recursor, the inductive type (the name prefix);
- for a matcher: `matcher` (the matcher itself), and `discrs`, one entry per discriminant with
  `head` (head constant of its type, or null) and `whnf_head` (head constant after `whnf` at
  default transparency), and whether each is an inductive type (`head_ind`, `whnf_ind`).
-/
import Lean
import Test.EvalCommon

open Lean Meta Eval

unsafe def importEnv (mods : Array Name) : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules (mods.map fun m => { module := m }) {} (loadExts := true)

def runMeta {α} (env : Environment) (x : MetaM α) : IO α := do
  let ctx : Core.Context := { fileName := "<m8facts>", fileMap := default, maxHeartbeats := 200000 * 1000 }
  let (a, _) ← (x.run' {} {}).toIO ctx { env }
  return a

/-- The matcher at or above `n` (`foo.match_1.splitter` → `foo.match_1`). -/
def matcherOf (env : Environment) (n : Name) : Option Name := Id.run do
  let mut p := n
  while !p.isAnonymous do
    if isMatcherCore env p then return some p
    p := p.getPrefix
  return none

def isInd (env : Environment) (n : Option Name) : Bool :=
  match n.bind env.find? with
  | some (.inductInfo _) => true
  | _ => false

def nameJson (n : Option Name) : Json := match n with
  | some n => Json.str n.toString
  | none => Json.null

def discrFacts (m : Name) : MetaM (Array Json) := do
  let some info ← getMatcherInfo? m | return #[]
  let ci ← getConstInfo m
  forallBoundedTelescope ci.type (some (info.numParams + 1 + info.numDiscrs)) fun xs _ => do
    let env ← getEnv
    let mut out := #[]
    for i in [info.numParams + 1 : xs.size] do
      let ty ← instantiateMVars (← inferType xs[i]!)
      let h := ty.getAppFn.constName?
      let w ← try (some <$> whnf ty) catch _ => pure none
      let wh := w.bind (·.getAppFn.constName?)
      out := out.push <| Json.mkObj [("head", nameJson h), ("head_ind", isInd env h),
                                     ("whnf_head", nameJson wh), ("whnf_ind", isInd env wh)]
    return out

def facts (env : Environment) (n : Name) : IO Json := do
  if (env.find? n).isNone then
    return Json.mkObj [("name", n.toString), ("kind", "missing")]
  if isRecCore env n then
    return Json.mkObj [("name", n.toString), ("kind", "recursor"), ("inductive", n.getPrefix.toString)]
  if isAuxRecursor env n || isCasesOnRecursor env n || isNoConfusion env n then
    return Json.mkObj [("name", n.toString), ("kind", "auxrec"), ("inductive", n.getPrefix.toString)]
  if let some m := matcherOf env n then
    let ds ← runMeta env (discrFacts m)
    return Json.mkObj [("name", n.toString), ("kind", "matcher"), ("matcher", m.toString),
                       ("discrs", Json.arr ds)]
  return Json.mkObj [("name", n.toString), ("kind", "other")]

unsafe def main (args : List String) : IO UInt32 := do
  let [inp, outp] := args | IO.eprintln "usage: M8Facts NAMES.txt OUT.jsonl"; return 2
  let env ← importEnv sourceModules
  let names := (← IO.FS.lines inp).filter (· ≠ "")
  -- strings are `Name.toString` of corpus constants; resolve them as the harness does
  let table : Std.HashMap String Name :=
    env.constants.fold (fun m n _ => m.insert n.toString n) {}
  let h ← IO.FS.Handle.mk outp .write
  for s in names do
    match table[s]? with
    | some n => h.putStrLn (← facts env n).compress
    | none => h.putStrLn (Json.mkObj [("name", s), ("kind", "missing")]).compress
  return 0
