/-
Milestone 5, pure tests: built arguments (SPEC §6.9).
1. `Reference` with groundness (new in milestone 5) reproduces the minimal N of the
   groundness-sensitive forest tests of milestone 1 (T1, T4, T4b, T5, T6b).
2. Requirement 3: a variable with a data child satisfies 6.8 through the child's value
   object (the true groundness witness is a `.value` object), and without the data
   child there is no proof.
3. Requirement 5: differential test on random forests with data constants and data
   positions, groundness on in both the encoder and `Reference`; zero mismatches. Mutation:
   with the 6.9 static filter off (a data clause may close a proposition position, a
   proof clause a data position) mismatches appear.
-/
import SolveBySat
import Test.Util

open SolveBySat

def c (s : String) : Term := .const s
def V (n : String) : Term := .var n
def atm (p : String) (as : List Term) : Term := .app p as.toArray
def goal (tgt : Term) (eig : List String := []) (hyps : List ClauseT := []) : GoalT := .mk tgt eig hyps
def clause (name : String) (head : Term) (vars : List String := []) (prems : List GoalT := []) : ClauseT :=
  .mk name head vars prems
def forest (g : GoalT) (cs : List ClauseT) : Forest :=
  match Forest.build g cs with
  | .ok F => F
  | .error e => panic! s!"bad forest: {e}"

/-- Turn global clause `cid` into a data clause with head `head` (already its head) and
value `v`, and give its variables listed in `typed` data positions. -/
def withData (F : Forest) (cid : Nat) (v : Option Term) (typed : List (String × Term)) : Forest := Id.run do
  let mut F := F
  let cl := F.clauses[cid]!
  let mut dps := #[]
  for (b, ty) in typed do
    let gid := F.goals.size
    F := { F with goals := F.goals.push { tgt := ty, eig := #[], hyps := #[],
                                          env := Forest.sortStrs (cl.env ++ cl.vars), dataVar := some b } }
    dps := dps.push (b, gid)
  { F with clauses := F.clauses.set! cid { cl with dataVal := v, dataPos := dps } }

def solveForest (P : Forest) (N : Nat) (opts : EncodeOptions := {}) : IO (Option (Array SkelNode) × Encoding × Array Bool) := do
  let E := encode P N opts
  match ← runSolver E.cnf with
  | .unsat => return (none, E, #[])
  | .sat m =>
    match readSkeleton P E.vars m with
    | .ok sk => return (some sk, E, m)
    | .error e => throw <| IO.userError s!"bad skeleton: {e}"

structure Tally where
  pass : Nat := 0
  fail : Nat := 0

def Tally.check (t : Tally) (ok : Bool) (msg : String) : IO Tally := do
  IO.println s!"{if ok then "PASS" else "FAIL"} {msg}"
  return if ok then { t with pass := t.pass + 1 } else { t with fail := t.fail + 1 }

/-! ## 1. Reference groundness on milestone 1 forests -/

def le (a b : Term) : Term := atm "le" [a, b]
def t1 : Forest :=
  let (x, y, z, w) := (V "x", V "y", V "z", V "w")
  forest (goal (le x w) ["x", "y", "z", "w"] [clause "h1" (le x y), clause "h2" (le y z), clause "h3" (le z w)])
    [clause "le_trans" (le (V "a") (V "c")) ["a", "b", "c"] [goal (le (V "a") (V "b")), goal (le (V "b") (V "c"))]]
def t4 (fixed : Bool) : Forest :=
  let h := clause "h" (c "P0") ["y"] [goal (atm "Q" [V "y"])]
  let q := if fixed then clause "q" (atm "Q" [c "k"]) else clause "q" (atm "Q" [V "z"]) ["z"]
  forest (goal (c "P0")) [h, q]
def t5 : Forest :=
  forest (goal (c "G0")) [clause "r" (atm "R" [V "x", atm "f" [V "x"]]) ["x"],
                          clause "g" (c "G0") ["y"] [goal (atm "R" [V "y", V "y"])]]
def t6b : Forest :=
  forest (goal (c "G0"))
    [clause "k" (c "G0") ["b", "cc"] [goal (atm "A1" [V "b", V "cc"]), goal (atm "A2" [V "cc"]), goal (atm "A3" [V "b"])],
     clause "f1" (atm "A1" [atm "f" [V "u"], V "u"]) ["u"], clause "f2" (atm "A2" [c "zero"]),
     clause "f3" (atm "A3" [atm "f" [c "zero"]])]

def minRef (P : Forest) : Option Nat := (List.range' 1 6).find? (Reference.provable P · (groundness := true))

/-! ## 2. A variable satisfies 6.8 through its data child -/

/-- `G ← ex(w) : P(w)` with `p : ∀ x, P(x)`; `w : D` is determined by nothing, and no
term of type `D` occurs anywhere; the data clause `z : D` builds `z0`. -/
def dataForest (withZ : Bool) : Forest := Id.run do
  let ex := clause "ex" (c "G") ["w"] [goal (atm "P" [V "w"])]
  let p := clause "p" (atm "P" [V "x"]) ["x"]
  let z := clause "z" (c "D")
  let F := forest (goal (c "G")) ([ex, p] ++ if withZ then [z] else [])
  let F := withData F 0 none [("w", c "D")]
  if withZ then withData F 2 (some (c "z0")) [] else F

/-! ## 3. Random forests with data -/

partial def rndTermD (vs : Array String) (d : Nat) : RM Term := do
  let r ← rnd 0 999
  if !vs.isEmpty && r < 550 then return .var (← choice (vs.qsort (· < ·)))
  if r < 800 || d ≥ 1 then return .const (← choice #["k1", "k1", "k2", "z0", "w0"])
  return .app (← choice #["f", "s", "m"]) #[← rndTermD vs (d + 1)]

def rndAtomD (vs : Array String) : RM Term := do
  if (← rnd 0 999) < 80 then return .const "N"   -- a proposition that looks like a data type
  let p ← choice #["P", "P", "Q"]
  if p == "Q" then return .app p #[← rndTermD vs 0, ← rndTermD vs 0] else return .app p #[← rndTermD vs 0]

structure GenSt where
  k : Nat := 0
  /-- Data type of each clause variable that has one. -/
  types : Array (String × Term) := #[]

abbrev GM := StateT GenSt RM

def fresh (p : String) : GM String := modifyGet fun s => (s!"{p}{s.k + 1}", { s with k := s.k + 1 })

mutual
partial def rndClauseD (env : Array String) (depth : Nat) : GM ClauseT := do
  let mut vs := #[]
  for _ in [0:← (choice #[0, 1, 1, 2] : RM _)] do
    let v ← fresh "v"
    vs := vs.push v
    let ty ← (choice #[0, 1, 1, 1, 2] : RM _)
    if ty == 1 then modify fun s => { s with types := s.types.push (v, .const "N") }
    if ty == 2 then modify fun s => { s with types := s.types.push (v, .const "M") }
  let scope := env ++ vs
  let mut prems := #[]
  let np ← if depth < 2 then (choice #[0, 1, 1, 2] : RM _) else pure 0
  for _ in [0:np] do prems := prems.push (← rndGoalD scope (depth + 1))
  let name ← fresh "c"
  return .mk name (← (rndAtomD scope : RM _)) vs.toList prems.toList

partial def rndGoalD (env : Array String) (depth : Nat) : GM GoalT := do
  let mut eig := #[]
  if ← (chance 300 : RM _) then eig := eig.push (← fresh "e")
  let scope := env ++ eig
  let mut hyps := #[]
  if (← (chance 300 : RM _)) && depth < 2 then hyps := hyps.push (← rndClauseD scope (depth + 1))
  return .mk (← (rndAtomD scope : RM _)) eig.toList hyps.toList
end

/-- A random forest with data constants (`z : N := z0`, and a random subset of
`s : N → N := s(n)`, `m : N → M := m(x)`, `w : M := w0`) and data positions for the clause
variables whose type is the head of some data constant (the compiler's rule). -/
def rndDataProblem : RM Forest := do
  let ((g, cs), st) ← (do
      let g ← rndGoalD #[] 0
      let mut cs := #[]
      for _ in [0:← (rnd 3 6 : RM _)] do cs := cs.push (← rndClauseD #[] 0)
      return (g, cs) : GM _).run {}
  let all := #[("z", c "N", [], c "z0"), ("s", c "N", ["n"], atm "s" [V "n"]),
               ("m", c "M", ["x"], atm "m" [V "x"]), ("w", c "M", [], c "w0")]
  let mut data := #[]
  -- `z` (a nullary builder) always; the others at random
  for h : i in [0:all.size] do
    if i == 0 then data := data.push all[i]
    else if ← chance 600 then data := data.push all[i]
  let dataClauses := data.map fun (n, h, vs, _) => ClauseT.mk n h vs []
  let F := forest g (cs.toList ++ dataClauses.toList)
  let heads := data.map (·.2.1)
  let types : Array (String × Term) := st.types ++ #[("n", c "N"), ("x", c "N")]
  let tyOf := fun (b : String) => (types.find? (·.1 == b)).map (·.2)
  let mut F := F
  let nProof := F.clauses.size - data.size
  for cid in [0:F.clauses.size] do
    let cl := F.clauses[cid]!
    let typed := cl.vars.toList.filterMap fun b => (tyOf b).bind fun ty => if heads.contains ty then some (b, ty) else none
    let v := if cid < nProof then none else some data[cid - nProof]!.2.2.2
    F := withData F cid v typed
  match F.check with
  | .ok () => return F
  | .error e => panic! s!"bad data forest: {e}"

def dataProblemOf (seed : Nat) : Forest := (rndDataProblem.run ⟨seed.toUInt64 * 7907 + 101⟩).1

structure DiffStats where
  total : Nat := 0
  provable : Nat := 0
  mismatches : Array (Nat × Nat × Bool × Bool) := #[]
  minSizes : Array (Nat × Nat) := #[]
  /-- SAT instances whose decoded skeleton uses a data node. -/
  dataUsed : Nat := 0

def diffChunk (seeds : List Nat) (opts : EncodeOptions) (stopAtFirst : Bool) : IO DiffStats := do
  let mut st : DiffStats := {}
  for seed in seeds do
    let P := dataProblemOf seed
    let mut minN : Option Nat := none
    for N in [1:6] do
      let r := Reference.provable P N (groundness := true)
      let (sk, _, _) ← solveForest P N opts
      st := { st with total := st.total + 1, provable := st.provable + (if r then 1 else 0) }
      if let some sk := sk then
        if sk.any (fun n => P.goals[n.goal]!.dataVar.isSome) then st := { st with dataUsed := st.dataUsed + 1 }
      if r && minN.isNone then minN := some N
      if sk.isSome != r then
        st := { st with mismatches := st.mismatches.push (seed, N, r, sk.isSome) }
        if stopAtFirst then return st
    if let some n := minN then st := { st with minSizes := st.minSizes.push (seed, n) }
  return st

def diffRun (seeds : Nat) (opts : EncodeOptions) (stopAtFirst := false) (workers := 4) : IO DiffStats := do
  let chunks := (List.range workers).map fun w => (List.range seeds).filter (· % workers == w)
  let tasks ← chunks.mapM fun ch => IO.asTask (diffChunk ch opts stopAtFirst) .dedicated
  let mut out : DiffStats := {}
  for tk in tasks do
    match ← IO.wait tk with
    | .error e => throw e
    | .ok s => out := { total := out.total + s.total, provable := out.provable + s.provable,
                        mismatches := out.mismatches ++ s.mismatches, minSizes := out.minSizes ++ s.minSizes,
                        dataUsed := out.dataUsed + s.dataUsed }
  return out

def histogram (xs : Array (Nat × Nat)) : List (Nat × Nat) :=
  (List.range 7).filterMap fun n =>
    let k := (xs.filter (·.2 == n)).size
    if k == 0 then none else some (n, k)

def main (args : List String) : IO UInt32 := do
  let seeds := (args[0]? >>= String.toNat?).getD 3000
  let workers := (args[1]? >>= String.toNat?).getD 4
  let cfg := args[2]?.getD "all"
  let some base := EncodeOptions.config cfg | IO.println s!"unknown configuration {cfg}"; return 2
  IO.println s!"solver: {← findSolver}; refinements: {cfg}"
  let mut t : Tally := {}
  -- 1
  for (name, P, expect) in [("T1", t1, some 5), ("T4", t4 false, none), ("T4b", t4 true, some 2),
                            ("T5", t5, none), ("T6b", t6b, some 4)] do
    let got := minRef P
    t ← t.check (got == expect) s!"Reference with groundness on {name}: min N = {got} (expected {expect})"
  -- 2
  let P := dataForest true
  let (sk2, _, _) ← solveForest P 2 base
  t ← t.check sk2.isNone "data forest: no proof with 2 nodes (w must be built)"
  let (sk3, E3, m3) ← solveForest P 3 base
  match sk3 with
  | none => t ← t.check false "data forest: a proof with 3 nodes"
  | some sk =>
    let exNode := (sk.find? (fun n => P.clauses[n.clause]!.name == "ex")).get!
    let wit := (E3.sv[(exNode.node, exNode.clause, "w")]!).find? fun (_, sv, _) => BLit.eval m3 sv
    let viaValue := match wit with
      | some (.value _ _ _ _ _, _, _) => true
      | _ => false
    t ← t.check (viaValue && exNode.dataChildren.any Option.isSome)
      s!"data forest: proof {renderSkeleton P sk 0}; the groundness witness of w is {repr (wit.map (·.1))}, a value object of its data child"
  let (skn, _, _) ← solveForest (dataForest false) 6 base
  t ← t.check skn.isNone "data forest without the data clause: no proof with 6 nodes"
  -- 3
  let t0 ← IO.monoMsNow
  let d ← diffRun seeds base (workers := workers)
  let deep := (d.minSizes.filter (·.2 ≥ 2)).size
  for (s, N, r, x) in d.mismatches do IO.println s!"MISMATCH (data) seed {s} N {N} ref {r} sat {x}"
  IO.println s!"differential with data: {d.total} comparisons, {d.provable} provable instances, {d.mismatches.size} mismatches, min-size histogram {histogram d.minSizes}, {deep} forests with min size ≥ 2, {d.dataUsed} SAT instances whose proof uses a data node [{((← IO.monoMsNow) - t0) / 1000}s]"
  t ← t.check (d.total ≥ 5000 && deep ≥ 100 && d.mismatches.isEmpty && d.dataUsed ≥ 100)
    "differential with data (need ≥ 5000 comparisons, ≥ 100 forests of min size ≥ 2, ≥ 100 proofs using a data node, 0 mismatches)"
  let m ← diffRun seeds { base with dataFilter := false } (stopAtFirst := true) (workers := workers)
  let first := m.mismatches.toList.take 3 |>.map fun (s, N, r, x) => s!"seed {s} N {N} (ref {r}, sat {x})"
  t ← t.check (!m.mismatches.isEmpty) s!"mutation 'static filter of 6.9 off': mismatches found, e.g. {first}"
  IO.println s!"M5: {t.pass} passed, {t.fail} failed"
  return if t.fail == 0 then 0 else 1
