/-
Milestone 8b (M8_PLAN §4.3, "Rules"): the DIMACS of every SPEC 7.3 instance (the `bench` forests
with 1, 5 and 9 lemmas at N = 5, 8, 12), with all refinements on and with all off, written with
the 8b analysis run on the encoding first (`on`) or not (`off`).

  m8b_dimacs73 OUTDIR on|off
-/
import SolveBySat
import Test.BenchForests
import Test.M8Diag

open SolveBySat

def main (args : List String) : IO UInt32 := do
  let [outdir, mode] := args | IO.eprintln "usage: m8b_dimacs73 OUTDIR on|off"; return 2
  IO.FS.createDirAll outdir
  for l in [1, 5, 9] do
    for n in [5, 8, 12] do
      for (cfg, o) in [("on", ({} : EncodeOptions)), ("off", EncodeOptions.allOff)] do
        let P := table73 l
        let E := encode P n o
        if mode == "on" then M8Diag.analyze P n o E (fun _ _ => pure ())
        let h ← IO.FS.Handle.mk (System.FilePath.mk outdir / s!"t73_{l}_{n}_{cfg}.cnf") .write
        h.putStr s!"p cnf {E.cnf.nVars} {E.cnf.clauses.size}\n"
        for c in E.cnf.clauses do
          h.putStr (" ".intercalate (c.toList.map toString) ++ " 0\n")
  return 0
