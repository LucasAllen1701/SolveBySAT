/-
Milestone 1 acceptance: the forest encoder (SPEC §9.1).
- forest tests T1 to T9 give the exact minimal N (none = unsatisfiable for every N ≤ 6);
- differential test against `Reference` for every N ≤ 5, groundness off on both sides:
  ≥ 5,000 comparisons, ≥ 100 forests whose smallest proof has ≥ 2 nodes, zero mismatches;
- mutation checks: switching off the scope clauses, or the occurs check, gives a mismatch.
Additionally, the CNF size of every forest test at every N ≤ 6 must equal the prototype's
(`Test/proto/proto_counts.py`), which checks the port family by family in aggregate.
-/
import SolveBySat
import Test.Util

open SolveBySat

/-! ## Forest tests (port of reference/tests.py) -/

def c (s : String) : Term := .const s
def V (n : String) : Term := .var n
def atm (p : String) (as : List Term) : Term := .app p as.toArray
def le (a b : Term) : Term := atm "le" [a, b]
def goal (tgt : Term) (eig : List String := []) (hyps : List ClauseT := []) : GoalT := .mk tgt eig hyps
def clause (name : String) (head : Term) (vars : List String := []) (prems : List GoalT := []) : ClauseT :=
  .mk name head vars prems
def forest (g : GoalT) (cs : List ClauseT) : Forest :=
  match Forest.build g cs with
  | .ok F => F
  | .error e => panic! s!"bad forest: {e}"

def t1 : Forest :=
  let (x, y, z, w) := (V "x", V "y", V "z", V "w")
  let g := goal (le x w) ["x", "y", "z", "w"] [clause "h1" (le x y), clause "h2" (le y z), clause "h3" (le z w)]
  let tr := clause "le_trans" (le (V "a") (V "c")) ["a", "b", "c"] [goal (le (V "a") (V "b")), goal (le (V "b") (V "c"))]
  forest g [tr]

def t2 (extra : Bool) : Forest :=
  let m := clause "m" (c "C") [] [goal (c "B") [] [clause "ha" (c "A")], goal (c "A")]
  let bb := clause "bb" (c "B") [] [goal (c "A")]
  forest (goal (c "C")) ([m, bb] ++ if extra then [clause "a" (c "A")] else [])

def t3 (legit : Bool) : Forest :=
  let inner := goal (if legit then atm "Eq" [V "y", V "y"] else atm "Eq" [V "x", V "y"]) ["y"]
  let ex := clause "ex" (c "Goal") (if legit then [] else ["x"]) [inner]
  let refl := clause "refl" (atm "Eq" [V "z", V "z"]) ["z"]
  forest (goal (c "Goal")) [ex, refl]

def t4 (fixed : Bool) : Forest :=
  let h := clause "h" (c "P0") ["y"] [goal (atm "Q" [V "y"])]
  let q := if fixed then clause "q" (atm "Q" [c "k"]) else clause "q" (atm "Q" [V "z"]) ["z"]
  forest (goal (c "P0")) [h, q]

def t5 : Forest :=
  let r := clause "r" (atm "R" [V "x", atm "f" [V "x"]]) ["x"]
  let g := clause "g" (c "G0") ["y"] [goal (atm "R" [V "y", V "y"])]
  forest (goal (c "G0")) [r, g]

def t6 (consistent : Bool) : Forest :=
  let k := clause "k" (c "G0") ["b", "cc"]
    [goal (atm "A1" [V "b", V "cc"]), goal (atm "A2" [V "cc"]), goal (atm "A3" [V "b"])]
  let f1 := clause "f1" (atm "A1" [atm "f" [V "u"], V "u"]) ["u"]
  let f2 := clause "f2" (atm "A2" [c "zero"])
  let f3 := clause "f3" (atm "A3" [atm "f" [if consistent then c "zero" else c "one"]])
  forest (goal (c "G0")) [k, f1, f2, f3]

def t7 : Forest :=
  let m := clause "m" (atm "R" [V "x"]) ["x"]
    [goal (atm "Q" [V "x", V "y"]) ["y"] [clause "hp" (atm "P" [V "x", V "y"])]]
  let pq := clause "pq" (atm "Q" [V "s", V "t"]) ["s", "t"] [goal (atm "P" [V "s", V "t"])]
  forest (goal (atm "R" [V "a"]) ["a"]) [m, pq]

def t8 : Forest :=
  let hf := clause "hf" (atm "P" [atm "s" [V "n"]]) ["n"] [goal (atm "P" [V "n"])]
  forest (goal (atm "P" [atm "s" [atm "s" [V "o"]]]) ["o"] [clause "h0" (atm "P" [V "o"]), hf]) []

def t9 : Forest :=
  let L := clause "L" (atm "F" [V "x"]) ["x"] [goal (atm "B" [V "x"]) [] [clause "hP" (atm "P" [V "x"])]]
  let r1 := clause "r1" (atm "B" [c "ka"]) [] [goal (atm "F" [c "kb"])]
  let r2 := clause "r2" (atm "B" [c "kb"]) [] [goal (atm "P" [c "ka"]), goal (atm "P" [c "kb"])]
  forest (goal (atm "F" [c "ka"])) [L, r1, r2]

/-- (name, forest, expected minimal N). -/
def forestTests : List (String × Forest × Option Nat) := [
  ("T1 le_trans chain", t1, some 5),
  ("T2 out-of-scope hypothesis", t2 false, none),
  ("T2b with A available", t2 true, some 4),
  ("T3 eigenvariable escape", t3 false, none),
  ("T3b forall y, y = y", t3 true, some 2),
  ("T4 undetermined argument", t4 false, none),
  ("T4b determined argument", t4 true, some 2),
  ("T5 occurs check", t5, none),
  ("T6 jointly inconsistent", t6 false, none),
  ("T6b consistent", t6 true, some 4),
  ("T7 nested intro", t7, some 3),
  ("T8 local hypothesis reused", t8, some 3),
  ("T9 outer instance of a re-introduced hypothesis", t9, some 6)]

/-- CNF sizes (vars, clauses) for N = 1..6 from `python3 Test/proto/proto_counts.py`. -/
def protoSizes : List (String × Array (Nat × Nat)) := [
  ("T1", #[(133, 844), (350, 2978), (651, 6917), (1036, 13176), (1505, 22270), (1974, 32854)]),
  ("T2", #[(9, 35), (22, 87), (39, 167), (60, 286), (85, 455), (114, 685)]),
  ("T2b", #[(10, 42), (24, 104), (42, 197), (64, 332), (90, 520), (120, 772)]),
  ("T3", #[(36, 82), (87, 279), (177, 740), (266, 1350), (390, 2345), (513, 3529)]),
  ("T3b", #[(21, 66), (51, 191), (102, 458), (154, 790), (225, 1315), (297, 1927)]),
  ("T4", #[(24, 29), (57, 89), (108, 203), (162, 366), (240, 625), (315, 943)]),
  ("T4b", #[(23, 32), (53, 97), (96, 218), (142, 390), (205, 660), (267, 991)]),
  ("T5", #[(41, 88), (116, 362), (228, 902), (388, 1812), (565, 2980), (780, 4528)]),
  ("T6", #[(83, 269), (213, 987), (372, 2182), (634, 4506), (895, 7285), (1203, 10931)]),
  ("T6b", #[(75, 224), (197, 865), (348, 1960), (572, 3890), (855, 6755), (1155, 10217)]),
  ("T7", #[(77, 233), (205, 913), (384, 2249), (614, 4450), (895, 7725), (1173, 11605)]),
  ("T8", #[(100, 323), (376, 1556), (852, 3965), (1580, 7912), (2480, 13015), (3636, 19738)]),
  ("T9", #[(29, 133), (66, 344), (117, 698), (172, 1156), (245, 1855), (318, 2668)])]

/-- Encode, solve, and on SAT read and render the skeleton. -/
def solveForest (P : Forest) (N : Nat) (opts : EncodeOptions := {}) : IO (Option String × Encoding) := do
  let E := encode P N opts
  match ← runSolver E.cnf with
  | .unsat => return (none, E)
  | .sat m =>
    match readSkeleton P E.vars m with
    | .ok sk => return (some (renderSkeleton P sk 0), E)
    | .error e => throw <| IO.userError s!"bad skeleton: {e}"

structure Tally where
  pass : Nat := 0
  fail : Nat := 0

def Tally.check (t : Tally) (ok : Bool) : Tally :=
  if ok then { t with pass := t.pass + 1 } else { t with fail := t.fail + 1 }

def runForestTests (base : EncodeOptions) (t : Tally) : IO Tally := do
  let mut t := t
  for (name, P, expect) in forestTests do
    let t0 ← IO.monoMsNow
    let mut found : Option Nat := none
    let mut term := ""
    let mut last : Option Encoding := none
    for N in [1:7] do
      let (r, E) ← solveForest P N base
      last := some E
      if let some s := r then
        found := some N; term := s; break
    let ok := found == expect
    t := t.check ok
    let E := last.get!
    IO.println s!"{if ok then "PASS" else "FAIL"} {name}: min N = {found} (expected {expect}) {term}  [{(← IO.monoMsNow) - t0} ms, last CNF {E.cnf.nVars} vars {E.cnf.clauses.size} clauses]"
  return t

def runSizeTests (t : Tally) : IO Tally := do
  let mut t := t
  let mut bad := #[]
  for ((_, P, _), (short, sizes)) in forestTests.zip protoSizes do
    for N in [1:7] do
      let E := encode P N (EncodeOptions.allOff { protoRank := true })
      let got := (E.cnf.nVars, E.cnf.clauses.size)
      if got != sizes[N-1]! then bad := bad.push s!"{short} N={N}: got {got}, prototype {sizes[N-1]!}"
  for b in bad do IO.println s!"FAIL size {b}"
  t := t.check bad.isEmpty
  IO.println s!"{if bad.isEmpty then "PASS" else "FAIL"} CNF sizes equal the prototype's for T1-T9 at N = 1..6 (78 instances, prototype rank width, all refinements off)"
  let E := encode t1 5 (EncodeOptions.allOff { protoRank := true })
  IO.println s!"  T1 at N=5 (prototype rank width): {repr E.info}"
  IO.println s!"  families: {E.cnf.familyCounts}"
  return t

/-! ## Differential test (port of reference/diff.py) -/

/-- Random argument term. `nb` is the number of enclosing term binders. With
`binders := false` this is exactly the port of diff.py's `term` (same random stream). With
`binders := true` (milestone 4) it also produces `lam(T, body)` and, under a binder,
`bvar:i` leaves. -/
partial def rndTerm (vs : Array String) (d : Nat) (binders : Bool := false) (nb : Nat := 0) : RM Term := do
  if !binders then
    let r ← rnd 0 999
    if !vs.isEmpty && r < 600 then return .var (← choice (vs.qsort (· < ·)))
    if r < 850 || d ≥ 1 then return .const (← choice #["k1", "k1", "k2"])
    return .app "f" #[← rndTerm vs (d + 1)]
  let r ← rnd 0 999
  if nb > 0 && r < 250 then return .const (Term.bvarSym (← rnd 0 (nb - 1)))
  if !vs.isEmpty && r < 600 then return .var (← choice (vs.qsort (· < ·)))
  if r < 750 || d ≥ 2 then return .const (← choice #["k1", "k1", "k2"])
  if r < 850 then return .app "f" #[← rndTerm vs (d + 1) true nb]
  return .app "lam" #[.const "T", ← rndTerm vs (d + 1) true (nb + 1)]

def rndAtom (vs : Array String) (binders : Bool := false) : RM Term := do
  let p ← choice #["P", "P", "Q"]
  if p == "Q" then return .app p #[← rndTerm vs 0 binders, ← rndTerm vs 0 binders]
  else return .app p #[← rndTerm vs 0 binders]

/- Port of `rnd_problem` in reference/diff.py, with the same shape probabilities. `k` is
the name counter. -/
mutual
partial def rndClause (env : Array String) (depth : Nat) (k : Nat) (binders : Bool) : RM (ClauseT × Nat) := do
  let mut k := k
  let mut vs := #[]
  for _ in [0:← choice #[0, 1, 1, 2]] do
    k := k + 1; vs := vs.push s!"v{k}"
  let scope := env ++ vs
  let mut prems := #[]
  let np ← if depth < 2 then choice #[0, 1, 1, 2] else pure 0
  for _ in [0:np] do
    let (g, k') ← rndGoal scope (depth + 1) k binders
    k := k'; prems := prems.push g
  k := k + 1
  return (.mk s!"c{k}" (← rndAtom scope binders) vs.toList prems.toList, k)

partial def rndGoal (env : Array String) (depth : Nat) (k : Nat) (binders : Bool) : RM (GoalT × Nat) := do
  let mut k := k
  let mut eig := #[]
  if ← chance 350 then
    k := k + 1; eig := eig.push s!"e{k}"
  let scope := env ++ eig
  let mut hyps := #[]
  if (← chance 350) && depth < 2 then
    let (h, k') ← rndClause scope (depth + 1) k binders
    k := k'; hyps := hyps.push h
  return (.mk (← rndAtom scope binders) eig.toList hyps.toList, k)
end

def rndProblem (binders : Bool) : RM Forest := do
  let (g, k) ← rndGoal #[] 0 0 binders
  let mut k := k
  let mut cs := #[]
  for _ in [0:← rnd 3 5] do
    let (cl, k') ← rndClause #[] 0 k binders
    k := k'; cs := cs.push cl
  return forest g cs.toList

def problemOf (seed : Nat) (binders : Bool := false) : Forest :=
  ((rndProblem binders).run ⟨seed.toUInt64 * 1000003 + 17 + (if binders then 7919 else 0)⟩).1

structure DiffStats where
  total : Nat := 0
  provable : Nat := 0
  mismatches : Array (Nat × Nat × Bool × Bool) := #[]
  minSizes : Array (Nat × Nat) := #[]

def diffChunk (seeds : List Nat) (maxN : Nat) (opts : EncodeOptions) (stopAtFirst : Bool)
    (binders : Bool) : IO DiffStats := do
  let mut st : DiffStats := {}
  for seed in seeds do
    let P := problemOf seed binders
    let mut minN : Option Nat := none
    for N in [1:maxN+1] do
      let r := Reference.provable P N
      let (s, _) ← solveForest P N opts
      st := { st with total := st.total + 1, provable := st.provable + (if r then 1 else 0) }
      if r && minN.isNone then minN := some N
      if s.isSome != r then
        st := { st with mismatches := st.mismatches.push (seed, N, r, s.isSome) }
        if stopAtFirst then return st
    if let some n := minN then st := { st with minSizes := st.minSizes.push (seed, n) }
  return st

/-- Run seeds `0 … seeds-1` in parallel chunks. -/
def diffRun (seeds maxN : Nat) (opts : EncodeOptions) (stopAtFirst := false) (workers := 8)
    (binders := false) : IO DiffStats := do
  let chunks := (List.range workers).map fun w => (List.range seeds).filter (· % workers == w)
  let tasks ← chunks.mapM fun ch => IO.asTask (diffChunk ch maxN opts stopAtFirst binders) .dedicated
  let mut out : DiffStats := {}
  for tk in tasks do
    match ← IO.wait tk with
    | .error e => throw e
    | .ok s => out := { total := out.total + s.total, provable := out.provable + s.provable,
                        mismatches := out.mismatches ++ s.mismatches, minSizes := out.minSizes ++ s.minSizes }
  return out

def histogram (xs : Array (Nat × Nat)) : List (Nat × Nat) :=
  (List.range 7).filterMap fun n =>
    let k := (xs.filter (·.2 == n)).size
    if k == 0 then none else some (n, k)

/-- Milestone 8 (M8_PLAN 3.4.5, 3.5): the mutation checks of R1 and R2 on one differential.
`minSizes` are the forests with a proof and their minimal N, from the reference (independent of
the encoder). -/
def m8Mutations (base : EncodeOptions) (seeds workers : Nat) (binders : Bool) (minSizes : Array (Nat × Nat))
    (t : Tally) : IO Tally := do
  let mut t := t
  let tag := if binders then " (forests with binders)" else ""
  let r1 : EncodeOptions := { base with groundness := false, nodeBounds := true }
  -- R1's size bound tightened by one: every forest with a proof fails at its minimal N
  let m ← diffRun seeds 5 { r1 with boundsTight := true } (workers := workers) (binders := binders)
  let failing := minSizes.filter fun (s, n) => m.mismatches.any fun (s', n', r, x) => s' == s && n' == n && r && !x
  let ok := failing.size == minSizes.size && !minSizes.isEmpty
  IO.println s!"{if ok then "PASS" else "FAIL"} mutation 'R1 size bound tightened by one'{tag}: {failing.size} of {minSizes.size} forests with a proof have none at their minimal N ({m.mismatches.size} mismatches in all)"
  t := t.check ok
  -- e(c) dropped: no answer changes, and no CNF is smaller than with e(c)
  let m ← diffRun seeds 5 { r1 with boundsScope := false } (workers := workers) (binders := binders)
  let mut smaller := 0
  let mut larger := 0
  for s in [0:seeds] do
    let P := problemOf s binders
    for N in [1:6] do
      let a := (encode P N { r1 with countOnly := true }).cnf.numClauses
      let b := (encode P N { r1 with countOnly := true, boundsScope := false }).cnf.numClauses
      if b < a then smaller := smaller + 1
      if b > a then larger := larger + 1
  let ok := m.mismatches.isEmpty && smaller == 0
  IO.println s!"{if ok then "PASS" else "FAIL"} mutation 'R1 without e(c)'{tag}: {m.mismatches.size} mismatches in {m.total} comparisons; CNFs smaller than with e(c): {smaller}, larger: {larger}"
  t := t.check ok
  -- R2 applied to a goal object and a head object at the same node: mismatches
  let m ← diffRun seeds 5 { base with groundness := false, exclusivePairs := true, exclusiveMutant := true }
    (stopAtFirst := true) (workers := workers) (binders := binders)
  let ok := !m.mismatches.isEmpty
  let first := m.mismatches.toList.take 3 |>.map fun (s, N, r, x) => s!"seed {s} N {N} (ref {r}, sat {x})"
  IO.println s!"{if ok then "PASS" else "FAIL"} mutation 'R2 on a goal object and a head object at one node'{tag}: mismatches found, e.g. {first}"
  return t.check ok

def main (args : List String) : IO UInt32 := do
  let seeds := (args[0]? >>= String.toNat?).getD 1500
  let workers := (args[1]? >>= String.toNat?).getD 4
  let cfg := args[2]?.getD "all"
  let some base := EncodeOptions.config cfg | IO.println s!"unknown configuration {cfg}"; return 2
  IO.println s!"solver: {← findSolver}; refinements: {cfg}"
  let mut t : Tally := {}
  t ← runForestTests base t
  -- milestone 8: R1's size bound tightened by one loses every forest test at its minimal N
  let mut lost := 0
  let mut withProof := 0
  for (_, P, expect) in forestTests do
    if let some n := expect then
      withProof := withProof + 1
      let (r, _) ← solveForest P n { base with nodeBounds := true, boundsTight := true }
      if r.isNone then lost := lost + 1
  IO.println s!"{if lost == withProof then "PASS" else "FAIL"} mutation 'R1 size bound tightened by one' (forest tests): {lost} of {withProof} have no proof at their minimal N"
  t := t.check (lost == withProof)
  t ← runSizeTests t
  -- differential test
  let t0 ← IO.monoMsNow
  let d ← diffRun seeds 5 { base with groundness := false } (workers := workers)
  let deep := (d.minSizes.filter (·.2 ≥ 2)).size
  for (s, N, r, x) in d.mismatches do IO.println s!"MISMATCH seed {s} N {N} ref {r} sat {x}"
  IO.println s!"differential: {d.total} comparisons, {d.provable} provable instances, {d.mismatches.size} mismatches, min-size histogram {histogram d.minSizes}, {deep} forests with min size ≥ 2 [{((← IO.monoMsNow) - t0) / 1000}s]"
  let ok := d.total ≥ 5000 && deep ≥ 100 && d.mismatches.isEmpty
  IO.println s!"{if ok then "PASS" else "FAIL"} differential (need ≥ 5000 comparisons, ≥ 100 forests of min size ≥ 2, 0 mismatches)"
  t := t.check ok
  let minPlain := d.minSizes
  -- mutation checks
  for (name, opts) in [("scope clauses of 6.7 off", { base with groundness := false, scope := false }),
                       ("occurs check off", { base with groundness := false, occurs := false })] do
    let m ← diffRun seeds 5 opts (stopAtFirst := true) (workers := workers)
    let ok := !m.mismatches.isEmpty
    let first := m.mismatches.toList.take 3 |>.map fun (s, N, r, x) => s!"seed {s} N {N} (ref {r}, sat {x})"
    IO.println s!"{if ok then "PASS" else "FAIL"} mutation '{name}': mismatches found, e.g. {first}"
    t := t.check ok
  -- milestone 4: the differential test and its mutation check on forests with binders
  let t0 ← IO.monoMsNow
  let open_ := ((List.range seeds).filter fun sd =>
    let P := problemOf sd true
    (P.goals.map (·.tgt) ++ P.clauses.map (·.head)).any (·.hasBVar)).length
  let d ← diffRun seeds 5 { base with groundness := false } (workers := workers) (binders := true)
  let deep := (d.minSizes.filter (·.2 ≥ 2)).size
  for (s, N, r, x) in d.mismatches do IO.println s!"MISMATCH (binders) seed {s} N {N} ref {r} sat {x}"
  IO.println s!"differential with binders: {d.total} comparisons, {d.provable} provable instances, {d.mismatches.size} mismatches, min-size histogram {histogram d.minSizes}, {deep} forests with min size ≥ 2, {open_} of {seeds} forests contain a bound variable [{((← IO.monoMsNow) - t0) / 1000}s]"
  let ok := d.total ≥ 5000 && deep ≥ 100 && d.mismatches.isEmpty
  IO.println s!"{if ok then "PASS" else "FAIL"} differential with binders (need ≥ 5000 comparisons, ≥ 100 forests of min size ≥ 2, 0 mismatches)"
  t := t.check ok
  let minBinders := d.minSizes
  let m ← diffRun seeds 5 { base with groundness := false, openBit := false } (stopAtFirst := true) (workers := workers) (binders := true)
  let ok := !m.mismatches.isEmpty
  let first := m.mismatches.toList.take 3 |>.map fun (s, N, r, x) => s!"seed {s} N {N} (ref {r}, sat {x})"
  IO.println s!"{if ok then "PASS" else "FAIL"} mutation 'open bit off' (forests with binders): mismatches found, e.g. {first}"
  t := t.check ok
  -- milestone 8 (M8_PLAN 3.4.5, 3.5), in the default configuration only (the other settings of
  -- Test/run_all.sh repeat the differentials, not these)
  if cfg == "all" then
    t ← m8Mutations base seeds workers false minPlain t
    t ← m8Mutations base seeds workers true minBinders t
  IO.println s!"M1: {t.pass} passed, {t.fail} failed"
  return if t.fail == 0 then 0 else 1
