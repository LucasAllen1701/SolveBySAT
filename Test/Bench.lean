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
import Test.BenchForests

open Lean Meta SolveBySat

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
