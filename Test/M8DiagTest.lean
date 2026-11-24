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

Milestone 8c-1 (M8_PLAN 3.4, 3.5, 4.4): a hand count of what R1 and R2 remove, on the untyped
forest K below, at N = 3:

    goal g0: P(f(a))
    p1: P(f(X)) :- Q(X)            premise g1
    p2: P(f(Y)) :- Q(Y), Q(Y)      premises g2, g3
    qa: Q(a)

- Least sizes: s(g1) = s(g2) = s(g3) = 1 (qa); cs(p1) = 2, cs(p2) = 3, cs(qa) = 1; s(g0) = 2.
  Least depths: d(g0) = 0, d(g1) = d(g2) = d(g3) = 1; cd(p1) = cd(p2) = 0, cd(qa) = 1.
- Dead at N = 3: gp(2, g0) (2 + 2 > 3), gp(0, g1), gp(0, g2), gp(0, g3) (depth 1 > 0): 4;
  cl(2, p1) (2 + 2 > 3), cl(1, p2), cl(2, p2) (α + 3 > 3), cl(0, qa) (depth 1 > 0): 4.
  So 8 unit clauses.
- Rigid objects: f(X) of p1 and f(Y) of p2 at each node: 6 without R1; with R1 f(X) at nodes 0
  and 1 and f(Y) at node 0: 3.
- Decomposition (symbol f/1, with the ground object f(a)): all pairs unify, so every pair is full:
  C(7, 2) = 21 pairs without R1, C(4, 2) = 6 with R1.
- R2: two objects at one node owned by p1 and p2. Without R1 one per node: 3 pairs skipped
  (18 left); with R1 only node 0: 1 skipped (5 left).
- Groundness: the candidates are the rigid objects and the ground terms a and f(a) (no types,
  so no candidate is dropped). Without R1: 6 slots (X at 3 nodes, Y at 3) × 8 candidates = 48 `sv`;
  with R1: the slots of cl(0, p1), cl(1, p1), cl(0, p2), 3 × 5 = 15 `sv`.
- At N = 1, s(g0) = 2 > 1: the early exit, one empty clause.
-/
import SolveBySat
import Lean
import Test.BenchForests
import Test.M8Diag

open Lean Meta SolveBySat

def kForest : Forest :=
  let c := fun (s : String) => SolveBySat.Term.const s
  let V := fun (n : String) => SolveBySat.Term.var n
  let atm := fun (p : String) (as : List SolveBySat.Term) => SolveBySat.Term.app p as.toArray
  let g := fun (t : SolveBySat.Term) => GoalT.mk t [] []
  match Forest.build (g (atm "P" [atm "f" [c "a"]]))
      [.mk "p1" (atm "P" [atm "f" [V "X"]]) ["X"] [g (atm "Q" [V "X"])],
       .mk "p2" (atm "P" [atm "f" [V "Y"]]) ["Y"] [g (atm "Q" [V "Y"]), g (atm "Q" [V "Y"])],
       .mk "qa" (atm "Q" [c "a"]) [] []] with
  | .ok F => F
  | .error e => panic! e

/-- The recount sections of one encoding of K, with the hand counts. -/
def kChecks (label : String) (N : Nat) (opts : EncodeOptions) (want : List (String × Nat)) : IO Nat := do
  let P := kForest
  let E := encode P N opts
  let out ← IO.mkRef (#[] : Array (String × Json))
  M8Diag.analyze P N opts E (fun sec j => out.modify (·.push (sec, j)))
  let secs ← out.get
  let get := fun (sec : String) => (secs.find? (·.1 == sec)).map (·.2) |>.getD Json.null
  let num := fun (j : Json) (k : String) => (j.getObjValD k).getNat?.toOption.getD 999999
  let yes := fun (j : Json) (k : String) => if j.getObjValD k == Json.bool true then 1 else 0
  let svs := ((get "m2").getObjValD "by").getObjValD "kind:rigid position" |>.getObjValD "vars" |>.getNat?.toOption.getD 0
  let svg := ((get "m2").getObjValD "by").getObjValD "kind:ground object" |>.getObjValD "vars" |>.getNat?.toOption.getD 0
  let got : List (String × Nat) := [
    ("early exit", if E.info.earlyExit then 1 else 0), ("clauses", E.cnf.numClauses),
    ("gp dead", E.info.gpDead), ("cl dead", E.info.clDead), ("unit clauses", num (get "r1") "unit_clauses"),
    ("rigid objects", E.info.rigid), ("full pairs", E.info.pairs), ("R2 skipped", E.info.exclusiveSkipped),
    ("sv", svs + svg),
    ("recount: groundness equal", yes (get "m2") "check_total_equal"),
    ("recount: decomposition equal", yes (get "m3") "check_total_equal"),
    ("recount: kept candidates mismatch", num (get "m2") "check_kept_mismatch"),
    ("recount: units equal", yes (get "r1") "check_units_equal"),
    ("recount: R2 skipped equal", yes (get "m3") "check_exclusive_equal")]
  let mut fails := 0
  for (k, w) in want do
    let g := (got.find? (·.1 == k)).map (·.2) |>.getD 999999
    if g != w then
      fails := fails + 1
      IO.println s!"FAIL K, {label}, N = {N}, {k}: {g}, hand count {w}"
  return fails

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
  -- 8c-1: R1 and R2 on K
  let rc := [("recount: groundness equal", 1), ("recount: decomposition equal", 1),
             ("recount: kept candidates mismatch", 0)]
  let r1c := rc ++ [("recount: units equal", 1), ("recount: R2 skipped equal", 1)]
  let cases : List (String × Nat × EncodeOptions × List (String × Nat)) := [
    ("flags off", 3, {}, rc ++ [("gp dead", 0), ("cl dead", 0), ("rigid objects", 6), ("full pairs", 21),
      ("R2 skipped", 0), ("sv", 48)]),
    ("R1", 3, { nodeBounds := true }, r1c ++ [("gp dead", 4), ("cl dead", 4), ("unit clauses", 8),
      ("rigid objects", 3), ("full pairs", 6), ("R2 skipped", 0), ("sv", 15)]),
    ("R1 and R2", 3, { nodeBounds := true, exclusivePairs := true }, r1c ++ [("gp dead", 4), ("cl dead", 4),
      ("rigid objects", 3), ("full pairs", 5), ("R2 skipped", 1), ("sv", 15)]),
    ("R2", 3, { exclusivePairs := true }, rc ++ [("rigid objects", 6), ("full pairs", 18), ("R2 skipped", 3),
      ("recount: R2 skipped equal", 1)]),
    ("R1, early exit", 1, { nodeBounds := true }, [("early exit", 1), ("clauses", 1)])]
  let mut kf := 0
  let mut kn := 0
  for (label, N, o, want) in cases do
    kf := kf + (← kChecks label N o want)
    kn := kn + want.length
  IO.println s!"M8 diagnostics, R1 and R2 (K, N = 3 and 1): {kn - kf} passed, {kf} failed"
  return if fails == 0 && kf == 0 then 0 else 1
