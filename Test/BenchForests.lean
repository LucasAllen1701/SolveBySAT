/-
The instances of SPEC §7.3, shared by `Test/Bench.lean` (the benchmark) and
`Test/CountOnly.lean` (the `countOnly` check): the untyped chain forest with `lemmas` lemmas,
and the Lean goals L1 and D3. Moved here unchanged from `Test/Bench.lean`.
-/
import SolveBySat
import Lean

open Lean Meta SolveBySat

def V (n : String) : SolveBySat.Term := .var n
def le (a b : SolveBySat.Term) : SolveBySat.Term := .app "le" #[a, b]

/-- SPEC §7.3's forest with `lemmas` lemmas in `H`. -/
def table73 (lemmas : Nat) : Forest :=
  let (x, y, z, w) := (V "x", V "y", V "z", V "w")
  let g := GoalT.mk (le x w) ["x", "y", "z", "w"]
    [.mk "h1" (le x y) [] [], .mk "h2" (le y z) [] [], .mk "h3" (le z w) [] []]
  let tr := ClauseT.mk "le_trans" (le (V "a") (V "c")) ["a", "b", "c"]
    [.mk (le (V "a") (V "b")) [] [], .mk (le (V "b") (V "c")) [] []]
  let mono := (List.range (lemmas - 1)).map fun i =>
    -- all monotonicity lemmas share the symbol `s`: this reproduces SPEC §7.3 exactly
    let (m, n) := (V s!"m{i}", V s!"n{i}")
    ClauseT.mk s!"mono{i}" (le (.app "s" #[m]) (.app "s" #[n])) [s!"m{i}", s!"n{i}"] [.mk (le m n) [] []]
  match Forest.build g (tr :: mono) with
  | .ok F => F
  | .error e => panic! e

/-- The goal of L1 or D3 as a closed type, and its `H`. -/
def leanGoal (name : String) : MetaM (Expr × Array Name) := do
  let nat := mkConst ``Nat
  let leNat := fun (a b : Expr) => mkApp4 (mkConst ``LE.le [.zero]) nat (mkConst ``instLENat) a b
  match name with
  | "L1" =>
    withLocalDeclD `x nat fun x => withLocalDeclD `y nat fun y => withLocalDeclD `z nat fun z =>
    withLocalDeclD `w nat fun w => do
      let h1 := leNat x y
      let h2 := leNat y z
      let h3 := leNat z w
      let t := leNat x w
      let body ← mkArrow h1 (← mkArrow h2 (← mkArrow h3 t))
      return (← mkForallFVars #[x, y, z, w] body, #[``Nat.le_trans])
  | "D3" =>
    withLocalDeclD `Q (← mkArrow nat (mkSort .zero)) fun Q => do
      let q ← withLocalDeclD `m nat fun m => do
        mkForallFVars #[m] (mkApp Q (mkApp (mkConst ``Nat.succ) m))
      let ex ← withLocalDeclD `n nat fun n => do
        mkAppM ``Exists #[← mkLambdaFVars #[n] (mkApp Q n)]
      return (← mkForallFVars #[Q] (← mkArrow q ex), #[``Nat.zero])
  | _ => throwError "unknown goal {name}"

