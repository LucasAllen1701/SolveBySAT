/-
SolveBySat.Reference: a brute-force backward-chaining prover over forests, used as a test
oracle (port of `ref` in `reference/diff.py`).

It enumerates proof trees of at most `N` nodes with real syntactic unification and an
occurs check. Eigenvariables become fresh constants, clause variables fresh unification
variables; after a complete proof, each clause variable's value may mention only the
eigenvariables in scope at the node that created it. Groundness is not checked (the
differential test switches it off on the encoder side too). Pure: no `Lean.Meta`.

Terms with binders (milestone 4): `lam`/`pi` over de Bruijn `bvar:i` leaves. Unification
is plain first-order unification on these de Bruijn terms (`bvar:i` is a constant, so
equal means α-equivalent), with the rule that a variable never takes an open value:
after a complete proof, every clause variable's fully resolved value must be closed.
Values are closed, so substituting them under binders needs no shifting.
-/
import SolveBySat.Forest
import Std.Data.HashMap

namespace SolveBySat.Reference

abbrev Subst := Std.HashMap String Term
abbrev Env := Std.HashMap String Term

partial def walk (s : Subst) : Term → Term
  | .var n => match s[n]? with
    | some t => walk s t
    | none => .var n
  | t => t

partial def occurs (s : Subst) (v : String) (t : Term) : Bool :=
  match walk s t with
  | .var n => n == v
  | .app _ as => as.any (occurs s v)

partial def unify (a b : Term) (s : Subst) : Option Subst :=
  match walk s a, walk s b with
  | .var x, .var y => if x == y then some s else bind x (.var y)
  | .var x, t => bind x t
  | t, .var y => bind y t
  | .app f as, .app g bs =>
    if f != g || as.size != bs.size then none
    else (as.zip bs).foldlM (fun s (x, z) => unify x z s) s
where
  bind (x : String) (t : Term) : Option Subst :=
    if occurs s x t then none else some (s.insert x t)

def inst (env : Env) (t : Term) : Term := t.subst (env[·]?)

def eigPrefix := "ev#"

partial def eigsOf (s : Subst) (t : Term) : Std.HashSet String :=
  match walk s t with
  | .var _ => {}
  | .app f as =>
    let r : Std.HashSet String := if f.startsWith eigPrefix then ({} : Std.HashSet String).insert f else {}
    as.foldl (fun r a => r.insertMany (eigsOf s a)) r

/-- Resolve a term through the substitution, all the way down. -/
partial def resolve (s : Subst) (t : Term) : Term :=
  match walk s t with
  | .var n => .var n
  | .app f as => .app f (as.map (resolve s))

structure St where
  uid : Nat := 0
  s : Subst := {}
  /-- For each clause-variable instance, the eigenvariables in scope where it was made. -/
  allowed : Std.HashMap String (Std.HashSet String) := {}
  /-- Instantiated rigid template positions of the nodes of the proof (the encoder's rigid
  and value objects): grounding candidates, resolved at the end. -/
  used : Array Term := #[]
  /-- Eigenvariables introduced at the nodes of the proof (grounding candidates). -/
  eigs : Array Term := #[]

/-- Non-variable, non-ground subterms of a template (its rigid positions). For an atom
(`atom := true`) the atom itself is not a position. -/
partial def rigidPositions (t : Term) (atom : Bool) : Array Term :=
  let here := if atom || t.isVar || t.isGround then #[] else #[t]
  t.args.foldl (fun acc a => acc ++ rigidPositions a false) here

/-- Ground subterms of the arguments of a template (the encoder's ground objects). -/
partial def groundSubterms (t : Term) : Array Term :=
  t.args.foldl (fun acc a => acc ++ (if a.isGround then #[a] else #[]) ++ groundSubterms a) #[]

/-- Ground objects of the forest that may ground a variable (SPEC §6.8): every ground
subterm of every target, head and data value (below the value itself), of term kind. -/
def groundCands (P : Forest) : Array Term :=
  let fromAtoms := (P.goals.map (·.tgt) ++ P.clauses.map (·.head)).flatMap groundSubterms
  let fromValues := P.clauses.filterMap (·.dataVal) |>.flatMap groundSubterms
  (fromAtoms ++ fromValues).filter (·.isTermKind)

/-- Search for proofs of goal position `g` within `budget` nodes. `k st used` is called
for each proof found with the resulting state and its number of nodes; the search
succeeds as soon as some continuation does. A data position (SPEC §6.9) is proved by a
data clause, whose value is unified with the variable being built; proposition
positions only by proof clauses. Data children of a clause are optional. -/
partial def prove (P : Forest) (g : Nat) (env : Env) (ctx : Array (Nat × Env))
    (scope : Std.HashSet String) (st : St) (budget : Nat) (k : St → Nat → Bool) : Bool := Id.run do
  if budget < 1 then return false
  let gp := P.goals[g]!
  let mut envg := env
  let mut st := st
  let mut sc := scope
  for b in gp.eig do
    st := { st with uid := st.uid + 1 }
    let e := s!"{eigPrefix}{st.uid}"
    envg := envg.insert b (.const e)
    sc := sc.insert e
    st := { st with eigs := st.eigs.push (.const e) }
  let ctx2 := ctx ++ gp.hyps.map (·, envg)
  let goal := inst envg gp.tgt
  let tgtPos := (rigidPositions gp.tgt true).map (inst envg)
  let globals := (List.range P.clauses.size).toArray.filter (P.clauses[·]!.localOf.isNone)
  for (c, envc) in ctx2 ++ globals.map (·, ({} : Env)) do
    let cl := P.clauses[c]!
    if cl.dataVal.isSome != gp.dataVar.isSome then continue
    let mut envc := envc
    let mut st1 := st
    for v in cl.vars do
      st1 := { st1 with uid := st1.uid + 1 }
      let x := s!"_{st1.uid}"
      envc := envc.insert v (.var x)
      st1 := { st1 with allowed := st1.allowed.insert x sc }
    let some s1 := unify goal (inst envc cl.head) st1.s | continue
    -- a data node: the variable being built equals the value
    let mut s1 := s1
    let mut valPos : Array Term := #[]
    if let (some b, some v) := (gp.dataVar, cl.dataVal) then
      let some s2 := unify (inst envg (.var b)) (inst envc v) s1 | continue
      s1 := s2
      valPos := #[inst envc v] ++ (rigidPositions v true).map (inst envc)
    let st2 := { st1 with s := s1,
                          used := st1.used ++ tgtPos ++ (rigidPositions cl.head true).map (inst envc) ++ valPos }
    let n := cl.prems.size
    let dps := cl.dataPos
    let rec kids (i : Nat) (st : St) (used : Nat) : Bool :=
      if i < n then
        prove P cl.prems[i]! envc ctx2 sc st (budget - used - (n - i - 1))
          (fun st' u2 => kids (i + 1) st' (used + u2))
      else if i < n + dps.size then
        kids (i + 1) st used ||
          prove P dps[i - n]!.2 envc ctx2 sc st (budget - used)
            (fun st' u2 => kids (i + 1) st' (used + u2))
      else k st used
    if kids 0 st2 1 then return true
  return false

/-- Scope and closed values (milestones 1 and 4). -/
def scopeOk (st : St) : Bool :=
  st.allowed.toList.all fun (v, ok) =>
    (eigsOf st.s (.var v)).toList.all ok.contains && !(resolve st.s (.var v)).isOpen

/-- Groundness (SPEC §6.8, untyped): every clause variable of the proof equals a candidate:
an instantiated rigid position of a node of the proof, a ground object, or an
eigenvariable of a node of the proof. A variable that unification left open may be
equated with any candidate (the encoder may choose any), so the search tries each. -/
partial def groundSearch (gc : Array Term) (st : St) : Bool :=
  let cands := ((st.used ++ st.eigs).map (resolve st.s)).filter (!·.isOpen) ++ gc
  match st.allowed.toList.find? (fun (v, _) => !cands.contains (resolve st.s (.var v))) with
  | none => scopeOk st
  | some (v, _) =>
    let r := resolve st.s (.var v)
    cands.any fun c => match unify r c st.s with
      | some s' => groundSearch gc { st with s := s' }
      | none => false

/-- Is there a proof of the root goal with at most `N` nodes? -/
def provable (P : Forest) (N : Nat) (groundness : Bool := false) : Bool :=
  let gc := groundCands P
  prove P 0 {} #[] {} {} N fun st _ =>
    if groundness then groundSearch gc st else scopeOk st

end SolveBySat.Reference
