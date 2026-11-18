/-
SolveBySat.Solver: locate a SAT solver, run it on a CNF, parse and verify the model.

Solver lookup order:
1. the environment variable `SOLVE_BY_SAT_SOLVER` (any DIMACS solver printing `s`/`v` lines);
2. `cadical` next to the running executable — this is how `bv_decide` finds the CaDiCaL
   bundled with the toolchain (`Lean/Meta/Tactic/BVDecide/TacticContext.lean`), and it
   applies when the tactic runs inside `lean`;
3. `<sysroot>/bin/cadical` via `Lean.findSysroot`, which covers compiled test executables;
4. `cadical` on `PATH`.
-/
import SolveBySat.CNF
import Lean.Util.Path

namespace SolveBySat

inductive SatResult where
  /-- `model[v]` is the value of variable `v` (index 0 unused). -/
  | sat (model : Array Bool)
  | unsat
  deriving Inhabited

def SatResult.isSat : SatResult → Bool
  | .sat _ => true
  | .unsat => false

def findSolver : IO String := do
  if let some s ← IO.getEnv "SOLVE_BY_SAT_SOLVER" then
    if !s.isEmpty then return s
  let exe := System.FilePath.exeExtension
  if let some dir := (← IO.appPath).parent then
    let p := (dir / "cadical").withExtension exe
    if ← p.pathExists then return p.toString
  try
    let p := (← Lean.findSysroot) / "bin" / ("cadical" : System.FilePath).withExtension exe
    if ← p.pathExists then return p.toString
  catch _ => pure ()
  return "cadical"

/-- Parse solver output in the SAT competition format. -/
def parseSolverOutput (nVars : Nat) (out : String) : Except String SatResult := do
  let mut status : Option Bool := none
  let mut model := Array.replicate (nVars + 1) false
  for line in out.splitOn "\n" do
    let line := line.trimAscii.toString
    if line.startsWith "s " then
      if line == "s SATISFIABLE" then status := some true
      else if line == "s UNSATISFIABLE" then status := some false
      else throw s!"unexpected solver status line: {line}"
    else if line.startsWith "v" then
      for tok in ((line.drop 1).toString.replace "\t" " ").splitOn " " do
        if tok.isEmpty then continue
        let some x := tok.toInt? | throw s!"bad model token: {tok}"
        if x == 0 then continue
        let v := x.natAbs
        if v > nVars then throw s!"model mentions variable {v} > {nVars}"
        model := model.set! v (x > 0)
  match status with
  | some true => return .sat model
  | some false => return .unsat
  | none => throw "solver printed no status line"

/-- Write `F` as DIMACS, run the solver, and parse the result. A returned model is
checked against every clause; a model that violates a clause is an error. -/
def runSolver (F : CNF) (solver? : Option String := none) : IO SatResult := do
  let solver ← match solver? with
    | some s => pure s
    | none => findSolver
  let (h, path) ← IO.FS.createTempFile
  try
    h.putStr F.toDimacs
    h.flush
    let quiet := if (System.FilePath.mk solver).fileStem == some "cadical" then #["-q"] else #[]
    let out ← IO.Process.output { cmd := solver, args := quiet.push path.toString }
    -- CaDiCaL exits with 10 (SAT) / 20 (UNSAT); anything else is a failure.
    unless out.exitCode == 10 || out.exitCode == 20 do
      throw <| IO.userError s!"SAT solver '{solver}' exited with code {out.exitCode}:\n{out.stderr}"
    match parseSolverOutput F.nVars out.stdout with
    | .error e => throw <| IO.userError s!"SAT solver '{solver}': {e}"
    | .ok r =>
      if let .sat m := r then
        unless F.satisfiedBy m do
          throw <| IO.userError s!"SAT solver '{solver}' returned a model that violates the CNF"
      return r
  finally
    IO.FS.removeFile path

end SolveBySat
