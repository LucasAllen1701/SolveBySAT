/-
Milestone 7a: corpus extraction (EVAL_PLAN §2).

  eval_corpus probe <modules…>      import the modules and report sizes (memory probe)
  eval_corpus extract <outdir>      write <outdir>/corpus_A.jsonl, corpus_B.jsonl and
                                    corpus_stats.txt (counts per tier and per filter)

Deterministic: theorems are processed in name order and every sample is drawn from a
fixed seed (Test/EvalCommon.lean), so the same seed gives byte-identical files.
Run under `Test/memrun.py --vlimit-mb 2500`.
-/
import Lean
import Test.EvalCommon

open Lean Meta Eval

unsafe def importEnv (mods : Array Name) : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules (mods.map fun m => { module := m }) {} (loadExts := true)

/-- Heartbeat limit of every MetaM run (in thousands, as `maxHeartbeats`). -/
def heartbeats : Nat := 400000

def runMeta {α} (env : Environment) (x : MetaM α) : IO α := do
  let ctx : Core.Context := { fileName := "<eval>", fileMap := default,
                              maxHeartbeats := heartbeats * 1000 }
  let (a, _) ← (x.run' {} {}).toIO ctx { env }
  return a

def nameLt (a b : Name) : Bool := decide (a.toString < b.toString)

/-- A seeded uniform sample of `k` elements (partial Fisher–Yates), returned in the
original order. -/
def sample {α} [Inhabited α] (xs : Array α) (k : Nat) (seed : UInt64) : Array α := Id.run do
  if xs.size ≤ k then return xs
  let mut idx := Array.range xs.size
  let mut r : Rng := ⟨seed⟩
  for i in [0:k] do
    let (j, r') := r.range i (xs.size - 1)
    r := r'
    idx := idx.swapIfInBounds i j
  let chosen := (idx.extract 0 k).qsort (· < ·)
  return chosen.map (xs[·]!)

def jNames (ns : Array Name) : Json := Json.arr (ns.map fun n => Json.str n.toString)
def jDropped (ds : Array (Name × String)) : Json :=
  Json.arr (ds.map fun (n, r) => Json.arr #[Json.str n.toString, Json.str r])

/-- The H fields of a record (EVAL_PLAN §10.2). -/
def jH (h : OracleH) : Json := Json.mkObj [("H_main", jNames h.main), ("H_full", jNames h.full),
  ("H_data_full", jNames h.dataFull), ("H_data_dropped", jNames h.dataDropped),
  ("dropped", jDropped h.dropped), ("self_in_H", h.selfHit),
  ("H_main_removed", jDropped h.mainRemoved)]

/-- Elimination constants of a goal: those of §2.1 in its (expanded) oracle term, and the
§10.4 ones that survived the data rule. -/
def goalElims (env : Environment) (cs : Array Name) (h : OracleH) : Array Name :=
  let es := elimsOf env cs
  (es ++ h.extraElims.filter (!es.contains ·)).qsort (·.toString < ·.toString)

def gitInfo : IO (String × Bool) := do
  let h ← IO.Process.output { cmd := "git", args := #["rev-parse", "HEAD"] }
  let s ← IO.Process.output { cmd := "git", args := #["status", "--porcelain", "--untracked-files=no"] }
  return (h.stdout.trimAscii.toString, s.stdout.trimAscii.toString != "")

def header (tier : String) : IO Json := do
  let (commit, dirty) ← gitInfo
  return Json.mkObj [("header", Json.mkObj [
    ("tier", tier), ("toolchain", Lean.versionString), ("git_commit", commit),
    ("git_dirty", dirty), ("modules", jNames sourceModules),
    ("tierA_cap", tierACap), ("tierB_theorems", tierBTheorems),
    ("tierB_per_theorem", tierBPerTheorem), ("tierB_cap", tierBCap),
    ("walk_budget", walkBudget), ("heartbeats", heartbeats),
    ("seeds", Json.mkObj [("A_sample", seedASample.toNat), ("B_theorems", seedBTheorems.toNat),
       ("B_per_theorem", seedBPerTheorem.toNat), ("B_total", seedBTotal.toNat)]),
    ("generated_suffixes", Json.arr (generatedSuffixes.toArray.map Json.str))])]

/-- Tier A filters, in order. `none` keeps the theorem. -/
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

structure Stats where
  lines : Array String := #[]

def Stats.add (s : Stats) (l : String) : Stats := { lines := s.lines.push l }

def countBy (xs : Array String) : Array (String × Nat) := Id.run do
  let mut keys : Array String := #[]
  let mut m : Std.HashMap String Nat := {}
  for x in xs do
    unless m.contains x do keys := keys.push x
    m := m.insert x (m.getD x 0 + 1)
  return keys.map fun k => (k, m.getD k 0)

unsafe def extract (out : System.FilePath) : IO UInt32 := do
  IO.FS.createDirAll out
  let env ← importEnv sourceModules
  let mut st : Stats := {}
  -- ## Tier A
  let inSource := fun (n : Name) => match env.getModuleIdxFor? n with
    | some i => sourceModules.any (·.isPrefixOf env.header.moduleNames[i.toNat]!)
    | none => false
  let all := (env.constants.map₁.toList.filter fun (n, _) => inSource n).toArray.qsort
    (fun a b => nameLt a.1 b.1)
  st := st.add s!"Tier A: constants in {sourceModules}: {all.size}"
  let verdicts ← runMeta env do
    all.mapM fun (n, ci) => return (n, ← tierAReject env n ci)
  for (r, k) in countBy (verdicts.filterMap (·.2)) do
    st := st.add s!"  dropped: {r}: {k}"
  let kept := verdicts.filterMap fun (n, r) => if r.isNone then some n else none
  st := st.add s!"  remaining after filters: {kept.size}"
  let tierA := sample kept tierACap seedASample
  st := st.add s!"  Tier A sample (cap {tierACap}, seed {seedASample}): {tierA.size}"
  let mut linesA := #[(← header "A").compress]
  let mut nElimA := 0
  let mut nSelfA := 0
  for n in tierA do
    let some (.thmInfo t) := env.find? n | throw (IO.userError s!"lost {n}")
    let j ← runMeta env do
      let cs := usedConstants env t.value
      let h ← splitH t.type n cs
      let elims := goalElims env cs h
      let mod := env.header.moduleNames[(env.getModuleIdxFor? n).get!.toNat]!
      return Json.mkObj [("id", s!"A/{n}"), ("tier", "A"), ("thm", n.toString),
        ("module", mod.toString), ("type", toString (← ppExpr t.type)),
        ("proof_size", dagSize t.value), ("uses_elim", !elims.isEmpty),
        ("elim", jNames elims)] |>.mergeObj (jH h)
    if (j.getObjValD "uses_elim") == Json.bool true then nElimA := nElimA + 1
    if (j.getObjValD "self_in_H") == Json.bool true then
      nSelfA := nSelfA + 1; st := st.add s!"  SELF IN H: {n}"
    linesA := linesA.push j.compress
  st := st.add s!"  of which the proof uses an elimination constant: {nElimA}"
  st := st.add s!"  goals whose own declaration was in H (removed): {nSelfA}"
  IO.FS.writeFile (out / "corpus_A.jsonl") (String.intercalate "\n" linesA.toList ++ "\n")
  -- ## Tier B
  let thmsB := sample tierA tierBTheorems seedBTheorems
  st := st.add s!"Tier B: theorems sampled from Tier A (seed {seedBTheorems}): {thmsB.size}"
  let mut seen : Std.HashSet (Expr × Array Name) := {}
  let mut rng : Rng := ⟨seedBPerTheorem⟩
  let mut nCand := 0
  let mut nTrunc := 0
  let mut nWalkErr := 0
  let mut nDupLocal := 0
  let mut nDupGlobal := 0
  let mut nCapped := 0
  let mut nTheoremsWithGoals := 0
  let mut goals : Array (Name × Nat × Expr × Expr × Nat × Array Name × OracleH) := #[]
  for thm in thmsB do
    let res ← (runMeta env do
      let (cands, trunc) ← candidates thm
      let withH ← cands.mapM fun (g, p, k) => do
        let h ← splitH g thm (usedConstants env p)
        return (g, p, k, h.full, h)
      return (withH, trunc)).toBaseIO
    let (cands, trunc) ← match res with
      | .ok r => pure r
      | .error _ => nWalkErr := nWalkErr + 1; pure (#[], false)
    if trunc then nTrunc := nTrunc + 1
    nCand := nCand + cands.size
    -- dedupe by (closed goal type up to α-equivalence, H), first occurrence in walk order
    let mut fresh := #[]
    let mut seenHere : Std.HashSet (Expr × Array Name) := {}
    for (pos, (g, p, k, h, d)) in cands.zipIdx.map (fun (c, i) => (i, c)) do
      if seenHere.contains (g, h) then nDupLocal := nDupLocal + 1; continue
      seenHere := seenHere.insert (g, h)
      if seen.contains (g, h) then nDupGlobal := nDupGlobal + 1; continue
      fresh := fresh.push (thm, pos, g, p, k, h, d)
    let chosen := sample fresh tierBPerTheorem rng.next.1
    rng := rng.next.2
    nCapped := nCapped + (fresh.size - chosen.size)
    if chosen.size > 0 then nTheoremsWithGoals := nTheoremsWithGoals + 1
    for c in chosen do seen := seen.insert (c.2.2.1, c.2.2.2.2.2.1)
    goals := goals ++ chosen
  st := st.add s!"  walks cut at the visit budget ({walkBudget}): {nTrunc}; walk errors: {nWalkErr}"
  st := st.add s!"  candidates (proof-valued applications headed by a constant or hypothesis): {nCand}"
  st := st.add s!"  dropped: duplicate within its theorem: {nDupLocal}"
  st := st.add s!"  dropped: duplicate of a goal from an earlier theorem: {nDupGlobal}"
  st := st.add s!"  dropped: over the per-theorem cap ({tierBPerTheorem}, seed {seedBPerTheorem}): {nCapped}"
  st := st.add s!"  goals before the total cap: {goals.size} (from {nTheoremsWithGoals} theorems)"
  let goalsB := sample goals tierBCap seedBTotal
  st := st.add s!"  Tier B sample (cap {tierBCap}, seed {seedBTotal}): {goalsB.size}"
  let mut linesB := #[(← header "B").compress]
  let mut nSanityFail := 0
  let mut nElimB := 0
  let mut nSelfB := 0
  for (thm, pos, g, p, k, h, d) in goalsB do
    let j ← runMeta env do
      let ok ← try isDefEq (← inferType p) g catch _ => pure false
      let (est, estCut) ← nodeEstimate p
      let elims := goalElims env (usedConstants env p) d
      return Json.mkObj [("id", s!"B/{thm}/{pos}"), ("tier", "B"), ("thm", thm.toString),
        ("pos", pos), ("nctx", k), ("goal", toString (← ppExpr g)),
        ("node_est", est), ("node_est_cut", estCut), ("oracle_size", dagSize p),
        ("uses_elim", !elims.isEmpty), ("elim", jNames elims), ("sanity", ok)] |>.mergeObj (jH d)
    if j.getObjValD "sanity" != Json.bool true then nSanityFail := nSanityFail + 1
    if j.getObjValD "uses_elim" == Json.bool true then nElimB := nElimB + 1
    if j.getObjValD "self_in_H" == Json.bool true then
      nSelfB := nSelfB + 1; st := st.add s!"  SELF IN H: B/{thm}/{pos}"
    linesB := linesB.push j.compress
  st := st.add s!"  of which the oracle term uses an elimination constant: {nElimB}"
  st := st.add s!"  goals whose source theorem was in H (removed): {nSelfB}"
  st := st.add s!"  sanity check (inferType of the oracle term defeq to the goal) failures: {nSanityFail}"
  IO.FS.writeFile (out / "corpus_B.jsonl") (String.intercalate "\n" linesB.toList ++ "\n")
  IO.FS.writeFile (out / "corpus_stats.txt") (String.intercalate "\n" st.lines.toList ++ "\n")
  for l in st.lines do IO.println l
  return if nSanityFail == 0 then 0 else 1

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | ["extract", out] => extract out
  | "probe" :: mods =>
    let env ← importEnv (mods.toArray.map String.toName)
    IO.println s!"modules {env.header.moduleNames.size}, constants {env.constants.map₁.size}"
    return 0
  | _ => IO.println "usage: eval_corpus probe <modules…> | extract <outdir>"; return 2
