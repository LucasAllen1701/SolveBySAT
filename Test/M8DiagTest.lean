/-
Milestone 8b (M8_PLAN §4.3, "Rules"): a diagnostic count against a hand count.

L1 (SPEC 9.1): `∀ x y z w : Nat, x ≤ y → y ≤ z → z ≤ w → x ≤ w` with `H = [Nat.le_trans]`.
The target and every head have only variables as arguments, so there are no rigid positions and
no ground terms, and the only grounding candidates are the eigenvariable slots: x, y, z, w at each
node. The static typing decision keeps all of them (every type is `Nat`). `Nat.le_trans` has three
clause variables, each of the three local hypotheses none.

At N = 2, for each node α and each clause variable of `Nat.le_trans` there are 2 · 4 = 8 candidates:
4 slots at α itself and 4 at the other node. So there are 3 · 8 = 24 `sv` per node, 48 in all:
- node 0: 12 at the same node, 12 at a larger index;
- node 1: 12 at the same node, 12 at a smaller index;
- in all: 24 same node, 12 smaller index, 12 larger index, all of kind "eigenvariable slot".
Decomposition has no pair (no rigid object), so M3 counts 0 clauses.
The test also checks that the recount equals the encoder's family counts.
-/
import SolveBySat
import Lean
import Test.BenchForests
import Test.M8Diag

open Lean Meta SolveBySat

def main : IO UInt32 := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Init }] {}
  let ((goal, H), _, _) ← (leanGoal "L1").toIO { fileName := "<m8diag>", fileMap := default } { env }
  let (C, _, _) ← (compile goal H).toIO { fileName := "<m8diag>", fileMap := default } { env }
  let P := C.forest
  let E := encode P 2 {}
  let out ← IO.mkRef (#[] : Array (String × Json))
  M8Diag.analyze P 2 {} E (fun sec j => out.modify (·.push (sec, j)))
  let secs ← out.get
  let get := fun (sec : String) => (secs.find? (·.1 == sec)).map (·.2) |>.getD Json.null
  let m2 := get "m2"
  let m3 := get "m3"
  let vars := fun (k : String) => ((m2.getObjValD "by").getObjValD k |>.getObjValD "vars").getNat?.toOption.getD 0
  let checks : List (String × Nat × Nat) := [
    ("sv, kind eigenvariable slot", vars "kind:eigenvariable slot", 48),
    ("sv, same node", vars "node:same node", 24),
    ("sv, smaller index", vars "node:smaller index", 12),
    ("sv, larger index", vars "node:larger index", 12),
    ("sv, rigid position", vars "kind:rigid position", 0),
    ("sv, ground object", vars "kind:ground object", 0),
    ("M3 clauses", (m3.getObjValD "total").getNat?.toOption.getD 99, 0),
    ("M2 total equals the family (1 = yes)", if (m2.getObjValD "check_total_equal") == Json.bool true then 1 else 0, 1),
    ("M2 kept candidates mismatch", (m2.getObjValD "check_kept_mismatch").getNat?.toOption.getD 99, 0),
    ("M3 total equals the family (1 = yes)", if (m3.getObjValD "check_total_equal") == Json.bool true then 1 else 0, 1)]
  let mut fails := 0
  for (name, got, want) in checks do
    if got != want then
      fails := fails + 1
      IO.println s!"FAIL {name}: {got}, hand count {want}"
  IO.println s!"M8 diagnostics (L1, N = 2): {checks.length - fails} passed, {fails} failed"
  return if fails == 0 then 0 else 1
