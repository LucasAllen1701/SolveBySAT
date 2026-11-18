/-
Milestone 6 benchmark driver (requirement 6). Encodes one instance, prints one line

  vars clauses encode_ms

and writes the CNF as DIMACS to `out`. `Test/bench.sh` runs this under `/usr/bin/time`
(peak memory of the encoder) and then runs CaDiCaL on the file, also under
`/usr/bin/time` (solve time and peak memory of the solver).

Usage:
  bench forest <lemmas> <N> <config> <out>   SPEC §7.3: `x ≤ w` from `x ≤ y`, `y ≤ z`,
      `z ≤ w`, with transitivity and `lemmas - 1` monotonicity lemmas `m ≤ n → s m ≤ s n`
      (an untyped forest, as in the prototype)
  bench lean L1|D3 <N> <config> <out>          the Lean goals L1 and D3, compiled
`config` is an `EncodeOptions.config` name (`all`, `none`, …); `proto` is `none` with the
prototype's rank width.
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

@[noinline] def timedEncode (P : Forest) (N : Nat) (opts : EncodeOptions) : IO (Encoding × Nat) := do
  let t0 ← IO.monoNanosNow
  let E ← IO.lazyPure fun _ => encode P N opts
  -- force the whole CNF
  let n := E.cnf.clauses.foldl (fun n c => n + c.size) 0
  let t1 ← IO.monoNanosNow
  if n == 0 && E.cnf.clauses.size > 0 then IO.println "empty"
  return (E, (t1 - t0) / 1000000)

def main (args : List String) : IO UInt32 := do
  let [kind, what, nStr, cfg, out] := args
    | IO.println "usage: bench forest|lean <lemmas|L1|D3> <N> <config> <out>"; return 2
  let some N := nStr.toNat? | return 2
  let some opts := (if cfg == "proto" then EncodeOptions.config "none" { protoRank := true }
                    else EncodeOptions.config cfg) | IO.println s!"unknown config {cfg}"; return 2
  let P ← if kind == "forest" then
      pure (table73 what.toNat!)
    else do
      initSearchPath (← findSysroot)
      let env ← importModules #[{ module := `Init }] {}
      let ((goal, H), _, _) ← (leanGoal what).toIO { fileName := "<bench>", fileMap := default } { env }
      let (C, _, _) ← (compile goal H).toIO { fileName := "<bench>", fileMap := default } { env }
      pure C.forest
  let (E, ms) ← timedEncode P N opts
  IO.FS.writeFile out E.cnf.toDimacs
  IO.println s!"{E.cnf.nVars} {E.cnf.clauses.size} {ms}"
  return 0
