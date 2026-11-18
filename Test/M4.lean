/-
Milestone 4, pure tests (requirement 3 of the milestone): the label of every kind of
object is allocated once and reused.

The forest is an `Eq.refl`-like problem with typed variables and level variables, built
by hand so that the encoder creates every kind of object:
- slots of term variables and of level variables;
- a rigid term object (`f(z)`) and a rigid level object (`lvl:succ(u2)`);
- ground term objects (`Nat`) and ground level objects (`lvl:zero`, `lvl:succ(lvl:zero)`);
- a type-template object (`sort(u)`, the type of `α`), which the typing clause uses.
`Encode.lab` counts every fresh allocation per object; each count must be exactly 1, and
every allocated object must be in the label cache with the full width `W`.
-/
import SolveBySat

open SolveBySat

def c (s : String) : Term := .const s
def V (n : String) : Term := .var n
def ap (f : String) (as : List Term) : Term := .app f as.toArray
def lsucc (t : Term) : Term := ap "lvl:succ" [t]

def unitForest : Forest := Id.run do
  let nat := c "c:Nat"
  let goal := GoalT.mk (ap "c:Eq" [lsucc (c "lvl:zero"), nat, V "n", V "n"]) ["n"] []
  let refl := ClauseT.mk "refl" (ap "c:Eq" [V "u", V "α", V "a", V "a"]) ["u", "α", "a"] []
  let lift := ClauseT.mk "lift" (ap "c:Q" [lsucc (V "u2"), ap "c:f" [V "z"]]) ["u2", "z"] []
  let F := match Forest.build goal [refl, lift] with
    | .ok F => F
    | .error e => panic! e
  let F := { F with
    varTypes := #[("n", some nat), ("α", some (ap "sort" [V "u"])), ("a", some (V "α")), ("z", some nat)],
    levelVars := #["u", "u2"],
    groundTypes := #[(nat, some (ap "sort" [lsucc (c "lvl:zero")]))] }
  -- the type of the rigid position `f(z)` (path #[1] of the head of `lift`) is `Nat`
  return { F with clauses := F.clauses.modify 1 fun cl => { cl with headTypes := #[(#[1], some nat)] } }

def objKind : Obj → String
  | .slot _ _ n => if n.startsWith "u" then "level slot" else "term slot"
  | .rigid _ _ _ _ (s, _) _ => if s.startsWith "lvl:" then "rigid level" else "rigid term"
  | .ground t => if t.isLevel then "ground level" else "ground term"
  | .trigid .. => "type template"
  | .value .. => "data value"

def main : IO UInt32 := do
  let P := unitForest
  let mut fails := 0
  for N in [1, 2, 3] do
    let E := encode P N
    let bad := E.allocs.toList.filter (·.2 != 1)
    let missing := E.allocs.toList.filter fun (o, _) => !E.labels.contains o
    let wrongWidth := E.labels.toList.filter fun (_, l) => l.size != E.info.W
    let kinds := (E.labels.toList.map (objKind ·.1)).eraseDups
    let need := ["term slot", "level slot", "rigid term", "rigid level", "ground term", "ground level", "type template"]
    let absent := need.filter (!kinds.contains ·)
    let counts := need.map fun k => (k, (E.labels.toList.filter (objKind ·.1 == k)).length)
    let ok := bad.isEmpty && missing.isEmpty && wrongWidth.isEmpty && absent.isEmpty
    IO.println s!"{if ok then "PASS" else "FAIL"} N = {N}: {E.allocs.size} objects, each label allocated once and cached with width W = {E.info.W}; objects per kind {counts}; {E.info.typing} typing clauses"
    for (o, k) in bad do IO.println s!"  allocated {k} times: {repr o}"
    for (o, _) in missing do IO.println s!"  not cached: {repr o}"
    for (o, l) in wrongWidth do IO.println s!"  width {l.size}: {repr o}"
    unless absent.isEmpty do IO.println s!"  kinds never allocated: {absent}"
    unless ok do fails := fails + 1
  -- the forest is provable in one node by `refl`
  let r ← runSolver (encode P 1).cnf
  IO.println s!"{if r.isSat then "PASS" else "FAIL"} the unit forest is satisfiable at N = 1"
  unless r.isSat do fails := fails + 1
  IO.println s!"M4 unit: {4 - fails} passed, {fails} failed"
  return if fails == 0 then 0 else 1
