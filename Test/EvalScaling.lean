/-
Milestone 7c, EVAL_PLAN §4.1 (synthetic typed scaling) and §10.9 (4.1 decisions 1–3).

  eval_scaling cell FAM K N CFG MODE   one grid cell, one JSON line on stdout

FAM ∈ {S, T1, T2, T3} (`Test/Synth.lean`), K the number of distractors (the first K `monoᵢ`
of the family), N the node bound, CFG one of the five configurations below, MODE `count`
(`countOnly`) or `full` (a full encode, for the decision 1 check). The goal is SPEC 7.3's
chain `∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w` (L1) with H = `Nat.le_trans`
followed by the distractors. It goes through the Lean compile path (`compile`), so type
templates are real. Nothing is solved.
-/
import SolveBySat
import Lean
import Test.BenchForests

open Lean Meta SolveBySat

unsafe def importEnv (mods : Array Name) : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot) [".lake/build/lib/lean"]
  importModules (mods.map fun m => { module := m }) {} (loadExts := true)

/-- The five configurations of EVAL_PLAN §4.1, and E6's `no_typing` (§10.10 decision 7). -/
def configOf : String → Option EncodeOptions
  | "all" => some {}
  | "none" => some EncodeOptions.allOff
  | "no_candidate" => some { candidatePruning := false }
  | "no_pair" => some { pairPruning := false }
  | "no_static" => some { staticTyping := false }
  -- E6 (EVAL_PLAN §10.10 decision 7, exploratory, not part of the pre-registered grid):
  -- both typing filters off, every other refinement on
  | "no_typing" => some { staticTyping := false, candidatePruning := false }
  | _ => none

def distractors (fam : String) (k : Nat) : Array Name :=
  (Array.range k).map fun i => Name.mkStr (Name.mkStr (Name.mkSimple "Synth") fam) s!"mono{i}"

def main (args : List String) : IO UInt32 := do
  let ["cell", fam, kS, nS, cfg, mode] := args
    | IO.eprintln "usage: eval_scaling cell FAM K N CFG count|full"; return 2
  let some k := kS.toNat? | return 2
  let some N := nS.toNat? | return 2
  let some opts := configOf cfg | IO.eprintln s!"unknown config {cfg}"; return 2
  unless ["S", "T1", "T2", "T3"].contains fam do IO.eprintln s!"unknown family {fam}"; return 2
  let env ← unsafe importEnv #[`Init, `Test.Synth]
  let ctx : Core.Context := { fileName := "<eval_scaling>", fileMap := default, maxHeartbeats := 0 }
  let ((goal, H0), _, _) ← (leanGoal "L1").toIO ctx { env }
  let H := H0 ++ distractors fam k
  -- compile each constant alone first, as the harness does, to report rejections
  let mut acc := #[]
  let mut rej := #[]
  for c in H do
    match ← ((compile goal #[c]).toIO ctx { env }).toBaseIO with
    | .ok _ => acc := acc.push c
    | .error e => rej := rej.push (c.toString, toString e)
  let (C, _, _) ← (compile goal acc).toIO ctx { env }
  let P := C.forest
  let t0 ← IO.monoNanosNow
  let E := encode P N { opts with countOnly := mode == "count" }
  -- force the whole encoding
  let nv := E.cnf.nVars
  let ncl := E.cnf.numClauses
  let lits := E.cnf.clauses.foldl (fun n c => n + c.size) 0
  let t1 ← IO.monoNanosNow
  let fams := Json.mkObj (E.cnf.familyCounts.toList.map fun (f, n) => (f, Json.num n))
  IO.println (Json.mkObj [("family", Json.str fam), ("k", toJson k), ("N", toJson N), ("config", Json.str cfg),
    ("mode", Json.str mode), ("H_size", toJson H.size), ("H_accepted", toJson acc.size),
    ("H_rejected", toJson (rej.map fun (c, m) => Json.arr #[Json.str c, Json.str m])),
    ("forest_clauses", toJson P.clauses.size), ("forest_goals", toJson P.goals.size),
    ("vars", toJson nv), ("clauses", toJson ncl), ("stored_clauses", toJson E.cnf.clauses.size),
    ("literals", toJson lits), ("families", fams), ("encode_ms", toJson ((t1 - t0) / 1000000)),
    ("typing", toJson E.info.typing), ("pairs", toJson E.info.pairs)]).compress
  return 0
