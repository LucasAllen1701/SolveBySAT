/- Shared test utilities: a deterministic RNG. -/

/-- Deterministic splitmix64, so failures are reproducible. -/
structure Rng where
  s : UInt64

def Rng.next (r : Rng) : UInt64 × Rng :=
  let s := r.s + 0x9E3779B97F4A7C15
  let z := (s ^^^ (s >>> 30)) * 0xBF58476D1CE4E5B9
  let z := (z ^^^ (z >>> 27)) * 0x94D049BB133111EB
  (z ^^^ (z >>> 31), ⟨s⟩)

/-- Uniform in `[lo, hi]`. -/
def Rng.range (r : Rng) (lo hi : Nat) : Nat × Rng :=
  let (x, r) := r.next
  (lo + x.toNat % (hi - lo + 1), r)

abbrev RM := StateM Rng
def rnd (lo hi : Nat) : RM Nat := modifyGet fun r => r.range lo hi
/-- True with probability `p / 1000`. -/
def chance (p : Nat) : RM Bool := return (← rnd 0 999) < p
def choice {α} [Inhabited α] (xs : Array α) : RM α := return xs[← rnd 0 (xs.size - 1)]!
