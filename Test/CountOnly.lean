/-
Milestone 7c (EVAL_PLAN §4.1, §10.9 4.1 decision 1): `countOnly` must count exactly what a full
encode produces. On every instance of the SPEC 7.3 table (the `bench` forests with 1, 5 and 9
lemmas at N = 5, 8, 12; L1 at N = 5; D3 at N = 3), with all refinements on and with all off, a
`countOnly` encode must equal a full encode in variables, in total clauses and in every
family's clause count (same families, same order), and must store no clause.
-/
import SolveBySat
import Lean
import Test.BenchForests

open Lean Meta SolveBySat

def fmtFams (fs : Array (String × Nat)) : String :=
  ", ".intercalate (fs.toList.map fun (f, k) => s!"{f} {k}")

def main : IO UInt32 := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Init }] {}
  let compileLean (name : String) : IO Forest := do
    let ((goal, H), _, _) ← (leanGoal name).toIO { fileName := "<countonly>", fileMap := default } { env }
    let (C, _, _) ← (compile goal H).toIO { fileName := "<countonly>", fileMap := default } { env }
    pure C.forest
  let mut cases : Array (String × Forest × Nat) := #[]
  for l in [1, 5, 9] do
    for n in [5, 8, 12] do
      cases := cases.push (s!"§7.3, {l} lemma{if l > 1 then "s" else ""}", table73 l, n)
  cases := cases.push ("L1", ← compileLean "L1", 5)
  cases := cases.push ("D3", ← compileLean "D3", 3)
  let mut fails := 0
  IO.println "| instance | N | config | vars (full = count) | clauses (full = count) | families equal | stored (count) |"
  IO.println "| --- | --- | --- | --- | --- | --- | --- |"
  for (label, P, N) in cases do
    for (cfg, o) in [("all on", ({} : EncodeOptions)), ("all off", EncodeOptions.allOff)] do
      let full := encode P N o
      let cnt := encode P N { o with countOnly := true }
      let okV := full.cnf.nVars == cnt.cnf.nVars
      let okC := full.cnf.clauses.size == cnt.cnf.numClauses && full.cnf.numClauses == full.cnf.clauses.size
      let okF := full.cnf.familyCounts == cnt.cnf.familyCounts
      let okS := cnt.cnf.clauses.size == 0
      let ok := okV && okC && okF && okS
      unless ok do
        fails := fails + 1
        IO.println s!"FAIL {label} N = {N} {cfg}: full {full.cnf.nVars} vars [{fmtFams full.cnf.familyCounts}], count {cnt.cnf.nVars} vars [{fmtFams cnt.cnf.familyCounts}]"
      IO.println s!"| {label} | {N} | {cfg} | {full.cnf.nVars} = {cnt.cnf.nVars} | {full.cnf.clauses.size} = {cnt.cnf.numClauses} | {if okF then s!"yes ({full.cnf.familyCounts.size})" else "NO"} | {cnt.cnf.clauses.size} |"
  IO.println s!"countOnly: {cases.size * 2 - fails} passed, {fails} failed"
  return if fails == 0 then 0 else 1
