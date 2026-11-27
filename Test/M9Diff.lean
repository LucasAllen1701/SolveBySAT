/-
Milestone 9a-2 (M9_PLAN 3.2): differential tests on forests with equality rules.

Random forests with equation sources (global clauses and local hypotheses whose head is an `Eq`
atom) get the rules that the tactic's own generation code makes: `Rules.select` (strict, or liberal
for the selection-mutation run), `Rules.mkRule` with a fixed typing oracle, and the equality core
(`Rules.selectCore`, `Rules.mkCore`), appended with `Forest.extend`. Rules are ordinary clauses, so
the encoder is compared with `Reference` unchanged, at every N from 1 to 5.

The symbols: `f(t)`, `g(κ, t)` (κ a context argument: `T`, `U`, a root eigenvariable `rT`, or a
clause variable `tv…` of an H clause, so that every row occurs), predicates `P(t)` and `Q(κ, t)`,
`Eq(L, τ, s, t)`, constants `k1`, `k2`, and the `app` atom `rP(t)` with the root eigenvariable `rP`.
The typing oracle: `f`, `P`, `rP` at type `T`; `g(κ, ·)` and `Q(κ, ·)` at type κ; `Eq(L, τ, ·, ·)`
at τ; every level `L`.

Usage: `test_m9diff [seeds] [workers]`. Prints the comparisons, mismatches, and how many
comparisons with a proof use a generated rule; exit 0 iff there are 0 mismatches and enough
comparisons use rules.
-/
import SolveBySat
import Test.Util

open SolveBySat SolveBySat.Rules

namespace M9Diff

def L : Term := .const "lvl:L"
def T : Term := .const "c:T"

def sigs : Sigs := Std.HashMap.ofList [
  ("c:f/1", { mask := #[true], offset := 0 }),
  ("c:g/2", { mask := #[false, true], offset := 0 }),
  ("c:P/1", { mask := #[true], offset := 0 }),
  ("c:Q/2", { mask := #[false, true], offset := 0 }),
  ("c:Eq/4", { mask := #[false, false, true, true], offset := 1 }),
  ("app:rP/2", { mask := #[false, true], offset := 1 })]

/-- The typing oracle (the module doc). -/
def typesOf (node : Term) (pos : Nat) : RuleTypes :=
  match node with
  | .app "c:g" as => { posLvl := L, posTy := as[0]!, resLvl := L, resTy := as[0]! }
  | .app "c:Q" as => { posLvl := L, posTy := as[0]! }
  | .app "c:Eq" as => { posLvl := as[0]!, posTy := as[1]! }
  | .app "c:f" _ => { posLvl := L, posTy := T, resLvl := L, resTy := T }
  | _ => let _ := pos; { posLvl := L, posTy := T }

/-- A random argument term over the variables `vs` and the context arguments `ks`. -/
partial def rndTerm (vs ks : Array Term) (d : Nat) : RM Term := do
  let r ← rnd 0 999
  if !vs.isEmpty && r < 450 then return ← choice vs
  if r < 700 || d ≥ 2 then return .const (← choice #["c:k1", "c:k1", "c:k2"])
  if r < 870 then return .app "c:f" #[← rndTerm vs ks (d + 1)]
  return .app "c:g" #[← choice ks, ← rndTerm vs ks (d + 1)]

def eqAtomR (vs ks : Array Term) : RM Term := do
  let τ ← if (← chance 800) then pure T else choice ks
  return eqAtom L τ (← rndTerm vs ks 0) (← rndTerm vs ks 0)

def rndAtom (vs ks : Array Term) (app : Bool) (eqP : Nat) : RM Term := do
  if ← chance eqP then return ← eqAtomR vs ks
  let r ← rnd 0 999
  if app && r < 250 then return .app "app" #[.var "rP", ← rndTerm vs ks 0]
  if r < 650 then return .app "c:P" #[← rndTerm vs ks 0]
  return .app "c:Q" #[← choice ks, ← rndTerm vs ks 0]

structure G where
  k : Nat := 0

abbrev GM := StateT G RM

def fresh (p : String) : GM String := modifyGet fun s => (s!"{p}{s.k + 1}", { s with k := s.k + 1 })

mutual
partial def rndClause (env : Array Term) (ks : Array Term) (app : Bool) (depth : Nat) (isH : Bool) : GM ClauseT := do
  let mut vs : Array String := #[]
  for _ in [0:← (choice #[0, 1, 1, 2] : RM Nat)] do vs := vs.push (← fresh "v")
  let mut ks := ks
  -- an H clause may be polymorphic in a context variable (the `hvars` row)
  if isH && (← (chance 350 : RM Bool)) then
    let tv ← fresh "tv"
    vs := vs.push tv
    ks := ks.push (.var tv)
  let scope := env ++ (vs.filter (·.startsWith "v")).map Term.var
  let mut prems := #[]
  let np ← if depth < 1 then (choice #[0, 0, 1, 1, 2] : RM Nat) else pure 0
  for _ in [0:np] do prems := prems.push (← rndGoal scope ks app (depth + 1))
  let head ← (rndAtom scope ks app (if isH then 550 else 600) : RM Term)
  return .mk s!"c{← fresh ""}" head vs.toList prems.toList

partial def rndGoal (env : Array Term) (ks : Array Term) (app : Bool) (depth : Nat) : GM GoalT := do
  let mut eig := #[]
  if (← (chance 250 : RM Bool)) then eig := eig.push (← fresh "e")
  let scope := env ++ eig.map Term.var
  let mut hyps := #[]
  if (← (chance 300 : RM Bool)) && depth < 1 then hyps := hyps.push (← rndClause scope ks app (depth + 1) false)
  return .mk (← (rndAtom scope ks app 300 : RM Term)) eig.toList hyps.toList
end

/-- A random forest: a root goal with eigenvariables `r1` (a term), `rP` (an `app` head) and `rT`
(a context argument), 0 to 2 local hypotheses, and 3 to 5 clauses of H. -/
def rndProblem : RM Forest := do
  let go : GM Forest := do
    let ks : Array Term := #[T, .const "c:U", .var "rT"]
    let rootVs : Array Term := #[.var "r1"]
    let mut hyps := #[]
    for _ in [0:← (rnd 0 2 : RM Nat)] do hyps := hyps.push (← rndClause rootVs ks true 1 false)
    let tgt ← (rndAtom rootVs ks true 450 : RM Term)
    let root : GoalT := .mk tgt ["r1", "rP", "rT"] hyps.toList
    let mut cs := #[]
    for _ in [0:← (rnd 3 5 : RM Nat)] do cs := cs.push (← rndClause #[] #[T, .const "c:U"] false 0 true)
    match Forest.build root cs.toList with
    | .ok F => pure F
    | .error e => panic! s!"generator: {e}"
  return (← go.run {}).1

/-- The forest with its rules: (forest, number of clauses before the rules). -/
def withRules (F : Forest) (liberal eqTrans : Bool) : Except String (Forest × Nat × Nat) := do
  let sel := select F sigs (liberal := liberal)
  let base := F.clauses.size
  let mut cs := #[]
  let mut congrIds := #[]
  for (key, occ) in sel.rules do
    let node := (subtermAt (atomAt F occ.loc) occ.path).get!
    let name := ruleName sigs key cs.size
    if key.kind == .congr then congrIds := congrIds.push (base + cs.size)
    cs := cs.push (mkRule F sigs key occ (typesOf node key.pos) name s!"{name}.")
  let F1 ← F.extend cs
  let core := selectCore F1 sel.sources congrIds #[] eqTrans
  let mut cc := #[]
  for (key, _) in core do
    let name := ruleName sigs key (cs.size + cc.size)
    cc := cc.push (mkCore key name s!"{name}.")
  let F2 ← F1.extend cc
  return (F2, base, cs.size + cc.size)

def problemOf (seed : Nat) : Forest := (rndProblem.run ⟨seed.toUInt64 * 2654435761 + 9091⟩).1

structure Stats where
  forests : Nat := 0
  withRules : Nat := 0
  rules : Nat := 0
  total : Nat := 0
  provable : Nat := 0
  usesRule : Nat := 0
  mismatches : Array (Nat × Nat × Bool × Bool) := #[]
  /-- (seed, N, liberal) where the strict forest has a proof at N and the liberal one does not. -/
  lost : Array (Nat × Nat) := #[]
  /-- (seed, N) where the liberal forest has a proof and the strict one does not. -/
  gained : Array (Nat × Nat) := #[]
  errors : Array String := #[]

def Stats.add (a b : Stats) : Stats :=
  { forests := a.forests + b.forests, withRules := a.withRules + b.withRules, rules := a.rules + b.rules,
    total := a.total + b.total, provable := a.provable + b.provable, usesRule := a.usesRule + b.usesRule,
    mismatches := a.mismatches ++ b.mismatches, lost := a.lost ++ b.lost, gained := a.gained ++ b.gained,
    errors := a.errors ++ b.errors }

def solve (P : Forest) (N : Nat) : IO (Option (Array SkelNode)) := do
  let E := encode P N { groundness := false }
  match ← runSolver E.cnf with
  | .unsat => return none
  | .sat m =>
    match readSkeleton P E.vars m with
    | .ok sk => return some sk
    | .error e => throw <| IO.userError s!"bad skeleton: {e}"

def chunk (seeds : List Nat) (maxN : Nat) (liberalToo : Bool) : IO Stats := do
  let mut st : Stats := {}
  for seed in seeds do
    let F := problemOf seed
    let eqTrans := seed % 3 != 0
    match withRules F false eqTrans with
    | .error e => st := { st with errors := st.errors.push s!"seed {seed}: {e}" }
    | .ok (P, base, n) =>
      st := { st with forests := st.forests + 1, rules := st.rules + n,
                      withRules := st.withRules + (if n > 0 then 1 else 0) }
      let lib? := if liberalToo then (withRules F true eqTrans).toOption else none
      for N in [1:maxN+1] do
        let r := Reference.provable P N
        let s ← solve P N
        st := { st with total := st.total + 1, provable := st.provable + (if r then 1 else 0) }
        if s.isSome != r then st := { st with mismatches := st.mismatches.push (seed, N, r, s.isSome) }
        if let some sk := s then
          if sk.any (·.clause ≥ base) then st := { st with usesRule := st.usesRule + 1 }
        -- the selection mutation: the liberal forest (more clauses) loses no proof
        if let some (PL, _, _) := lib? then
          let rl := Reference.provable PL N
          let sl ← solve PL N
          if sl.isSome != rl then st := { st with mismatches := st.mismatches.push (seed + 1000000, N, rl, sl.isSome) }
          if s.isSome && !sl.isSome then st := { st with lost := st.lost.push (seed, N) }
          if !s.isSome && sl.isSome then st := { st with gained := st.gained.push (seed, N) }
  return st

def run (seeds maxN workers : Nat) (liberalToo : Bool) : IO Stats := do
  let chunks := (List.range workers).map fun w => (List.range seeds).filter (· % workers == w)
  let tasks ← chunks.mapM fun ch => IO.asTask (chunk ch maxN liberalToo) .dedicated
  let mut out : Stats := {}
  for tk in tasks do
    match ← IO.wait tk with
    | .error e => throw e
    | .ok s => out := out.add s
  return out

end M9Diff

open M9Diff in
def main (args : List String) : IO UInt32 := do
  let seeds := (args[0]? >>= String.toNat?).getD 600
  let workers := (args[1]? >>= String.toNat?).getD 4
  IO.println s!"solver: {← findSolver}"
  let t0 ← IO.monoMsNow
  let d ← run seeds 5 workers false
  for e in d.errors do IO.println s!"ERROR {e}"
  for (s, N, r, x) in d.mismatches do IO.println s!"MISMATCH seed {s} N {N} ref {r} sat {x}"
  IO.println s!"differential with rules: {d.forests} forests ({d.withRules} with rules, {d.rules} rules), \
    {d.total} comparisons, {d.provable} provable, {d.usesRule} proofs use a generated rule, \
    {d.mismatches.size} mismatches [{((← IO.monoMsNow) - t0) / 1000}s]"
  let ok := d.errors.isEmpty && d.mismatches.isEmpty && d.total ≥ 2500 && d.usesRule ≥ 100
  IO.println s!"{if ok then "PASS" else "FAIL"} differential with rules (need ≥ 2500 comparisons, ≥ 100 proofs using a rule, 0 mismatches)"
  -- the selection mutation (M9_PLAN 3.2, 6.1 clarification 4): liberal rules lose no proof
  let t0 ← IO.monoMsNow
  let m ← run (seeds / 3) 5 workers true
  for (s, N, r, x) in m.mismatches do IO.println s!"MISMATCH (liberal) seed {s} N {N} ref {r} sat {x}"
  IO.println s!"selection dropped (liberal rules): {m.total} comparisons, {m.lost.size} proofs lost, \
    {m.gained.size} proofs gained, {m.mismatches.size} mismatches [{((← IO.monoMsNow) - t0) / 1000}s]"
  let ok2 := m.errors.isEmpty && m.mismatches.isEmpty && m.lost.isEmpty
  IO.println s!"{if ok2 then "PASS" else "FAIL"} selection dropped: no proof lost, 0 mismatches"
  return if ok && ok2 then 0 else 1
