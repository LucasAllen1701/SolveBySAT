# Solve By SAT: revised specification

Nov 16, 2026 · @Lucas

## 1. Overview and contract

`solve_by_sat` takes a closed goal `G`, a list `H` of constants and a bound `N`, and builds one CNF formula. The formula is satisfiable exactly when `G` has a proof of at most `N` nodes in the proof class of section 2. A satisfying assignment is decoded into a Lean term, which the kernel then checks.

The implementation must meet three properties, and the tests in section 9 check each one.

1. **Soundness.** If the CNF is satisfiable, decoding returns a term `t` and the kernel accepts `t : G`.
2. **Completeness.** If a proof in the class with at most `N` nodes exists, the CNF is satisfiable.
3. **One shot.** The CNF is built once, before the solver runs. Nothing is fed back from Lean to the solver, and the CNF size is polynomial in `N` and the size of `H` (section 7).

A **node** is one application of a hypothesis, a local hypothesis or a built-in connective rule, together with the `intro` steps that precede it. Arguments that unification infers cost no nodes, like `_` in Lean.

The method is backward chaining: introduce the binders of the goal, apply a hypothesis whose conclusion matches, and repeat on its premises. The SAT solver chooses the hypothesis at each node and the tree shape. Unification is not computed beforehand; it is encoded in the CNF as labels on terms (section 6.5).

## 2. Scope

The reduction covers backward-chaining proofs over first-order hereditary Harrop formulas, with syntactic unification. In tactic terms it mimics `intro`, `apply`, `exact`, `constructor` on `∧ ∨ ↔ True`, and `exists` when the witness is determined. It does not mimic `rw`, `cases` or `induction`.

### 2.1 Supported formulas

Two shapes are defined by mutual recursion and read off a Lean type after the preprocessing of section 4.1.

- A **goal formula** is `∀ b₁ … bₘ, R`. A non-Prop binder is an **eigenvariable**: a fresh local constant after `intro`. A Prop binder is a **local hypothesis**, and its type must be a clause formula. The target `R` is an atom, or one of `A ∧ B`, `A ∨ B`, `∃ x, A`, `A ↔ B`, `True` with `A`, `B` goal formulas.
- A **clause formula** is `∀ a₁ … aₖ, R`. A non-Prop binder is a **clause variable**: a fresh metavariable at each use. A Prop binder is a **premise**, and its type must be a goal formula. The head `R` is an atom, or `A ∧ B` or `A ↔ B`, which are split into projections.
- An **atom** is an application whose head is a constant or an eigenvariable. Its arguments are arbitrary Lean terms in which clause variables occur only unapplied.

The goal must be a goal formula, and every constant in `H` must have a clause formula as its type. Anything else is rejected with an error that names the reason.

| Statement | Status | Reason |
| --- | --- | --- |
| `Nat.le_trans : n ≤ m → m ≤ k → n ≤ k` | accepted | atoms with rigid heads |
| `Nat.succ_le_succ : n ≤ m → succ n ≤ succ m` | accepted | clause variables only as arguments |
| a premise `∀ y, P x y → Q y` | accepted | nested `intro` |
| `And.intro`, `Or.inl`, `Or.inr`, `Exists.intro`, `Iff.intro` | built in, not listed in `H` | their premises are bare proposition variables, so they are specialised per goal |
| `Or.elim`, `False.elim`, `absurd`, `Classical.em` | rejected | the head is a bare proposition variable |
| `congrArg : a = b → f a = f b` | rejected | the clause variable `f` is applied |
| `Nat.rec`, `Eq.subst`, `Eq.mpr` | rejected | they need a motive |

### 2.2 The proof class

A proof in the class is a tree. Each node solves one instance of a goal formula in three steps.

1. Introduce every binder of the goal formula.
2. Apply one rule to the target. For a connective, the rule is its introduction rule. For an atom, the rule is a clause, either from `H` or a local hypothesis in scope, whose head equals the target after substituting terms for its clause variables.
3. Prove each premise of the rule in a child node.

Four conditions make a tree a proof.

- **Syntactic equality.** Head and target must be the same Lean expression after substitution, up to bound-variable names. Proof terms inside expressions are ignored. No unfolding or computation is used.
- **Determined arguments.** Each clause variable must equal a term that occurs in an instantiated statement used in the proof, or be built by a child from data constants in `H` (milestone 5). Nothing may be left undetermined.
- **Typing.** A value given to a clause variable has that variable's type.
- **Scope.** A value may mention an eigenvariable only if it was introduced at the node that created the variable, or at an ancestor.

The size of a proof is its number of nodes.

### 2.3 What it can prove

| Kind | Example | Nodes |
| --- | --- | --- |
| Chains of lemmas | `x ≤ w` from `x ≤ y`, `y ≤ z`, `z ≤ w` and `Nat.le_trans` | 5 |
| Implications with hypotheses | `(A → B) → (B → C) → A → C` | 3 |
| Quantified hypotheses | `Q a` from `∀ y, P y → Q y` and `P a` | 2 |
| Connectives in goals | `A ∧ B` from `A` and `B`; `A ∨ B` from `B` | 3; 2 |
| Existentials, witness forced | `∃ x, x ≤ b` from `a ≤ b` | 2 |
| Negation as implication | `¬A` goals and hypotheses, with `False` as an ordinary atom | varies |
| Reflexivity | `a = a` by `Eq.refl` when both sides are identical | 1 |
| Conjunctive and iff hypotheses | using `h : A ∧ B` or `h : A ↔ B` through projections | varies |

### 2.4 What stays out of reach

| Category | Example | Why |
| --- | --- | --- |
| Rewrite, cases, induction | `Nat.rec`, `Eq.mpr`, splitting `h : A ∨ B`, destructuring `h : ∃ x, P x` | need a motive, or elimination into an arbitrary goal |
| Ex falso and classical logic | `False.elim`, `absurd`, `Classical.em`, proof by contradiction | the conclusion is a bare proposition variable |
| Unfolding and computation | `2 + 2 = 4`; `n + 1` against `Nat.succ n`; `a ⊆ b`; `Function.Injective f` | only `Not` and `Ne` are unfolded |
| Higher-order unification | `congrArg`, function witnesses that are then applied | needs β-reduction inside unification |
| Type class resolution | an instance argument that is definitionally but not syntactically the expected one | instances are found only by unification |
| Proof-dependent types | a binder whose type mentions an earlier proof variable | rejected at compile time |
| Lemma reuse | a sub-proof needed twice | proofs are trees, so it is counted twice; there is no `have` |
| Large problems | long hypothesis lists or large `N` | the CNF grows roughly as N³ and quadratically in the size of `H` (section 7) |

## 3. Architecture

The implementation is a four-stage pipeline in which only the first and last stages touch Lean's metaprogramming API. The middle two work on plain data, so they can be tested without Lean expressions.

1. **Compile** (`MetaM`). Turn the goal and each constant in `H` into a clause forest: clauses, goal positions and term templates (section 4).
2. **Encode** (pure). Turn the forest and `N` into a CNF (sections 5 and 6).
3. **Solve** (`IO`). Write DIMACS, run a SAT solver, read the model.
4. **Decode** (`MetaM`). Read the proof tree from the model, rebuild the term, and have the kernel check it (section 8).

| Module | Content | Uses Lean `Meta` |
| --- | --- | --- |
| `SolveBySat/Term.lean` | first-order term templates and symbols | no |
| `SolveBySat/Forest.lean` | clauses, goal positions, frames, well-formedness check | no |
| `SolveBySat/Compile.lean` | `Expr` to forest, with rejection messages | yes |
| `SolveBySat/CNF.lean` | variable allocation, clause builder with constant folding, bit-vector equality and less-than, at-most-one, DIMACS output | no |
| `SolveBySat/Encode.lean` | the clause families of section 6 | no |
| `SolveBySat/Solver.lean` | run the solver, parse the model | no |
| `SolveBySat/Decode.lean` | model to proof skeleton, replay, kernel check | yes |
| `SolveBySat/Tactic.lean` | `solve_by_sat [h₁, …] (nodes := N)` | yes |
| `SolveBySat/Reference.lean` | brute-force prover over forests, used as a test oracle | no |
| `Test/` | fixed tests, differential tests, Lean examples | mixed |

**Dependencies.** Lean core and `Std` only, no Mathlib. For the solver, recent Lean toolchains bundle CaDiCaL for `bv_decide`. Check on the installed toolchain how to locate that binary; otherwise require `cadical` on `PATH`. This was not verified when the spec was written.

**Reference prototype.** A Python prototype of stages 2 and 3 accompanies this spec (`enc.py`, `tests.py`, `diff.py`, `cdcl.c`). It is the executable form of sections 5 and 6.1 to 6.8 for untyped forests. Where the prose and the prototype disagree on those sections, the prototype is right, because it is the version that was tested.

## 4. Compilation: from Lean to a clause forest

Compilation produces a finite, static structure called the **clause forest**. It is finite because every clause and goal position is a subformula of the goal or of a statement in `H`.

### 4.1 Preprocessing

The tactic first reverts the whole local context, so the goal is closed. Each type is then normalised by exactly these steps and no others:

- instantiate metavariables, strip metadata, β-reduce, and inline `let`;
- unfold `Not`, `Ne`, `GE.ge` and `GT.gt`.

There is no `whnf` and no other unfolding. This keeps the proof class predictable.

### 4.2 Goal positions and clauses

| Object | Fields |
| --- | --- |
| Goal position `g` | `eig(g)`: its non-Prop binders. `loc(g)`: the clauses made from its Prop binders. `tgt(g)`: its target atom. Its owner: the root, or premise `k` of a clause. |
| Clause `c` | `vars(c)`: its non-Prop binders, plus its universe parameters if it is a constant. `prem(c)`: one goal position per Prop binder. `head(c)`: its head atom. Its origin: a constant in `H`, a local hypothesis of a goal position, or a built-in rule. |

The forest is built by recursion: the goal gives the root goal position, each constant in `H` gives a global clause, each premise gives a goal position, and each Prop binder of a goal position gives a local clause.

**Connectives in targets** become built-in clauses that belong to the goal position and can only be applied at the node that owns it. Their head is the target itself.

| Target of `g` | Built-in clauses | Clause variables | Premises | Proof term |
| --- | --- | --- | --- | --- |
| `A ∧ B` | one | none | `A`, `B` | `And.intro` |
| `A ∨ B` | two | none | `A`; or `B` | `Or.inl`; `Or.inr` |
| `∃ x : τ, A` | one | `w : τ` | `A` with `x := w` | `Exists.intro w` |
| `A ↔ B` | one | none | `A → B`, `B → A` | `Iff.intro` |
| `True` | one | none | none | `True.intro` |

**Connectives in heads** are removed by splitting. A clause with head `A ∧ B` becomes two clauses with heads `A` and `B`, whose proof terms wrap the original in `And.left` and `And.right`. A clause with head `A ↔ B` becomes one clause with head `B` and extra premise `A` (`Iff.mp`), and one with head `A` and extra premise `B` (`Iff.mpr`). Splitting repeats until every head is an atom.

### 4.3 Static variables and frames

Every non-Prop binder in the forest is a **static variable** with a globally unique name. Each has a kind (`term` or `level`) and, for kind `term`, a type template.

The variables visible at a position are defined by `Env`:

- `Env(root) = ∅`, and `Env(c) = ∅` for a global clause;
- `Env(c) = Env(g) ∪ eig(g)` for a clause `c` local to `g`, including built-in clauses;
- `Env(g) = Env(c) ∪ vars(c)` for a premise `g` of `c`.

The **goal frame** of `g` is `Env(g) ∪ eig(g)`; `tgt(g)` is a template over it. The **clause frame** of `c` is `Env(c) ∪ vars(c)`; `head(c)` is a template over it.

### 4.4 Term templates

An atom is a predicate symbol with argument templates. A template is a tree whose leaves are static variables or constants, built from a Lean expression as follows.

| Lean expression | Template |
| --- | --- |
| a static variable, unapplied | variable leaf |
| an eigenvariable applied to `k` arguments, `k ≥ 1` | symbol `app/(k+1)` over the variable and its arguments |
| a clause variable applied to arguments | compile error: not first order |
| `c.{l₁…lₘ} a₁ … aₖ` | symbol `(c, m, k)` over the levels, then the arguments |
| `fun x : τ => b`, or `∀ x : τ, b` inside a term | symbol `lam` or `pi` over `τ` and `b`; the inner bound variable is a symbol `bvar i` |
| `Sort l`, literals, projections | symbols `sort` over `l`; a constant per literal; `(proj S i)` over the structure |
| universe levels | symbols `zero`, `succ`, `max`, `imax`; a parameter of the goal is a constant, a parameter of a hypothesis is a `level` variable |
| a subterm that is a proof | the single constant `⟨proof⟩` |

An atom whose head is an eigenvariable, such as a proposition variable `A`, uses the predicate symbol `app` with the variable as its first argument.

Compilation records three facts for each template node: whether it is **ground** (no static variables), whether it is **open** (it contains a `bvar` bound outside itself), and, for term-kind nodes, its **type template** obtained with `inferType`.

### 4.5 Rejections

Compilation fails with a specific message in these cases: a head or target whose head symbol is a clause variable; a clause variable applied to arguments; a binder type that mentions a proof variable; a Prop binder of a goal that is not a clause formula; a premise that is not a goal formula; an `∃` whose body is not a literal `fun` after η-expansion.

## 5. SAT variables

The CNF has two groups of variables: structural variables that describe the proof tree, and label bits that describe the values of terms. Nodes are numbered `0` to `N − 1`, node `0` is the root, and a parent always has a smaller number than its children.

### 5.1 Structural variables

| Variable | Meaning | Count |
| --- | --- | --- |
| `act(α)` | node α is used | N |
| `cl(α, c)` | node α applies clause `c` | N · C |
| `gp(α, g)` | node α solves goal position `g` | N · G |
| `y(α, β, k)`, α < β | node β proves premise `k` of node α | N² · A / 2 |
| `anc(γ, β)`, γ < β | node γ is a proper ancestor of node β | N² / 2 |
| `u(β, γ)`, γ ≤ β | the local clause applied at β was introduced at node γ | N² / 2 |

Here `C` is the number of clauses in the forest, `G` the number of goal positions, and `A` the largest number of premises of any clause.

### 5.2 Term objects

Each node owns a private copy of every template, so the same lemma can be used at several nodes with different instantiations.

| Object | One per | Active when |
| --- | --- | --- |
| **Goal slot** `(α, goal, b)` | node α and static variable `b` | always allocated; constrained only when in use |
| **Clause slot** `(α, clause, b)` | node α and static variable `b` | same |
| **Rigid object** `(α, p)` | node α and non-ground template position `p` below an atom | `gp(α, g)` or `cl(α, c)`, for the template that contains `p` |
| **Ground object** | distinct closed ground subterm, shared by all nodes | always |

The arguments of `tgt(g)` at node α are built over α's goal slots, and the arguments of `head(c)` over α's clause slots. Two frames per node are necessary: with one, a clause applied inside its own premise would share its variables with the parent's instance. The prototype found this.

Atoms themselves are not objects. Only their arguments and the subterms below them are.

### 5.3 Labels

Every object carries a **label**, a fixed-width bit vector. Two objects have the same value exactly when their labels are equal, so a label acts as the name of an equivalence class of terms.

| Field | Width in bits | Meaning | Rigid object | Ground object | Eigenvariable slot |
| --- | --- | --- | --- | --- | --- |
| `sym` | log₂(number of symbols + 1) | head symbol of the class | constant: its symbol | constant | constant `EV` |
| `idx` | log₂(N·T + ground terms + N·E + 1) | separates classes with the same symbol | free | constant: its unique id | constant: unique id of (α, b) |
| `rank` | log₂(N·(d + 1) + 2) | height of the class, for the occurs check | free | constant: its height | constant 0 |
| `esc` | N | the nodes whose eigenvariables occur in the value | free | constant: empty | constant: only bit α |
| `open` | 1 | the value has a loose inner bound variable | constant: static | constant 0 | constant 0 |

`T` is the number of non-ground template positions, `E` the number of eigenvariable binders, and `d` the greatest template depth. All fields of an ordinary slot are free, except `open`, which is 0. Widths are rounded up. The total width is written `W`.

All remaining variables are auxiliaries introduced by the clause families: `sm` (two rigid objects are in the same class), `d` (a bit differs), the less-than chain, and `sv` (a grounding witness).

## 6. Clause families

The CNF is the conjunction of the families below. Families 6.1 to 6.8 are implemented and tested in the prototype, except the typing part of 6.8.

**Conventions.** `L(o)` is the label of object `o`. `X ⇒ L(o) = L(o')` means bitwise equality under condition `X`: two clauses per pair of free bits, one per free bit against a constant, and the single clause `¬X` if two constant bits differ. "At most one" may use the pairwise or the ladder encoding. The clause builder must fold constant bits and drop tautologies.

### 6.1 Node assignment

- `act(0)`, and `act(α+1) ⇒ act(α)`: used nodes form a prefix.
- At most one `cl(α, c)` per node; `act(α) ⇒` some `cl(α, c)`; `cl(α, c) ⇒ act(α)`.
- The same three constraints for `gp(α, g)`.
- `gp(0, root)`.

### 6.2 Tree shape

- For β ≥ 1: `act(β) ⇒` some `y(α, β, k)`; at most one `y(α, β, k)` over all α and `k`; `y(α, β, k) ⇒ act(α)` and `act(β)`.
- For each α and `k`: at most one β with `y(α, β, k)`.
- If `k` is a premise of `c`: `cl(α, c) ⇒` some `y(α, β, k)`. Otherwise `cl(α, c) ⇒ ¬y(α, β, k)` for every β.
- `cl(α, c) ∧ y(α, β, k) ⇒ gp(β, prem(c, k))`.

### 6.3 Context

These clauses replace the `z` variables of the original draft. A local hypothesis may be used only below the node that introduced it, and each use says which node that was.

- At most one γ with `u(β, γ)`.
- For a global clause `c`: `cl(β, c) ⇒ ¬u(β, γ)` for every γ.
- For a clause `c` local to goal position `g`: `cl(β, c) ⇒` some `u(β, γ)` with γ ≤ β, and `u(β, γ) ∧ cl(β, c) ⇒ gp(γ, g)`. For a built-in clause, additionally `cl(β, c) ⇒ u(β, β)`.
- `u(β, γ) ⇒ anc(γ, β)` for γ < β.
- `anc(γ, β) ⇒ act(β)`. For γ < α < β: `anc(γ, β) ∧ y(α, β, k) ⇒ anc(γ, α)`. For α < γ: `¬anc(γ, β) ∨ ¬y(α, β, k)`.

Only this direction is needed for `anc`: it may be true only when γ really is an ancestor. Nothing requires it to be true.

### 6.4 Matching

For every node α, goal position `g` and clause `c`:

- if the predicate symbols or arities of `tgt(g)` and `head(c)` differ: `¬gp(α, g) ∨ ¬cl(α, c)`;
- otherwise, for each argument position `i`: `gp(α, g) ∧ cl(α, c) ⇒ L(argᵢ of tgt(g) at α) = L(argᵢ of head(c) at α)`.

### 6.5 Decomposition

This family makes label equality behave like equality of terms. For every unordered pair of rigid or ground objects `o`, `o'` with the same symbol and arity, not both ground, and with no constant bits that differ, introduce `sm`:

- for each bit position `j` where both bits are free, a fresh `dⱼ` with `dⱼ ⇒ (bit j of o ≠ bit j of o')`, as two clauses. A free bit against a constant needs no `dⱼ`: use the literal saying the free bit differs from the constant;
- `¬act(o) ∨ ¬act(o') ∨ d₁ ∨ … ∨ d_w ∨ sm`: two active objects with equal labels force `sm`;
- `sm ⇒ L(childᵢ of o) = L(childᵢ of o')` for each child.

The direction of the `dⱼ` definition matters. With the opposite implication the solver can set `dⱼ` freely and the family constrains nothing; the prototype had this bug at first.

Different symbols need no clauses: their constant `sym` bits already differ.

### 6.6 Links

A child sees its parent's variables, and a use of a local hypothesis sees the variables of the node that introduced it.

- **Parent link.** For α < β, clause `c`, premise `k`, and each `b` in the clause frame of `c`: `cl(α, c) ∧ y(α, β, k) ⇒ L(β, goal, b) = L(α, clause, b)`.
- **Introducer link.** For γ ≤ β, local clause `c`, and each `b` in `Env(c)`: `u(β, γ) ∧ cl(β, c) ⇒ L(β, clause, b) = L(γ, goal, b)`. The case γ = β is included.

### 6.7 Eigenvariables, occurs check and scope

- **Eigenvariables.** For `b` in `eig(g)`: `gp(α, g) ⇒ L(α, goal, b) =` the constant label of section 5.3.
- **Occurs check.** For each rigid object `o` and each child: `act(o) ⇒ rank(child) < rank(o)`.
- **Escape sets.** For each rigid object `o`, each child and each node γ: `act(o) ∧ esc(child, γ) ⇒ esc(o, γ)`.
- **Scope.** For each clause variable `b` of `c`, with `s` the clause slot `(α, clause, b)`: `cl(α, c) ⇒ ¬esc(s, γ)` for γ > α, and `cl(α, c) ∧ esc(s, γ) ⇒ anc(γ, α)` for γ < α.

Less-than on bit vectors `X < Y`, most significant bit first, uses a chain `t₀ … t_w` with `t_w` false. Assert `t₀` under the condition, and for each bit `i` add `tᵢ ∧ xᵢ ⇒ yᵢ`, `tᵢ ∧ xᵢ ⇒ tᵢ₊₁` and `tᵢ ∧ ¬yᵢ ⇒ tᵢ₊₁`.

### 6.8 Groundness and typing

Every clause variable in use must have a concrete value of the right type. A **candidate** is any non-open rigid object of any node, any ground object, or any eigenvariable goal slot of any node, of the same kind as the variable.

For each node α, clause `c`, clause variable `b` with slot `s`, and candidate `o`, introduce `sv`:

- `cl(α, c) ⇒` some `sv` over the candidates;
- `sv ⇒ act(o)`, and `sv ⇒ L(s) = L(o)`;
- **typing:** `sv ⇒ L(type of b at α) = L(type of o)`.

When both types are closed, the typing clause is decided statically: keep the candidate if the types are identical, drop it otherwise. Level variables have level candidates only and no typing clause. Objects that exist only as type templates are never candidates, which keeps the construction finite.

Typing is needed because the solver may give an otherwise unconstrained variable the value of any candidate. Values forced by matching are already well typed, so the clause never removes a real proof. Type templates are instantiated per node and labelled like any other template. The typing clause is specified here but was not prototyped.

### 6.9 Built arguments (milestone 5)

A clause variable whose type is not a function type may instead be built by a child node. This was not prototyped.

- Each such variable `b` of `c` gets a **data position**: a goal position with no binders whose target is the type template of `b`. It adds an optional child index to `c`: at most one child, none required.
- A **data clause** is a constant in `H`, or an eigenvariable, whose result type is not a proposition. Its head is its result type, and it carries a value template: the constant applied to its clause variables.
- At a node β on a data position with data clause `c'`: the label of the target type equals the label of the head type, and `L(β, goal, b) = L(value of c' at β)`.
- Proof clauses apply only at proposition positions and data clauses only at data positions. This is a static filter. The value object of a data clause is a per-node rigid object, active only when that node applies the clause, even if the value is a closed term. Otherwise a listed data constant could be used without spending a node.

### 6.10 Optional refinements (milestone 6)

- **Symmetry breaking.** Require breadth-first numbering: if `y(α, β, k)` and `y(α', β+1, k')` then `(α, k)` precedes `(α', k')` lexicographically.
- **Pair pruning.** Skip a decomposition pair when its two templates do not unify with all variables renamed apart.
- **Candidate pruning.** Skip a grounding candidate whose type cannot unify with the variable's type.
- **Frame pruning.** Link only the variables that actually occur in the premise or clause, instead of the whole frame.

### 6.11 Why the encoding is exact

- A set of first-order equations has a unifier exactly when the terms can be labelled so that equated terms share a label, same-label rigid terms have the same symbol and pairwise same-label children, and every rigid term ranks above its children. Families 6.4 to 6.7 state precisely this for the equations of the chosen tree.
- From a real proof, label every object by its fully instantiated value. This satisfies every family, which gives completeness.
- From a model, equal labels define the substitution. Groundness guarantees each variable has a rigid member in its class, and the rank order makes the values finite, which gives soundness.
- The kernel check in section 8 is a backstop, not part of the argument. If it ever fails on a satisfiable CNF, that is a bug.

## 7. Clause counts

The number of clauses grows as N³ in the node bound and quadratically in the total size of the hypothesis list. Two families dominate: groundness (6.8) and decomposition (6.5).

### 7.1 Parameters

| Symbol | Meaning | Bound in terms of `H` |
| --- | --- | --- |
| `N` | node bound | given |
| `h`, `s` | number of hypotheses in `H`; largest statement size in expression nodes, goal included | given |
| `C`, `G` | clauses and goal positions in the forest | each at most (h + 1)·s |
| `A`, `a` | most premises of a clause; largest symbol arity | at most s |
| `M`, `E` | clause variables and eigenvariable binders, in total | each at most (h + 1)·s |
| `F` | largest frame | at most (h + 1)·s; usually far smaller |
| `T` | non-ground template positions | at most (h + 1)·s |
| `P` | sum over symbols `f` of (positions with symbol `f`)² | at most T² |
| `W` | label width: N + log₂ of symbols, of N·T, and of N·d | about N + 2·log₂(N·T) |

### 7.2 Count per family

These are leading terms for the unpruned encoding with pairwise at-most-one, which is what the prototype builds.

| Family | Clauses | Grows as |
| --- | --- | --- |
| 6.1 Node assignment | N·(C² + G²)/2 | N · h² |
| 6.2 Tree shape | N³·A²/6 + N²·C·A/2 | N³ + N² · h |
| 6.3 Context | N³·A/6 + N²·C/2 | N³ + N² · h |
| 6.4 Matching | at most 2·N·G·C·a·W | N · W · h² |
| 6.5 Decomposition | N²·P·(a + 1)·W | N² · W · h² |
| 6.6 Links | at most 2·N²·C·A·F·W | N² · W · h |
| 6.7 Eigenvariables, occurs, scope | N·E·W + N·T·a·(N + 3·rank bits) + N²·M | N² · h |
| 6.8 Groundness | 2·N²·M·(T + E)·W, doubled where typing is not static | N² · W · h² |

Adding these up gives the total below. Since `W` is about `N` once `N` exceeds the logarithmic terms, the total is cubic in `N` for a fixed `H`, and quadratic in h·s for a fixed `N`.

```latex
\#\text{clauses} \;=\; \Theta\!\Big( N^{2}\, W \,\big( M\,(T+E) \;+\; P\,a \;+\; C\,A\,F \big) \Big) \;=\; O\!\Big( N^{2}\,\big(N + \log(N h s)\big)\; h^{2} s^{2}\, a \Big)
```

The ladder at-most-one encoding removes the N³·A² term of 6.2 and the squares in 6.1. The pruning rules of 6.10 cut the constants of 6.5, 6.6 and 6.8; their effect has not been measured.

### 7.3 Measured sizes

The prototype was run on the goal `x ≤ w` from `x ≤ y`, `y ≤ z`, `z ≤ w`, with transitivity and then 4 or 8 extra monotonicity lemmas of the shape `m ≤ n → s m ≤ s n`. Each cell is variables / clauses.

| Lemmas in `H` | N = 5 | N = 8 | N = 12 |
| --- | --- | --- | --- |
| 1 | 1,505 / 22,270 | 3,192 / 65,408 | 6,300 / 174,848 |
| 5 | 20,225 / 204,970 | 60,296 / 648,800 | 155,748 / 1,744,688 |
| 9 | 72,675 / 653,530 | 223,992 / 2,066,208 | 571,956 / 5,354,456 |

The measurements match the formula. From N = 5 to N = 12 with 9 lemmas the formula predicts a factor of 8.5 and the count grew 8.2 times. From 5 to 9 lemmas at N = 8 it predicts 3.4 and the count grew 3.2 times.

At 9 lemmas and N = 12, groundness is 57% of the clauses and decomposition 37%. Matching and links are 3% each, and everything else is under 1%.

These instances are easy for a solver. With the minimal CDCL solver written for the prototype, the 648,800-clause instance took 1.6 seconds including encoding, and every test in section 9 took under 0.3 seconds. Harder instances were not benchmarked, so no practical limit on `N` is claimed here.

## 8. Decoding: from a model to a checked proof

The decoder reads the proof tree from the structural variables and replays it in `MetaM`, then the kernel checks the result. Replay recomputes argument values with Lean's unifier instead of reading them from labels, because templates erase proof subterms and cannot always be turned back into expressions.

1. **Read the skeleton.** For each used node, read its clause from `cl`, its goal position from `gp`, its children from `y`, and for a local clause its introducing node from `u`.
2. **Replay a node.** Starting from a metavariable for the goal:
   - introduce the binders of the goal position, and record the new free variables against this node;
   - build the head term of the clause: the constant with fresh level metavariables, the recorded free variable of the introducing node, a projection wrapper from section 4.2, or the built-in constructor;
   - create metavariables for its arguments, and unify its conclusion with the current target using `isDefEq` under reducible transparency;
   - replay each child on the metavariable of its premise, and each data child on the metavariable of its argument.
3. **Finish.** Instantiate metavariables, fail if any remains, type-check the term, and close the user's goal with it so the kernel checks it.
4. **Treat failure as a bug.** If the CNF is satisfiable and any step of 2 or 3 fails, raise an error that prints the skeleton. Never fall back silently and never report the goal as unprovable.

If the CNF is unsatisfiable, the tactic fails with the message that no proof with at most `N` nodes exists in the class.

For debugging, a second decoder may read each slot's value by following equal labels to a rigid object, and compare it with the value Lean assigned.

## 9. Milestones and acceptance tests

Build in the order below; each milestone is done only when its acceptance tests pass and all earlier tests still pass.

| # | Milestone | Deliverable | Acceptance |
| --- | --- | --- | --- |
| 0 | SAT plumbing | Lake project, `CNF.lean`, `Solver.lean` | pigeonhole 7 into 6 is unsatisfiable; 300 random small CNFs agree with brute force |
| 1 | Forest encoder | `Term`, `Forest`, `Encode`, `Reference`: a port of the prototype | forest tests T1 to T9 give the exact minimal `N`; differential test passes; mutation checks fire |
| 2 | Lean front and back end for `∀`, `→`, atoms | `Compile`, `Decode`, `Tactic` | L1 to L4 succeed; F4 fails as expected |
| 3 | Connectives | built-in clauses and head splitting (4.2) | L5 to L8 succeed; F1 fails as expected |
| 4 | Typing, levels, binders in terms | typing clause of 6.8, level variables, the `open` bit | polymorphic `Eq.refl` works; an ill-typed grounding is rejected; F2 and F3 fail as expected |
| 5 | Built arguments | 6.9 | `∃ n : Nat, n ≤ n` with `[Nat.le_refl, Nat.zero]` in 3 nodes |
| 6 | Refinements | 6.10 and ladder at-most-one | identical answers on every earlier test; clause counts reported before and after |

### 9.1 Forest tests (milestone 1)

These are the tests in the prototype's `tests.py`. "None" means unsatisfiable for every `N` up to 6.

| Test | What it checks | Minimal N |
| --- | --- | --- |
| T1 | one lemma used twice with different instantiations | 5 |
| T2, T2b | a hypothesis used outside the branch that introduced it; the same with the fact available globally | none; 4 |
| T3, T3b | an eigenvariable escaping its scope; the legal variant | none; 2 |
| T4, T4b | an argument that nothing determines; the same with a constant available | none; 2 |
| T5 | occurs check | none |
| T6, T6b | constraints that are pairwise consistent but jointly inconsistent; the consistent variant | none; 4 |
| T7 | a local hypothesis that mentions an ancestor's clause variable | 3 |
| T8 | a local hypothesis applied inside its own premise | 3 |
| T9 | two live instances of one local hypothesis, with the outer one needed inside the inner scope | 6 |

**Differential test.** Generate random forests and compare the encoder against `Reference` for every `N` up to 5, with groundness switched off on both sides. Require at least 5,000 comparisons, at least 100 forests whose smallest proof has 2 or more nodes, and zero mismatches.

**Mutation checks.** Disabling the scope clauses of 6.7 must produce at least one mismatch, and so must disabling the occurs check. This shows the differential test can detect those errors.

### 9.2 Lean tests (milestones 2 and 3)

```lean
-- L1: chain of lemmas, exactly 5 nodes
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)
-- L2: implications, 3 nodes
example (A B C : Prop) : (A → B) → (B → C) → A → C := by
  solve_by_sat [] (nodes := 3)
-- L3: quantified hypothesis, 2 nodes
example (P Q : Nat → Prop) (a : Nat) (h : ∀ y, P y → Q y) (hp : P a) : Q a := by
  solve_by_sat [] (nodes := 2)
-- L4: reflexivity, 1 node
example (n : Nat) : n ≤ n := by
  solve_by_sat [Nat.le_refl] (nodes := 1)
-- L5: conjunction, 3 nodes
example (A B : Prop) (ha : A) (hb : B) : A ∧ B := by
  solve_by_sat [] (nodes := 3)
-- L6: disjunction, 2 nodes
example (A B : Prop) (hb : B) : A ∨ B := by
  solve_by_sat [] (nodes := 2)
-- L7: existential with a forced witness, 2 nodes
example (a b : Nat) (h : a ≤ b) : ∃ x, x ≤ b := by
  solve_by_sat [] (nodes := 2)
-- L8: conjunctive hypothesis through a projection, 1 node
example (A B : Prop) (h : A ∧ B) : B := by
  solve_by_sat [] (nodes := 1)

-- Each of the following must fail with "no proof with at most N nodes".
-- F1: hypothesis out of scope
example (A : Prop) : (A → A) ∧ A := by
  fail_if_success solve_by_sat [] (nodes := 6)
  sorry
-- F2: eigenvariable escape
example : ∃ x : Nat, ∀ y : Nat, x = y := by
  fail_if_success solve_by_sat [Eq.refl] (nodes := 6)
  sorry
-- F3: needs computation, a documented limitation
example : 2 + 2 = 4 := by
  fail_if_success solve_by_sat [Eq.refl] (nodes := 6)
  sorry
-- F4: one node short of L1
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  fail_if_success solve_by_sat [Nat.le_trans] (nodes := 4)
  sorry
```

F1 needs milestone 3 and F2 and F3 need milestone 4; until then, test their forest equivalents T2 and T3. The node counts in L1 to L8 are minimal, so each example must also fail with one node fewer.

### 9.3 What has and has not been validated

- **Validated on the prototype:** families 6.1 to 6.7 and the untyped part of 6.8. All 13 forest tests pass. The differential test ran 7,500 comparisons with zero mismatches; 2,461 were provable instances, and 157 forests had a smallest proof of 2 to 5 nodes. Both mutation checks fired.
- **Not validated:** the typing clause of 6.8, connectives, universe levels, the `open` bit, data nodes, the refinements of 6.10, and every Lean-side step. No Lean toolchain was available where this spec was written, so Lean API names and constant signatures must be checked against the installed version.

## 10. What changed from the original draft

The idea of the draft survives: a bounded proof tree whose nodes apply hypotheses, with SAT variables for the assignment and the tree shape. The changes below fix the points where the draft was unsound or incomplete, or narrow the scope so a single CNF is possible.

| Original draft | Revised | Reason |
| --- | --- | --- |
| `x(α, h)`: node α is assigned hypothesis `h` | `cl(α, c)` plus `gp(α, g)` | the goal a node solves is now explicit, so matching can be stated per node |
| `y(α, β, k)` | unchanged |  |
| `z(α, h)`: `h` is in the context of α | `u(β, γ)` and `anc(γ, β)` | the draft's clauses only forced `z` true, so any hypothesis could be used anywhere; a use now names the node that introduced the hypothesis |
| Static lists of potential hypotheses and goals | the clause forest of section 4 | still static, but only because the fragment excludes goals whose shape depends on an instantiation |
| One set of metavariables per hypothesis | fresh slots per node, in two frames | a lemma can be used several times with different instantiations |
| Tables `U`, `L` and the pairwise matrix `M` | labels inside the CNF (5.3, 6.4 to 6.7) | pairwise checks miss joint inconsistency, the occurs check and scope |
| Non-propositional goals read from `E` | the groundness rule (6.8) and built arguments (6.9) | no argument may stay undetermined, and values must be well typed |
| `N` leaves; a child for every parameter | `N` nodes; a child only for premises and built arguments | inferred arguments are not nodes |
| Rewrite, Cases, Induction | out of scope | they need a motive, which is higher-order |
| Use | supported when the witness is determined or built |  |
| No statement of correctness | the contract of section 1 and the tests of section 9 |  |
