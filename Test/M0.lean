/-
Milestone 0 acceptance: SAT plumbing.
- pigeonhole 7 into 6 is unsatisfiable;
- 300 random small CNFs (with constant literals, to exercise folding) agree with brute force;
- additionally: the eq / lt / amo gadgets are checked exhaustively against their meaning,
  since every later family is built from them.
-/
import SolveBySat
import Test.Util

open SolveBySat CNF

/-- Assignment of variables `1..n` from the bits of `mask`. -/
def modelOf (n mask : Nat) : Array Bool :=
  (Array.range (n + 1)).map fun v => v > 0 && (mask >>> (v - 1)) &&& 1 == 1

def evalBClauses (cs : Array (Array BLit)) (m : Array Bool) : Bool :=
  cs.all fun c => c.any (BLit.eval m)

/-- Is there an assignment of the variables above `nOrig` that, together with the
original assignment `m`, satisfies `F`? -/
def existsAux (F : CNF) (nOrig : Nat) (m : Array Bool) : Bool := Id.run do
  let nAux := F.nVars - nOrig
  for a in [0:2 ^ nAux] do
    let full := (Array.range (F.nVars + 1)).map fun v =>
      if v ≤ nOrig then m[v]! else (a >>> (v - nOrig - 1)) &&& 1 == 1
    if F.satisfiedBy full then return true
  return false

def bvNat (m : Array Bool) (X : Array BLit) : Nat :=
  X.foldl (fun acc b => 2 * acc + (if BLit.eval m b then 1 else 0)) 0

structure Tally where
  pass : Nat := 0
  fail : Nat := 0
  msgs : Array String := #[]

def Tally.check (t : Tally) (ok : Bool) (msg : String) : Tally :=
  if ok then { t with pass := t.pass + 1 } else { t with fail := t.fail + 1, msgs := t.msgs.push msg }

/-- Pigeonhole: `p` pigeons into `h` holes. -/
def pigeonhole (p h : Nat) : CNF := (buildCNF (do
  let x ← (List.range p).mapM fun _ => newLits h
  for i in [0:p] do addClause x[i]!
  for j in [0:h] do amo ((List.range p).toArray.map fun i => x[i]![j]!)) ).2

/-- A random clause over `n` variables with occasional constants. -/
def rndClause (n : Nat) : RM (Array BLit) := do
  let len ← rnd 1 4
  let mut c := #[]
  for _ in [0:len] do
    let k ← rnd 0 19
    if k == 0 then c := c.push BLit.tt
    else if k ≤ 2 then c := c.push BLit.ff
    else
      let v ← rnd 1 n
      let s ← rnd 0 1
      c := c.push (.lit (if s == 0 then (v : Int) else -(v : Int)))
  return c

def randomCnfTests (t : Tally) : IO Tally := do
  let mut t := t
  let mut rng : Rng := ⟨2026⟩
  let mut nSat := 0
  let mut nUnsat := 0
  for i in [0:300] do
    let ((n, cs), r) := (do
      let n ← rnd 1 10
      let m ← rnd 1 (5 * n)
      let cs ← (List.range m).toArray.mapM fun _ => rndClause n
      return (n, cs) : RM _).run rng
    rng := r
    let F := (buildCNF (do
      for _ in [0:n] do discard newVar
      for c in cs do addClause c)).2
    -- brute force on the unfolded clauses
    let mut brute := false
    let mut foldOk := true
    for mask in [0:2 ^ n] do
      let m := modelOf n mask
      let a := evalBClauses cs m
      if a then brute := true
      if a != F.satisfiedBy m then foldOk := false
    t := t.check foldOk s!"random CNF {i}: folding changed the meaning"
    let r ← runSolver F
    if r.isSat then nSat := nSat + 1 else nUnsat := nUnsat + 1
    t := t.check (r.isSat == brute) s!"random CNF {i}: solver {r.isSat}, brute force {brute}"
  IO.println s!"  random CNFs: 300 instances, {nSat} SAT / {nUnsat} UNSAT"
  return t

/-- Random bit vector: each bit a constant or a fresh variable among `vars`. -/
def rndVec (w : Nat) (vars : Array BLit) : RM (Array BLit) := do
  let mut X := #[]
  for _ in [0:w] do
    let k ← rnd 0 3
    if k == 0 then X := X.push (.const ((← rnd 0 1) == 1))
    else X := X.push vars[(← rnd 0 (vars.size - 1))]!
  return X

def gadgetTests (t : Tally) : Tally := Id.run do
  let mut t := t
  let mut rng : Rng := ⟨7⟩
  for i in [0:300] do
    -- shape of this instance
    let ((kind, w, nv, condConst), r) := (do
      return (← rnd 0 3, ← rnd 1 3, ← rnd 1 5, ← rnd 0 4) : RM _).run rng
    rng := r
    -- variables 1..nv are the "original" ones; variable 1 doubles as the condition
    let ((X, Y, ls), r) := (do
      let vars := (Array.range nv).map fun v => BLit.lit ((v + 1 : Nat) : Int)
      return (← rndVec w vars, ← rndVec w vars, ← rndVec (w + 5) vars) : RM _).run rng
    rng := r
    let cond : Array BLit := if condConst == 0 then #[] else #[.lit 1]
    let F := (buildCNF (do
      for _ in [0:nv] do discard newVar
      match kind with
      | 0 => eqUnder cond X Y
      | 1 => ltUnder cond X Y
      | 2 => amo ls
      | _ => amoLadder ls)).2
    let mut ok := true
    for mask in [0:2 ^ nv] do
      let m := modelOf nv mask
      let c := cond.all (BLit.eval m)
      let spec := match kind with
        | 0 => !c || bvNat m X == bvNat m Y
        | 1 => !c || bvNat m X < bvNat m Y
        -- entries counted with multiplicity: a repeated true entry violates at-most-one
        | _ => (ls.filter (BLit.eval m)).size ≤ 1
      if spec != existsAux F nv m then ok := false
    let name := match kind with | 0 => "eq" | 1 => "lt" | 2 => "amo" | _ => "amo-ladder"
    t := t.check ok s!"gadget {name} instance {i} (w={w}, nv={nv}) disagrees with its meaning"
  return t

def main : IO UInt32 := do
  IO.println s!"solver: {← findSolver}"
  let mut t : Tally := {}
  -- pigeonhole
  let php := pigeonhole 7 6
  let t0 ← IO.monoMsNow
  let r ← runSolver php
  IO.println s!"  pigeonhole 7→6: {php.nVars} vars, {php.clauses.size} clauses, {if r.isSat then "SAT" else "UNSAT"} [{(← IO.monoMsNow) - t0} ms]"
  t := t.check (!r.isSat) "pigeonhole 7→6 must be UNSAT"
  let r ← runSolver (pigeonhole 6 6)
  t := t.check r.isSat "pigeonhole 6→6 must be SAT"
  t ← randomCnfTests t
  t := gadgetTests t
  IO.println s!"  gadgets: 300 eq/lt/amo/ladder-amo instances checked exhaustively"
  for m in t.msgs do IO.println s!"FAIL {m}"
  IO.println s!"M0: {t.pass} passed, {t.fail} failed"
  return if t.fail == 0 then 0 else 1
