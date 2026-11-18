/-
SolveBySat.Term: first-order term templates and symbols (SPEC §4.4).

A template is a tree whose leaves are static variables or constants. Atoms use the same
type: the predicate symbol is the head of an `app`. Pure: no `Lean.Meta`.
-/
import Std.Data.HashSet
import Std.Data.HashMap

namespace SolveBySat

inductive Term where
  /-- A static variable (SPEC §4.3), by its globally unique name. -/
  | var (name : String)
  /-- A rigid term: symbol applied to arguments; a constant has no arguments. -/
  | app (sym : String) (args : Array Term)
  deriving BEq, Hashable, Repr, Inhabited, Ord

namespace Term

def const (s : String) : Term := .app s #[]

def isVar : Term → Bool
  | .var _ => true
  | .app .. => false

/-- Symbol key: name and arity. Two rigid terms can only be equal if their keys agree. -/
def symKey : Term → Option (String × Nat)
  | .var _ => none
  | .app s as => some (s, as.size)

def args : Term → Array Term
  | .var _ => #[]
  | .app _ as => as

partial def varsOf : Term → Std.HashSet String
  | .var n => ({} : Std.HashSet String).insert n
  | .app _ as => as.foldl (fun s a => s.insertMany (varsOf a)) {}

partial def isGround : Term → Bool
  | .var _ => false
  | .app _ as => as.all isGround

/-- Template height used for the `rank` width (SPEC §5.3, `d`). A variable leaf counts 1,
a constant 0, an application `1 + max` over its arguments. This is what the prototype's
`height` computes for single-character variable names; see NOTES.md (milestone 1). -/
partial def height : Term → Nat
  | .var _ => 1
  | .app _ as => if as.isEmpty then 0 else 1 + as.foldl (fun m a => max m (height a)) 0

/-- Symbols of level templates start with this prefix (SPEC §4.4: `zero`, `succ`, `max`,
`imax`, level parameters of the goal). Level objects are never candidates for a
term-kind clause variable (SPEC §6.8). -/
def levelPrefix : String := "lvl:"

def isLevel : Term → Bool
  | .var _ => false
  | .app s _ => s.startsWith levelPrefix

/-- The single constant that stands for every proof subterm (SPEC §4.4). -/
def proofSym : String := "⟨proof⟩"


/-- Number of non-ground application nodes (rigid positions) in the term, itself included. -/
partial def rigidCount : Term → Nat
  | .var _ => 0
  | t@(.app _ as) => (if t.isGround then 0 else 1) + as.foldl (fun n a => n + rigidCount a) 0

/-- Binders inside terms (SPEC §4.4): `lam`/`pi` over the binder type and the body; the
bound variable is the leaf `bvar:i` (de Bruijn index). -/
def bvarSym (i : Nat) : String := s!"bvar:{i}"

def bvarIdx? : Term → Option Nat
  | .app s #[] => if s.startsWith "bvar:" then (s.drop 5).toString.toNat? else none
  | _ => none

/-- One more than the largest loose de Bruijn index (0 if closed), as `Expr.looseBVarRange`. -/
partial def looseRange (t : Term) : Nat :=
  match t.bvarIdx? with
  | some i => i + 1
  | none => match t with
    | .var _ => 0
    | .app s #[d, b] =>
      if s == "lam" || s == "pi" then max (looseRange d) (looseRange b - 1)
      else max (looseRange d) (looseRange b)
    | .app _ as => as.foldl (fun m a => max m (looseRange a)) 0

/-- Some subterm is a bound-variable leaf (equivalently: some subterm is open). -/
partial def hasBVar (t : Term) : Bool :=
  t.bvarIdx?.isSome || t.args.any hasBVar

/-- The term has a loose bound variable (SPEC §4.4, `open`). -/
def isOpen (t : Term) : Bool := t.looseRange > 0

/-- Ground objects that may ground a term-kind clause variable: not a level, not the proof
placeholder (a clause variable is never a proof: Prop binders are premises), not open. -/
def isTermKind (t : Term) : Bool := !t.isLevel && t != .app proofSym #[] && !t.isOpen

/-- Simultaneous substitution of variables. Unmapped variables are kept. -/
partial def subst (σ : String → Option Term) : Term → Term
  | .var n => (σ n).getD (.var n)
  | .app s as => .app s (as.map (subst σ))

/-- Do `t₁` and `t₂` unify after renaming the variables of `t₂` apart (first-order, with an
occurs check; `bvar:i` leaves are constants, so equality is α-equivalence)? Used by the
pruning refinements of SPEC §6.10: two template positions whose instances can ever be
equal must unify in this sense. -/
partial def unifiableApart (t₁ t₂ : Term) : Bool :=
  let t₂ := t₂.subst fun n => some (.var ("'" ++ n))
  (go t₁ t₂ {}).isSome
where
  walk (s : Std.HashMap String Term) : Term → Term
    | .var n => match s[n]? with
      | some t => walk s t
      | none => .var n
    | t => t
  occurs (s : Std.HashMap String Term) (v : String) (t : Term) : Bool :=
    match walk s t with
    | .var n => n == v
    | .app _ as => as.any (occurs s v)
  go (a b : Term) (s : Std.HashMap String Term) : Option (Std.HashMap String Term) :=
    match walk s a, walk s b with
    | .var x, .var y => if x == y then some s else some (s.insert x (.var y))
    | .var x, t | t, .var x => if occurs s x t then none else some (s.insert x t)
    | .app f as, .app g bs =>
      if f != g || as.size != bs.size then none
      else (as.zip bs).foldlM (fun s (x, z) => go x z s) s

partial def toString : Term → String
  | .var n => "?" ++ n
  | .app s as => if as.isEmpty then s else s ++ "(" ++ ", ".intercalate (as.map toString).toList ++ ")"

instance : ToString Term := ⟨toString⟩

end Term
end SolveBySat
