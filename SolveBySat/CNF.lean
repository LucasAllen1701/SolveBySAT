/-
SolveBySat.CNF: variable allocation, a clause builder with constant folding, and the
bit-vector gadgets (conditional equality, less-than, at-most-one) of SPEC §6.

Port of the `CNF`, `neg`, `bits`, `eq`, `lt` and `amo` helpers of `reference/enc.py`.
Pure: no `Lean.Meta`.
-/
import Std.Data.HashMap
import Std.Data.HashSet

namespace SolveBySat

/-- A literal that may be a known constant. `lit l` is a DIMACS literal (`l ≠ 0`). -/
inductive BLit where
  | const (b : Bool)
  | lit (l : Int)
  deriving BEq, Hashable, Repr, Inhabited

namespace BLit
def tt : BLit := .const true
def ff : BLit := .const false

def neg : BLit → BLit
  | .const b => .const (!b)
  | .lit l => .lit (-l)

def isConst : BLit → Bool
  | .const _ => true
  | .lit _ => false

/-- Value under a model indexed by variable (`model[v]` for `v ≥ 1`). -/
def eval (model : Array Bool) : BLit → Bool
  | .const b => b
  | .lit l => if l > 0 then model[l.toNat]! else !model[(-l).toNat]!
end BLit

/-- `bits x w`: the `w`-bit big-endian representation of `x` as constants. -/
def constBits (x w : Nat) : Array BLit :=
  (Array.range w).map fun i => .const (((x >>> (w - 1 - i)) &&& 1) == 1)

/-- A CNF under construction. Clauses are stored as DIMACS literals. -/
structure CNF where
  nVars : Nat := 0
  clauses : Array (Array Int) := #[]
  /-- The clause family currently being emitted, for size reports (SPEC §7). -/
  fam : String := "misc"
  counts : Std.HashMap String Nat := {}
  /-- Order in which families first received a clause, for stable reports. -/
  famOrder : Array String := #[]

instance : Inhabited CNF := ⟨{}⟩

abbrev CnfM := StateM CNF

namespace CNF

def newVar : CnfM Int := modifyGet fun s => ((s.nVars + 1 : Nat), { s with nVars := s.nVars + 1 })

def newLit : CnfM BLit := return .lit (← newVar)

def newLits (n : Nat) : CnfM (Array BLit) := do
  let mut out := Array.mkEmpty n
  for _ in [0:n] do out := out.push (← newLit)
  return out

def setFamily (f : String) : CnfM Unit := modify fun s => { s with fam := f }

/-- Add the disjunction of `ls`, folding constants: a `true` literal or a complementary
pair drops the clause, `false` literals and duplicates are removed. An all-false clause
is kept as the empty clause. -/
def addClause (ls : Array BLit) : CnfM Unit := do
  let mut out : Array Int := Array.mkEmpty ls.size
  let mut seen : Std.HashSet Int := {}
  for l in ls do
    match l with
    | .const true => return
    | .const false => pure ()
    | .lit x =>
      if seen.contains (-x) then return
      unless seen.contains x do
        seen := seen.insert x
        out := out.push x
  modify fun s =>
    let c := s.counts.getD s.fam 0
    { s with clauses := s.clauses.push out
             counts := s.counts.insert s.fam (c + 1)
             famOrder := if c == 0 && !s.famOrder.contains s.fam then s.famOrder.push s.fam else s.famOrder }

/-- `cond ⇒ X = Y` bitwise (enc.py `eq`). Two clauses per pair of free bits, one per free
bit against a constant; if two constant bits differ, the single clause `¬cond`. -/
def eqUnder (cond : Array BLit) (X Y : Array BLit) : CnfM Unit := do
  let nc := cond.map BLit.neg
  for i in [0:min X.size Y.size] do
    match X[i]!, Y[i]! with
    | .const a, .const b =>
      if a != b then addClause nc; return
    | .const a, b => addClause (nc.push (if a then b else b.neg))
    | a, .const b => addClause (nc.push (if b then a else a.neg))
    | a, b =>
      if a != b then
        addClause (nc ++ #[a.neg, b])
        addClause (nc ++ #[a, b.neg])

/-- `cond ⇒ X < Y` as unsigned big-endian bit vectors of equal width (enc.py `lt`).
Chain `t₀ … t_w` with `t_w = false`; assert `t₀` under `cond`; for each bit
`tᵢ ∧ xᵢ ⇒ yᵢ`, `tᵢ ∧ xᵢ ⇒ tᵢ₊₁`, `tᵢ ∧ ¬yᵢ ⇒ tᵢ₊₁`. -/
def ltUnder (cond : Array BLit) (X Y : Array BLit) : CnfM Unit := do
  let w := X.size
  let t := (← newLits w).push BLit.ff
  addClause ((cond.map BLit.neg).push t[0]!)
  for i in [0:w] do
    addClause #[t[i]!.neg, X[i]!.neg, Y[i]!]
    addClause #[t[i]!.neg, X[i]!.neg, t[i+1]!]
    addClause #[t[i]!.neg, Y[i]!, t[i+1]!]

/-- At most one of `ls`, pairwise encoding (enc.py `amo`). -/
def amoPairwise (ls : Array BLit) : CnfM Unit := do
  for i in [0:ls.size] do
    for j in [i+1:ls.size] do
      addClause #[ls[i]!.neg, ls[j]!.neg]

/-- At most one of `ls`, ladder (sequential counter) encoding (milestone 6): auxiliaries
`s₁ … s_{n-1}` with `sᵢ` meaning "one of x₁ … xᵢ is true": `xᵢ ⇒ sᵢ`, `sᵢ₋₁ ⇒ sᵢ`,
`xᵢ ⇒ ¬sᵢ₋₁`. 3n − 4 clauses and n − 1 variables instead of n(n − 1)/2 clauses. -/
def amoLadder (ls : Array BLit) : CnfM Unit := do
  let n := ls.size
  if n ≤ 1 then return
  let sv ← newLits (n - 1)
  for i in [0:n] do
    if i < n - 1 then addClause #[ls[i]!.neg, sv[i]!]
    if i > 0 then
      addClause #[ls[i]!.neg, sv[i-1]!.neg]
      if i < n - 1 then addClause #[sv[i-1]!.neg, sv[i]!]

/-- At most one of `ls`: pairwise, or with `ladder` the ladder encoding for 6 or more
literals (below that the pairwise encoding has no more clauses and no auxiliaries). -/
def amo (ls : Array BLit) (ladder : Bool := false) : CnfM Unit :=
  if ladder && ls.size ≥ 6 then amoLadder ls else amoPairwise ls

/-- Does `model` (indexed by variable, entry 0 unused) satisfy every clause? -/
def satisfiedBy (F : CNF) (model : Array Bool) : Bool :=
  F.clauses.all fun c => c.any fun l => BLit.eval model (.lit l)

/-- DIMACS text. -/
def toDimacs (F : CNF) : String := Id.run do
  let mut s := s!"p cnf {F.nVars} {F.clauses.size}\n"
  for c in F.clauses do
    for l in c do
      s := s ++ toString l ++ " "
    s := s ++ "0\n"
  return s

/-- Clause counts per family, in first-use order. -/
def familyCounts (F : CNF) : Array (String × Nat) :=
  F.famOrder.map fun f => (f, F.counts.getD f 0)

end CNF

/-- Run a builder from the empty CNF. -/
def buildCNF {α} (m : CnfM α) (init : CNF := {}) : α × CNF := (StateT.run m init).run

end SolveBySat
