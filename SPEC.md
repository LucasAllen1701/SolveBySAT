# Solve By SAT: revised specification

Lucas Allen · 18 November 2026; revised 24 November 2026 and 27 November 2026

**Status: implemented and evaluated.** Milestones 0 to 6 are complete on Lean 4.36.0, and milestone 7 evaluated the tactic on 6,300 real Lean goals. Milestone 8 added two exact reductions of the CNF, node–clause bounds with an early exit and exclusive pairs, now on by default (6.10.1 and 6.10.2). This revision describes the system as built. It folds in every amendment and deviation from the implementation's NOTES.md:

- milestone 7's three fixes (sections 4.5 and 8) and its encoder addition `countOnly` (section 3);
- milestone 8's reductions, options and measurements (sections 3, 5.3, 6.10, 7.5).

It summarises both evaluations (sections 7.4, 7.5, 9.5 and 9.6). Section 11 lists the changes. The evaluations are in the repository: `EVAL.md` and `EVAL_PLAN.md` for milestone 7, and `M8_PLAN.md` with the reports under `eval/m8a/` to `eval/m8d/` for milestone 8.

## 1. Overview and contract

`solve_by_sat` takes a goal `G`, a list `H` of constants and a bound `N`, and builds one CNF formula. The formula is satisfiable exactly when `G` has a proof of at most `N` nodes in the proof class of section 2. A satisfying assignment is decoded into a Lean term, which the kernel then checks.

```lean
example (x y z w : Nat) (h1 : x ≤ y) (h2 : y ≤ z) (h3 : z ≤ w) : x ≤ w := by
  solve_by_sat [Nat.le_trans] (nodes := 5)
```

The implementation meets three properties, each checked by the tests in section 9.

1. **Soundness.** If the CNF is satisfiable, decoding returns a term `t` and the kernel accepts `t : G`.
2. **Completeness.** If a proof in the class with at most `N` nodes exists, the CNF is satisfiable.
3. **One shot.** The CNF is built once, before the solver runs. Nothing is fed back from Lean to the solver, and the CNF size is polynomial in `N` and the size of `H` (section 7).

A **node** is one application of a clause, together with the `intro` steps that precede it. The clause is a hypothesis, a local hypothesis, a built-in connective rule, or a data constant that builds an argument. Arguments that unification infers, or that equal a term already in the proof, cost no nodes, like `_` in Lean.

The method is backward chaining: introduce the binders of the goal, apply a clause whose conclusion matches, and repeat on its premises. The SAT solver chooses the clause at each node and the tree shape. Unification is encoded in the CNF as labels on terms (sections 5.3 and 6.4 to 6.7).

## 2. Scope

The reduction covers backward-chaining proofs over first-order hereditary Harrop formulas, with syntactic unification on preprocessed terms. In tactic terms it mimics `intro`, `apply` and `exact`; `constructor` on `∧ ∨ ↔ True`; `exists` when the witness is forced or built from listed data constants; and projections of `∧` and `↔` hypotheses. It does not mimic `rw`, `cases` or `induction`.

### 2.1 Supported statements

The shapes below are read off a Lean type after the preprocessing of section 4.1.

- A **goal formula** is `∀ b₁ … bₘ, R`. A non-Prop binder is an **eigenvariable**. A Prop binder is a **local hypothesis**. The target `R` is an atom, or one of `A ∧ B`, `A ∨ B`, `∃ x, A`, `A ↔ B`, `True` with `A`, `B` goal formulas.
- A **clause formula** is `∀ a₁ … aₖ, R`. A non-Prop binder is a **clause variable**, fresh at each use. A Prop binder is a **premise**, and its type must be a goal formula. The head `R` is an atom; `A ∧ B` or `A ↔ B`, which are also split into projections; or `A ∨ B`, `∃ x, A`, `True`.
- An **atom** is an application whose head is a constant or an eigenvariable. Its arguments are Lean terms in which clause variables occur only unapplied.
- **Opaque atoms.** Every target and every head, connective or not, can also be matched as a whole proposition. So `h : A ∨ B` proves the goal `A ∨ B`, though it can never be split into cases.
- A **data clause** is a constant in `H` whose type is not a proposition and whose result type is not a Sort, such as `Nat.zero`, `Nat.succ` or `Int.ofNat`. An eigenvariable with a function type whose result is neither a proposition nor a Sort, such as `f : Nat → Int`, is a data clause local to its binder. A plain eigenvariable such as `k : Nat` is not a data clause: it is a grounding candidate instead, which costs no node.

A constant listed in `H` that fits none of these shapes is rejected with a message giving the reason. A hypothesis in the local context that does not fit is introduced but ignored, and `solve_by_sat.verbose` reports why. For a hypothesis with an `∧` or `↔` head, each split path is judged separately.

| Statement | Status | Reason |
| --- | --- | --- |
| `Nat.le_trans`, `Nat.succ_le_succ` | accepted | atoms with rigid heads; clause variables only as arguments |
| a premise `∀ y, P x y → Q y` | accepted | nested `intro` |
| `Eq.refl` and other universe-polymorphic lemmas | accepted | universe parameters become level variables |
| `Nat.zero`, `Nat.succ` | accepted as data clauses | non-Prop constants whose result is not a Sort |
| `And.intro`, `Or.inl`, `Or.inr`, `Exists.intro`, `Iff.intro`, `True.intro` | built in, not listed in `H` | specialised per goal |
| `h : A ∨ B` or `h : ∃ x, P x` in the context | used only as opaque facts | no elimination rules |
| `Nat` | rejected | a type former: neither a proof nor a data constant |
| `Or.elim`, `False.elim`, `absurd`, `Classical.em` | rejected | the head is a bare proposition variable |
| `congrArg` | rejected | the clause variable `f` is applied to arguments |
| `Nat.rec`, `Eq.subst`, `Eq.mpr` | rejected | they need a motive |
| a target `∃ h : P, Q` with `P` a proposition | rejected | the witness would be a proof |

### 2.2 The proof class

A proof in the class is a tree. Each node solves one instance of a goal formula or of a data position in three steps.

1. Introduce every binder of the goal formula.
2. Apply one clause to the target: a built-in introduction rule, a clause from `H`, or a local hypothesis in scope, whose head equals the target after substituting terms for its clause variables. At a data position, the clause is a data clause whose result type and value match the variable being built.
3. Prove each premise in a child node. Optionally, build an eligible clause variable in a data child (section 4.3).

Four conditions make a tree a proof.

- **Syntactic equality.** Head and target must be the same term after preprocessing (section 4.1): bound variables are compared by position, proof subterms are ignored, and universe levels are normalised. No further unfolding or computation is used.
- **Determined arguments.** Each clause variable must equal a term that occurs in an instantiated statement or built value of the proof, or an eigenvariable in scope. Its value never contains a loose bound variable.
- **Typing.** A value's type template must equal the variable's type template, syntactically.
- **Scope.** A value may mention an eigenvariable only if it was introduced at the node that created the variable, or at an ancestor. The same holds for using a local hypothesis or a local data clause.

The size of a proof is its number of nodes.

### 2.3 What it can prove

| Kind | Example | Nodes |
| --- | --- | --- |
| Chains of lemmas | `x ≤ w` from `x ≤ y`, `y ≤ z`, `z ≤ w` and `Nat.le_trans` | 5 |
| Implications | `(A → B) → (B → C) → A → C` | 3 |
| Quantified hypotheses | `Q a` from `∀ y, P y → Q y` and `P a` | 2 |
| Reflexivity | `n ≤ n` with `Nat.le_refl`; `n = n` with `Eq.refl` | 1 |
| Connectives in goals | `A ∧ B` from `A` and `B`; `A ∨ B` from `B` | 3; 2 |
| Existentials, witness forced | `∃ x, x ≤ b` from `a ≤ b`; `∃ n : Nat, n = 1` with `Eq.refl` | 2 |
| Projections of hypotheses | `B` from `h : A ∧ B` | 1 |
| Hypotheses as opaque facts | `A ∨ B` from `h : A ∨ B` | 1 |
| Quantifier order | `∀ y, ∃ x, R x y` from `∀ n, R n n` | 2 |
| Built witnesses | `∃ n : Nat, n ≤ n` with `[Nat.le_refl, Nat.zero]` | 3 |
| Built argument of a hypothesis | `∃ n, Q n` from `∀ m, Q (Nat.succ m)` with `[Nat.zero]` | 3 |
| Built by a local function | `∀ f : Nat → Int, ∃ i : Int, True` with `[Nat.zero]`, building `f Nat.zero` | 4 |
| Universe levels in a different order | `f = f` for `f : Sort (max v u) → Sort u`, from a lemma stated with `max u v` | 1 |

### 2.4 What stays out of reach

| Category | Example | Why |
| --- | --- | --- |
| Rewrite, cases, induction | `Nat.rec`, `Eq.mpr`, splitting `h : A ∨ B`, destructuring `h : ∃ x, P x` | need a motive, or elimination into an arbitrary goal |
| Ex falso and classical logic | `False.elim`, `absurd`, `Classical.em`, proof by contradiction | the conclusion is a bare proposition variable |
| Unfolding and computation | `2 + 2 = 4`; `n + 1` against `Nat.succ n`; `a ⊆ b` | only `Not`, `Ne`, `GE.ge` and `GT.gt` are unfolded |
| Numerals against constructors | `∃ n, Nat.succ n = 1`, though `⟨0, rfl⟩` proves it | `1` is `OfNat.ofNat Nat 1 _`, and there is no literal arithmetic |
| Higher-order unification | `congrArg`, function witnesses that are then applied | needs β-reduction inside unification |
| Building some witnesses | a witness whose type is a Sort, a function type, or a clause variable | no data position is created for such variables |
| Level equalities up to commutativity | `max ?a ?b` against `max u v` when the two statements sort their parameter names differently | levels are normalised per statement, then matched syntactically |
| Definitional typing | a value whose type is definitionally but not syntactically the variable's type | typing compares templates syntactically |
| Type class resolution | an instance argument that is not syntactically the expected one | instances are found only by unification |
| Proof-dependent types | a binder whose type mentions an earlier proof variable | rejected at compile time |
| Lemma reuse | a sub-proof needed twice | proofs are trees, so it is counted twice; there is no `have` |
| Large problems | 9 lemmas at 12 nodes is 4.2 million clauses; on real goals, 21.6% exceeded 2.5 GB at N ≤ 10 before milestone 8, and an estimated 13% still do | groundness and decomposition grow quadratically in `H` (sections 7.3 to 7.5) |

## 3. Architecture

The implementation is a four-stage pipeline in which only the first and last stages use Lean's metaprogramming API. The middle two work on plain data and are tested without Lean expressions.

1. **Compile** (`MetaM`). Turn the goal and each constant in `H` into a clause forest: clauses, goal positions, data positions and term templates (section 4).
2. **Encode** (pure). Turn the forest and `N` into a CNF (sections 5 and 6).
3. **Solve** (`IO`). Write DIMACS, run a SAT solver, read and verify the model.
4. **Decode** (`MetaM`). Replay the proof tree, finish the term from the model, and have the kernel check it (section 8).

| Module | Content | Uses Lean `Meta` |
| --- | --- | --- |
| `SolveBySat/Term.lean` | first-order term templates, symbols, `unifiableApart` | no |
| `SolveBySat/Forest.lean` | clauses, goal and data positions, frames, `varsBelow`, well-formedness | no |
| `SolveBySat/Compile.lean` | preprocessing, `Expr` to forest in two passes, rejection messages | yes |
| `SolveBySat/CNF.lean` | variables, clause builder with constant folding, bit-vector `eq` and `lt`, pairwise and ladder at-most-one, DIMACS | no |
| `SolveBySat/Encode.lean` | the clause families of section 6, `EncodeOptions`, and `readSkeleton`/`renderSkeleton` | no |
| `SolveBySat/Solver.lean` | finding and running the solver, parsing and checking the model | no |
| `SolveBySat/Decode.lean` | replay, grounding from the model, kernel check | yes |
| `SolveBySat/Tactic.lean` | `solve_by_sat [h₁, …] (nodes := N)` and its options | yes |
| `SolveBySat/Reference.lean` | brute-force prover over forests with binders, data and groundness; the test oracle | no |
| `Test/` | fixed tests, differential tests, Lean examples, scripts | mixed |
| `Test/Eval*.lean`, `Test/eval_*.py`, `eval/` | the milestone 7 evaluation: corpus extraction, coverage harness and driver, scaling runs, and `eval/report.py`, which writes `EVAL.md` | mixed |
| `Test/M8Diag.lean`, `Test/m8*_run.py`, `eval/m8a/` to `eval/m8d/` | milestone 8: the rewriting probe, the CNF diagnostics (an exact recount of every family in a counting CNF), and the stage reports | mixed |

**Solver.** Lean 4.36.0 ships CaDiCaL 2.1.2 in the toolchain's `bin/`. `Solver.findSolver` tries, in order: the environment variable `SOLVE_BY_SAT_SOLVER`, `IO.appPath.parent/cadical`, `Lean.findSysroot/bin/cadical`, and `cadical` on `PATH`. Every model returned is checked against the CNF, so a faulty solver cannot produce a false proof.

**Options.**

| Option | Default | Effect |
| --- | --- | --- |
| `(nodes := N)` | 8 | node bound; `nodes := 0` fails at once with the no-proof message |
| `solve_by_sat.verbose` | false | reports CNF size, the skeleton found, and context hypotheses that were ignored |
| `solve_by_sat.refinements` | true | `false` switches off all seven refinements of 6.10 |
| `solve_by_sat.nodeBounds` | true | node–clause bounds and the early exit (6.10.1) |
| `solve_by_sat.exclusivePairs` | true | no decomposition between objects that are never active together (6.10.2) |
| `solve_by_sat.staticTyping`, `typingClause`, `forgetTypes` | true, true, false | testing only: switch off the static typing filter or the typing clause, or treat every type as unknown |
| `solve_by_sat.checkTemplates` | false | testing only: fail with an internal error if a type template is changed by preprocessing (section 4.5) |
| `solve_by_sat.checkBounds` | false | testing only: check every node of a decoded proof against the bounds of 6.10.1 |

`EncodeOptions` has one flag per refinement (`symmetry`, `pairPruning`, `candidatePruning`, `framePruning`, `ladderAmo`, `nodeBounds`, `exclusivePairs`), plus `protoRank` (the prototype's rank width). For mutation tests only, it also has `openBit`, `dataFilter`, `boundsScope` (on), `boundsTight` and `exclusiveMutant` (off).

`EncodeOptions.countOnly` (default false) counts variables and clauses, per family, without storing any clause. The clause builder does all its constant folding and counting as before and only skips storing the clause, so the counts equal a full encode's; a test checks this on every instance of section 7.3. It is used to measure CNFs too large to build in memory (section 7.4).

**Dependencies.** Lean core and `Std` only, no Mathlib.

**Reference prototype.** The Python prototype (`enc.py`, `tests.py`, `diff.py`, `cdcl.c`) is now historical. The Lean implementation is authoritative. With all refinements off and `protoRank` on, the encoder still reproduces the prototype's CNF sizes exactly on tests T1 to T9.

**Environment.** The development machine has about 3.8 GB of memory and no swap. Lake builds occasionally fail with "not enough memory" when spawning `lean`. The cause is the kernel's heuristic overcommit refusing `lake`'s fork, and `vm.overcommit_memory = 1` fixes it. The differential tests use 4 worker threads, because 8 exhausted memory. The evaluation ran on a second machine (Intel i7-10510U, 7.6 GB), one process at a time under a 2.5 GB cgroup cap.

## 4. Compilation: from Lean to a clause forest

Compilation produces a finite, static structure called the **clause forest**. It is finite because every clause, goal position and data position is a subformula of the goal or of a statement in `H`.

### 4.1 Preprocessing

The tactic first reverts the whole local context, so the goal is closed. Each type is then normalised by exactly these steps:

- instantiate metavariables, strip metadata, β-reduce, and inline `let`;
- unfold `Not`, `Ne`, `GE.ge` and `GT.gt` by instantiating their definitions;
- normalise every universe level with `Level.normalize`, which sorts the arguments of `max` by parameter name, removes subsumed terms and pushes `succ` inside `max`.

There is no `whnf` and no other unfolding. The decoder applies the same preprocessing to the type of each constant it uses, with the constant's own parameter names, before instantiating its universe parameters. Otherwise the order of `max` arguments could depend on metavariable numbering.

### 4.2 Goal positions and clauses

| Object | Fields |
| --- | --- |
| Goal position `g` | `eig(g)`: its non-Prop binders. `loc(g)`: the clauses made from its Prop binders, its data-clause eigenvariables and its built-in rules. `tgt(g)`: its target atom. Its owner: the root, premise `k` of a clause, or data position `b` of a clause. |
| Clause `c` | `vars(c)`: its non-Prop binders, plus one level variable per universe parameter of a constant. `prem(c)`: one goal position per Prop binder. `data(c)`: one data position per eligible clause variable (4.3). `head(c)`: its head atom. Its origin: a constant in `H`, a local hypothesis, a local data eigenvariable, or a built-in rule. |

The forest is built by recursion: the goal gives the root goal position, each constant in `H` gives one or more global clauses, each premise and data position gives a goal position, and each Prop binder of a goal position gives local clauses.

**Opaque atoms.** Every target and every head is first an atom in its own right, whatever its connective. A target `A ∨ B` can therefore be closed by its built-in rule or by any clause whose head is syntactically `A ∨ B`.

**Connectives in targets** add built-in clauses. They are local to the goal position that owns the target, their head is that target's opaque atom, and they can only be applied at that node (`cl(β, c) ⇒ u(β, β)`, section 6.3).

| Target of `g` | Built-in clauses | Clause variables | Premises | Proof term |
| --- | --- | --- | --- | --- |
| `A ∧ B` | one | none | `A`, `B` | `And.intro` |
| `A ∨ B` | two | none | `A`; or `B` | `Or.inl`; `Or.inr` |
| `∃ x : τ, A` | one | `w : τ` | `A` with `x := w` | `Exists.intro w` |
| `A ↔ B` | one | none | `A → B`, `B → A` | `Iff.intro` |
| `True` | one | none | none | `True.intro` |

An `∃` whose body is not a literal `fun` is η-expanded, so `∃ p` gives premise `p w`. An `∃` over a proposition is rejected.

**Connectives in heads** are split, and the whole head is kept as well. A clause with head `A ∧ B` gives the opaque clause plus clauses with heads `A` (`And.left`) and `B` (`And.right`). A head `A ↔ B` gives the opaque clause plus one with head `B` and extra premise `A` (`Iff.mp`), and one with head `A` and extra premise `B` (`Iff.mpr`). Splitting repeats on the components. Each split path is its own clause, with fresh binder names and its own copies of the premise goal positions. It records a recipe of projection steps for the decoder. A component that is itself a `∀` adds binders.

**Context hypotheses that are not clauses** are introduced but give no clause, per split path. For `h : A ∧ (∀ f : Nat → Nat, f 0 = 0)`, the opaque clause and `h.left` are kept and `h.right` is dropped. Constants listed in `H` are rejected instead.

### 4.3 Data clauses and data positions

Compilation runs in two passes. Pass 1 finds the data clauses. Only if there is at least one does pass 2 add data positions, so a problem without data clauses compiles exactly as it would without this feature.

- **Data clauses.** A constant of `H` whose type is not a proposition and whose result type is not a Sort. Also, an eigenvariable whose type is a function type with a result that is neither a proposition nor a Sort, such as `f : Nat → Int`; it is local to the goal position that binds it. Non-Prop binders are clause variables, Prop binders are premises, and the head is the result type. The **value template** is the constant (with its level variables) or the eigenvariable, applied to all its binders.
- **Data positions.** A clause variable gets one only if its type is not a proposition, not a syntactic `∀` and not a Sort; its type compiles as an atom with a constant head; and that head symbol is the head symbol of some data clause. The data position is a goal position with no binders whose target is the variable's type template.
- **Plain eigenvariables** such as `k : Nat` are not data clauses. They are already grounding candidates (6.8), so a data node for one would only cost a node.

### 4.4 Static variables and frames

Every non-Prop binder in the forest is a **static variable** with a globally unique name. Each has a kind (`term` or `level`) and, for kind `term`, a type template. Level variables are fresh for every clause made from a constant, one set per split path. Universe parameters of the goal stay constants.

The variables visible at a position are defined by `Env`:

- `Env(root) = ∅`, and `Env(c) = ∅` for a global clause;
- `Env(c) = Env(g) ∪ eig(g)` for a clause `c` local to `g`, including built-in clauses and local data clauses;
- `Env(g) = Env(c) ∪ vars(c)` for a premise or data position `g` of `c`.

The **goal frame** of `g` is `Env(g) ∪ eig(g)`; `tgt(g)` is a template over it. The **clause frame** of `c` is `Env(c) ∪ vars(c)`; `head(c)` and the value template are templates over it.

### 4.5 Term templates

An atom is a predicate symbol with argument templates. A template is a tree whose leaves are static variables or constants.

| Lean expression | Template |
| --- | --- |
| a static variable, unapplied | variable leaf |
| an eigenvariable applied to `k ≥ 1` arguments | symbol `app` over the variable and its arguments |
| a clause variable applied to arguments | compile error: not first order |
| `c.{l₁…lₘ} a₁ … aₖ` | symbol `c:<name>` over the levels, then the arguments; its key is `(name, m + k)` |
| `fun x : τ => b`, or `∀ x : τ, b` inside a term | symbol `lam` or `pi` over `τ` and `b`, with de Bruijn leaves `bvar:i` for bound variables |
| literals, projections, `Sort l` | `lit:<value>`; `proj:<S>:<i>` over the structure; `sort` over `l` |
| universe levels | symbols `zero`, `succ`, `max`, `imax`; a parameter of the goal is a constant, a parameter of a constant in `H` is a level variable |
| a subterm that is a proof | the single constant `⟨proof⟩` |

The eigenvariable symbol has no name, so it cannot collide with a user constant. An atom whose head is an eigenvariable, such as a proposition variable `A`, uses the predicate symbol `app`.

For each template node, compilation records:

- whether it is **ground** (no static variables), and for a ground term a **representative** Lean expression when it has a closed one;
- whether it is **open** (it contains a loose `bvar`);
- for term-kind static variables, non-ground positions and ground terms, a **type template** from `inferType`, preprocessed as in 4.1. A type that cannot be compiled, or that mentions a variable bound inside the term, is **unknown**.

Every template the compiler records is unchanged by preprocessing. The testing option `solve_by_sat.checkTemplates` checks this, and it holds on every goal and H constant of the milestone 7 corpus. Before milestone 7, type templates of ground terms and positions were built from the raw inferred type. The typing clause (6.8) then compared an unnormalised type with a normalised one, which could exclude a real proof: a completeness bug, never a soundness one.

Term binders are opened as local declarations during compilation, so types can still be inferred, and their variables are converted back to `bvar:i`.

### 4.6 Rejections

Compilation fails with a specific message for a constant in `H` that: has a head whose symbol is a clause variable; applies a clause variable to arguments; has a binder type that mentions a proof variable; has a premise that is not a goal formula; or is a type former such as `Nat`. A root goal that is not a goal formula is rejected, and so is a target `∃` over a proposition.

## 5. SAT variables

The CNF has two groups of variables: structural variables that describe the proof tree, and label bits that describe the values of terms. Nodes are numbered `0` to `N − 1`, node `0` is the root, and a parent always has a smaller number than its children.

### 5.1 Structural variables

| Variable | Meaning | Count |
| --- | --- | --- |
| `act(α)` | node α is used | N |
| `cl(α, c)` | node α applies clause `c` | N · C |
| `gp(α, g)` | node α solves goal or data position `g` | N · G |
| `y(α, β, k)`, α < β | node β is child `k` of node α | N² · A / 2 |
| `anc(γ, β)`, γ < β | node γ is a proper ancestor of node β | N² / 2 |
| `u(β, γ)`, γ ≤ β | the local clause applied at β was introduced at node γ | N² / 2 |

`C` is the number of clauses in the forest and `G` the number of goal and data positions. The child indices of a clause are its premises, followed by its data positions, and `A` is the largest number of child indices of any clause.

### 5.2 Term objects

Each node owns a private copy of every template, so the same lemma can be used at several nodes with different instantiations.

| Object | One per | Active when |
| --- | --- | --- |
| **Goal slot** `(α, goal, b)` | node α and static variable `b` (term or level) | allocated always; constrained only when in use |
| **Clause slot** `(α, clause, b)` | node α and static variable `b` | same |
| **Rigid object** | node α and non-ground position below an atom of a target or head | `gp(α, g)` or `cl(α, c)` for the template that contains it |
| **Value object** | node α and data clause `c`: the value template and its non-ground positions | `cl(α, c)`, even when the value is closed |
| **Type-template object** | node α and the type template of a variable or position | active with its owner; encoded only when needed (6.8) |
| **Ground object** | distinct ground subterm, shared by all nodes | always |

The arguments of `tgt(g)` at node α are built over α's goal slots, and the arguments of `head(c)` and of the value template over α's clause slots. Two frames per node are necessary: with one, a clause applied inside its own premise would share its variables with the parent's instance. Atoms themselves are not objects; only their arguments and the subterms below them are.

### 5.3 Labels

Every object carries a **label**, a fixed-width bit vector. Two objects have the same value exactly when their labels are equal, so a label names an equivalence class of terms. Each object's label is allocated once and reused. Twice during implementation, a missed cache gave each use fresh bits, which silently disabled matching, so a unit test now checks this for every object kind.

| Field | Width in bits | Meaning | Rigid or value object | Ground object | Eigenvariable slot |
| --- | --- | --- | --- | --- | --- |
| `sym` | log₂(symbols + 1) | head symbol of the class | constant: its symbol | constant | constant: eigenvariable symbol |
| `idx` | log₂(objects built + 1) | separates classes with the same symbol | free | constant: unique id | constant: unique id of (α, b) |
| `rank` | `clog2(N·(rt + rh) + gh + 2)` | height of the class, for the occurs check | free | constant: its height | constant 0 |
| `esc` | N | the nodes whose eigenvariables occur in the value | free | constant: empty | constant: only bit α |
| `open` | 1, present only if some template is open | the value has a loose bound variable | constant | constant | constant 0 |

Here "objects built" counts rigid, type-template, value and ground objects plus N·E eigenvariable codes. With node bounds (6.10.1), only the objects that are built count, so `idx` can be narrower. This keeps every answer, because only objects that can be active need distinct codes, but it is not a literal restriction of the old models. `rt` and `rh` are the most rigid positions in any target and any head, counting the type templates attached to them, and `gh` is the greatest ground height. This bound is sound: a strictly increasing chain of non-ground classes above the ground terms has at most N·(rt + rh) members.

All fields of an ordinary slot are free, except `open`, which is 0, so a clause variable can never take an open value. The total width is written `W`.

The remaining variables are auxiliaries introduced by the clause families: `sm` (two objects are in the same class), `d` (a bit differs), the less-than chain, `sv` (a grounding witness), and the ladder auxiliaries of at-most-one.

## 6. Clause families

The CNF is the conjunction of the families below. All are implemented; the refinements of 6.10 are on by default and each can be switched off. With node bounds on, the encoder also emits a family of unit clauses ("11 node bounds" in the counts).

**Conventions.** `L(o)` is the label of object `o`. `X ⇒ L(o) = L(o')` means bitwise equality under condition `X`: two clauses per pair of free bits, one per free bit against a constant, and the single clause `¬X` if two constant bits differ. The clause builder folds constant bits and drops tautologies. At-most-one uses the ladder encoding for 6 or more literals (3n − 4 clauses, n − 1 auxiliaries, with `xᵢ ⇒ sᵢ`, `sᵢ₋₁ ⇒ sᵢ` and `xᵢ ⇒ ¬sᵢ₋₁`) and pairwise below that.

### 6.1 Node assignment

- `act(0)`, and `act(α+1) ⇒ act(α)`: used nodes form a prefix.
- At most one `cl(α, c)` per node; `act(α) ⇒` some `cl(α, c)`; `cl(α, c) ⇒ act(α)`.
- The same three constraints for `gp(α, g)`.
- `gp(0, root)`.

### 6.2 Tree shape

- For β ≥ 1: `act(β) ⇒` some `y(α, β, k)`; at most one `y(α, β, k)` over all α and `k`; `y(α, β, k) ⇒ act(α)` and `act(β)`.
- For each α and `k`: at most one β with `y(α, β, k)`.
- Premise index `k` of `c`: `cl(α, c) ⇒` some `y(α, β, k)`. Data index `k` of `c`: no child is required. Any other index: `cl(α, c) ⇒ ¬y(α, β, k)` for every β.
- `cl(α, c) ∧ y(α, β, k) ⇒ gp(β, g)`, where `g` is the premise or data position of `c` at index `k`.

### 6.3 Context

A local clause may be used only below the node that introduced it, and each use names that node. Local clauses are local hypotheses, local data eigenvariables and built-in rules.

- At most one γ with `u(β, γ)`.
- For a global clause `c`: `cl(β, c) ⇒ ¬u(β, γ)` for every γ.
- For a clause `c` local to goal position `g`: `cl(β, c) ⇒` some `u(β, γ)` with γ ≤ β, and `u(β, γ) ∧ cl(β, c) ⇒ gp(γ, g)`. For a built-in clause, additionally `cl(β, c) ⇒ u(β, β)`.
- `u(β, γ) ⇒ anc(γ, β)` for γ < β.
- `anc(γ, β) ⇒ act(β)`. For γ < α < β: `anc(γ, β) ∧ y(α, β, k) ⇒ anc(γ, α)`. For α < γ: `¬anc(γ, β) ∨ ¬y(α, β, k)`.

Only this direction is needed for `anc`: it may be true only when γ really is an ancestor.

### 6.4 Matching

For every node α, goal or data position `g` and clause `c`:

- **Kind filter.** Proof clauses apply only at proposition positions and data clauses only at data positions; otherwise `¬gp(α, g) ∨ ¬cl(α, c)`.
- If the predicate symbols or arities of `tgt(g)` and `head(c)` differ: `¬gp(α, g) ∨ ¬cl(α, c)`.
- Otherwise, for each argument position `i`: `gp(α, g) ∧ cl(α, c) ⇒ L(argᵢ of tgt(g) at α) = L(argᵢ of head(c) at α)`.
- For a data clause on the data position of variable `b`: `gp(α, g) ∧ cl(α, c) ⇒ L(α, goal, b) = L(value of c at α)`.

### 6.5 Decomposition

This family makes label equality behave like equality of terms. It covers rigid, value, type-template and ground objects. For every unordered pair `o`, `o'` with the same symbol and arity, not both ground, and with no constant bits that differ, introduce `sm`:

- for each bit position `j` where both bits are free, a fresh `dⱼ` with `dⱼ ⇒ (bit j of o ≠ bit j of o')`, as two clauses. A free bit against a constant needs no `dⱼ`;
- `¬act(o) ∨ ¬act(o') ∨ d₁ ∨ … ∨ d_w ∨ sm`;
- `sm ⇒ L(childᵢ of o) = L(childᵢ of o')` for each child.

The direction of the `dⱼ` definition matters: with the opposite implication the family constrains nothing. Different symbols need no clauses, because their `sym` bits already differ. Pair pruning (6.10) replaces this family for pairs that can never be equal.

### 6.6 Links

- **Parent link.** For α < β, clause `c`, child index `k` (premise or data), and each `b` in the clause frame of `c`: `cl(α, c) ∧ y(α, β, k) ⇒ L(β, goal, b) = L(α, clause, b)`. The link must cover data indices too: without that, a data child's copy of the variable it builds is unconstrained, which the decoder caught as a false "proof".
- **Introducer link.** For γ ≤ β, local clause `c`, and each `b` in `Env(c)`: `u(β, γ) ∧ cl(β, c) ⇒ L(β, clause, b) = L(γ, goal, b)`.

With frame pruning (6.10), only the variables that occur somewhere below the child or clause are linked.

### 6.7 Eigenvariables, occurs check and scope

- **Eigenvariables.** For `b` in `eig(g)`: `gp(α, g) ⇒ L(α, goal, b) =` the constant label of section 5.3.
- **Occurs check.** For each rigid, value or type-template object `o` and each child: `act(o) ⇒ rank(child) < rank(o)`.
- **Escape sets.** For each such `o`, each child and each node γ: `act(o) ∧ esc(child, γ) ⇒ esc(o, γ)`.
- **Scope.** For each clause variable `b` of `c`, with `s` the clause slot `(α, clause, b)`: `cl(α, c) ⇒ ¬esc(s, γ)` for γ > α, and `cl(α, c) ∧ esc(s, γ) ⇒ anc(γ, α)` for γ < α.

Less-than on bit vectors `X < Y`, most significant bit first, uses a chain `t₀ … t_w` with `t_w` false. Assert `t₀` under the condition, and for each bit `i` add `tᵢ ∧ xᵢ ⇒ yᵢ`, `tᵢ ∧ xᵢ ⇒ tᵢ₊₁` and `tᵢ ∧ ¬yᵢ ⇒ tᵢ₊₁`.

### 6.8 Groundness and typing

Every clause variable in use must have a concrete value of the right type.

**Candidates.** For a term variable: any non-open rigid object of any node (positions in targets, heads and values), any value object, any ground object that occurs outside type templates, and any eigenvariable goal slot of any node. For a level variable: non-open rigid level objects and ground level terms. Open objects, type-template objects and `⟨proof⟩` are never candidates.

For each node α, clause `c`, clause variable `b` with slot `s`, and candidate `o`, introduce `sv`:

- `cl(α, c) ⇒` some `sv` over the candidates;
- `sv ⇒ act(o)`, and `sv ⇒ L(s) = L(o)`;
- **typing**, for term variables: `sv ⇒ L(type of b at α) = L(type of o)`.

The typing clause is handled in three ways:

- **Both types closed.** Decided at compile time: the candidate is kept if the types are identical and dropped otherwise.
- **Either type unknown.** The candidate is kept with no typing clause. If the decoder then rejects the grounding, it reports a documented limitation, not a bug. No statement in the supported fragment was found to produce an unknown type, so a testing option forces this path.
- **Otherwise.** The typing clause is emitted. Type-template objects are encoded only when some known type is not closed, so problems with only closed types keep their size.

Values forced by matching are already well typed, so the typing clause never removes a real proof. Turning the static decision off changes no answer in the test suite, only CNF sizes.

### 6.9 Built arguments

A data position (section 4.3) is an optional child index of its clause. A data node β on the data position of variable `b` applies a data clause `c'`. Matching makes its head equal the variable's type, and makes `L(β, goal, b)` equal the value of `c'` at β. The parent link carries this back to the parent's slot. The data clause's own clause variables are then grounded, matched or built like any others, so built values can nest. A value object is active only when its node applies the clause, even if the value is closed; otherwise a listed data constant could be used without spending a node.

### 6.10 Refinements

| Refinement | Flag | What it does | Why it removes no proof |
| --- | --- | --- | --- |
| Symmetry breaking | `symmetry` | breadth-first numbering: for β in 1 … N − 2, `¬y(a, β, k) ∨ ¬y(a′, β+1, k′)` whenever (a′, k′) \<lex (a, k) | any proof tree can be renumbered breadth-first; parents still precede children, and no matching, link or scope fact changes |
| Pair pruning | `pairPruning` | for a pair whose static templates do not unify with variables renamed apart, emit only "their `idx` bits differ" instead of 6.5 | equal values in a real proof are instances of both templates, so the union of the two substitutions unifies the templates apart |
| Candidate pruning | `candidatePruning` | in 6.8, skip a candidate whose type template does not unify apart with the variable's | a real grounding has equal types, which are instances of both type templates |
| Frame pruning | `framePruning` | link a variable into a child only if it occurs anywhere below it: targets, local clauses, values and type templates, recursively (`Forest.varsBelow`) | a variable absent from the whole subforest constrains nothing there |
| Ladder at-most-one | `ladderAmo` | sequential encoding for 6 or more literals | equivalent to pairwise |
| Node–clause bounds (milestone 8) | `nodeBounds` | the units `¬gp(α, g)` and `¬cl(α, c)` for pairs no proof tree can use; nothing that depends only on them is built; an early exit when no proof fits (6.10.1) | the bounds hold in every model of the structural clauses |
| Exclusive pairs (milestone 8) | `exclusivePairs` | no decomposition clauses between two objects of one node whose owners are in one at-most-one group (6.10.2) | the pair's clauses are implied or satisfiable by their own auxiliaries |

Pair pruning must keep the `idx`-differs clause. Dropping the pair outright would let two objects that can never be equal share a label. The `idx` field has a code for every object, so distinct classes can always get distinct codes.

Milestone 8 accepted only **exact** reductions: each keeps every answer and every minimal N. With its flag off, each gives the CNF of the code before it byte for byte; with both milestone 8 flags off, the encoder gives milestone 7's CNF.

#### 6.10.1 Node–clause bounds

**Dead literals.** One mechanism serves this refinement. A literal shown false in every model is emitted as a unit clause and treated as the constant `false` by the clause builder. Clauses it satisfies disappear, and no object, slot, label or auxiliary used only by them is allocated. This is exact: if F ⊨ ¬x, then F ≡ F[x := false] ∧ ¬x. Ground objects are still built, because they are always active and are candidates.

**Definitions.** Write c ▷ g when clause c passes the static tests of 6.4 for position g: the kind filter, and the same predicate symbol and arity. A built-in clause matches only its own target.

- **Least depth.** d(root) = 0. For a premise or data position p of c, d(p) = 1 + min over c ▷ g of max(d(g), e(c)). Here e(c) is d(g₀) for a clause local to g₀, and 0 for a global clause: a local clause is used only at or below the node that introduced it (6.3), and that node solves g₀.
- **Least size.** s(g) = min over c ▷ g of cs(c), where cs(c) = 1 + the sum of s(p) over the premises p of c. Data positions count 0, because they are optional (6.9).
- Both are fixpoints computed from ∞, ignoring unification.

**The bounds.**

- `gp(α, g)` is possible only if d(g) ≤ α and α + s(g) ≤ N.
- `cl(α, c)` is possible only if some g with c ▷ g has max(d(g), e(c)) ≤ α, and α + cs(c) ≤ N.

**Why they hold in every model.**

- Only node 0 solves the root, and every other node has one parent edge whose clause matches the parent's position (6.1, 6.2, 6.4). So a node's depth is at least the least depth of its position, and parents have smaller indices, so depth(β) ≤ β.
- A local clause's introducer is the node itself or an ancestor (6.3).
- Every premise index has a child with a larger index (6.2), so the subtree of α has at least cs(c) nodes, all with indices in [α, N).
- These are structural clauses, and unification only adds conditions, so the bounds hold in every model.
- Checked on models: 0 of 492 pairs used in 90 real models violate them.

**What disappears with the dead pairs:** their objects and slots; matching, links and scope clauses under them; their groundness; candidates on dead objects; and decomposition pairs with a dead object.

**Early exit.** If `gp(0, root)` is dead, because s(root) > N or s(root) = ∞, the encoder returns one empty clause and builds nothing else. The tactic then fails with the no-proof message before solving. With `verbose` it explains: "every proof has at least k nodes", or "no proof tree exists at any N".

#### 6.10.2 Exclusive pairs

Two objects at one node α whose activation literals are different members of one at-most-one group of 6.1 are never active together. Such groups are `cl(α, c)` and `cl(α, c′)` with c ≠ c′, covering head, value and clause-side type-template objects; and `gp(α, g)` and `gp(α, g′)`, covering goal-side objects. For such a pair, no decomposition clauses are emitted, and no pair-pruning `idx`-differs clause either.

This is exact. The pair's defining clause `¬act(o) ∨ ¬act(o′) ∨ d₁ ∨ … ∨ sm` is implied by the at-most-one. `sm` and the `dⱼ` occur positively only there, so setting them false satisfies the pair's other clauses. Labels of inactive objects are constrained only under their activation literals, so sharing a label does no harm.

A goal object and a head object at the same node can be active together, so they are never such a pair. A mutation that treats them as one is caught by the differential tests.

### 6.11 Why the encoding is exact

- A set of first-order equations has a unifier exactly when the terms can be labelled so that equated terms share a label, same-label rigid terms have the same symbol and pairwise same-label children, and every rigid term ranks above its children. Families 6.4 to 6.7 state precisely this for the equations of the chosen tree.
- From a real proof, label every object by its fully instantiated value. This satisfies every family, including the refinements by the arguments in 6.10, which gives completeness.
- From a model, equal labels define the substitution. Groundness guarantees each variable has a rigid member in its class, and the rank order makes the values finite, which gives soundness.
- The kernel check in section 8 is a backstop, not part of the argument. It has caught three encoder bugs during implementation (two missed label caches and the missing data-child link) and two decoder bugs on real goals in milestone 7 (section 8), each rejected rather than accepted as a proof. It cannot catch completeness bugs: milestone 7's type-template bug (4.5) was found by reviewing failures by hand.

## 7. Clause counts

The number of clauses grows as N³ in the node bound and quadratically in the total size of the hypothesis list. Two families dominate: groundness (6.8) and decomposition (6.5), which together are over 90% of the clauses on larger problems. The refinements of milestone 6 do not reduce either, except typing when the lemmas have distinct types (7.4). Milestone 8's node bounds and exclusive pairs reduce both, by about 2 to 3.4 times at N = 5 on real goals, less at larger N (7.5). The growth rates are unchanged.

### 7.1 Parameters

| Symbol | Meaning | Bound in terms of `H` |
| --- | --- | --- |
| `N` | node bound | given |
| `h`, `s` | number of hypotheses in `H`; largest statement size in expression nodes, goal included | given |
| `C`, `G` | clauses; goal and data positions | each at most (h + 1)·s |
| `A`, `a` | most child indices of a clause; largest symbol arity | at most s |
| `M`, `E` | clause variables and eigenvariable binders, in total | each at most (h + 1)·s |
| `F` | largest frame | at most (h + 1)·s; usually far smaller |
| `T` | non-ground template positions, including values and encoded type templates | at most (h + 1)·s per kind |
| `P` | sum over symbols `f` of (positions with symbol `f`)² | at most T² |
| `W` | label width (section 5.3) | about N + 2·log₂(N·T) |

### 7.2 Count per family

These are leading terms with all refinements off.

| Family | Clauses | Grows as |
| --- | --- | --- |
| 6.1 Node assignment | N·(C² + G²)/2 with pairwise at-most-one; N·(C + G) with the ladder | N · h², or N · h |
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

### 7.3 Measured sizes and times

The benchmark (`Test/bench.py`) proves `x ≤ w` from `x ≤ y`, `y ≤ z`, `z ≤ w` with transitivity, plus 0, 4 or 8 monotonicity lemmas `m ≤ n → s m ≤ s n`. All the extra lemmas share the symbol `s`; with distinct symbols the counts are smaller. L1 and D3 are the Lean tests of section 9. Every instance is satisfiable. "Before" is all refinements off; "after" is the five refinements of milestone 6. The column "with milestone 8" adds node bounds and exclusive pairs, the default since milestone 8. It comes from the `countOnly` parity test, which checks it against a full encode.

| Instance | N | Variables after | Clauses before → after | Clauses with milestone 8 | Encode ms after | Solve s before → after | Solver MB after |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 lemma | 5 | 1,237 | 16,910 → 14,283 | 10,461 | 5 | 0.01 → 0.01 | 16 |
| 1 lemma | 8 | 2,829 | 52,800 → 44,119 | 36,681 | 14 | 0.04 → 0.01 | 16 |
| 1 lemma | 12 | 5,723 | 141,128 → 116,999 | 103,801 | 36 | 0.40 → 0.03 | 17 |
| 5 lemmas | 5 | 19,292 | 193,350 → 189,563 | 119,421 | 60 | 0.07 → 0.06 | 25 |
| 5 lemmas | 8 | 58,101 | 620,176 → 608,135 | 460,965 | 187 | 0.23 → 0.28 | 77 |
| 5 lemmas | 12 | 151,055 | 1,681,688 → 1,649,015 | 1,375,973 | 508 | 1.00 → 0.86 | 196 |
| 9 lemmas | 5 | 69,242 | 618,190 → 613,943 | 368,781 | 195 | 0.24 → 0.24 | 74 |
| 9 lemmas | 8 | 215,493 | 1,978,320 → 1,965,351 | 1,450,613 | 604 | 0.93 → 1.04 | 230 |
| 9 lemmas | 12 | 553,199 | 5,159,936 → 5,126,687 | 4,207,117 | 1,565 | 3.48 → 3.27 | 619 |
| L1 | 5 | 1,377 | 19,590 → 16,523 | 12,093 | 5 | 0.01 → 0.01 | 26 |
| D3 | 3 | 1,155 | 4,793 → 4,602 | 2,373 | 1 | 0.00 → 0.00 | 26 |

Encoder memory, including the Lean runtime, ranges from about 100 MB on the forests to 600 MB at 9 lemmas and N = 12; L1 and D3 use about 430 MB because they import `Init`.

What the refinements change:

- **With 1 lemma**, frame pruning nearly halves the link clauses (53,280 to 29,280 at N = 12), and symmetry breaking cuts solve time from 0.40 s to 0.03 s.
- **With 9 lemmas at N = 8**, groundness (1,104,280 clauses) and decomposition (723,392) are 92% of the CNF and do not change. Candidate pruning needs type templates, which this untyped benchmark lacks, and pair pruning finds nothing, because every template unifies apart with every other.
- **Scaling in the number of lemmas** is therefore unchanged by milestone 6's refinements. Node bounds and exclusive pairs cut 11–40% here, and more on real goals (7.5). Reducing groundness and decomposition remains the main open problem (section 9.4).

With all refinements off and the prototype's rank width, the encoder reproduces the original prototype's counts exactly, for example 571,956 variables and 5,354,456 clauses at 9 lemmas and N = 12.

### 7.4 Typed and real-goal scaling (milestone 7)

Milestone 7 measured scaling through the Lean compile path, so type templates are real, using `countOnly` for CNFs too large to build (`EVAL.md`, R5, R6, E3 and E6).

**Synthetic families.** The chain of 7.3 with k distractors `∀ m n, R m n → R (f m) (f n)`, for k = 0, 4, 8, 16, 32 and N = 5, 8, 12. Exponents are the log-log slope of total clauses from k = 8 to k = 32; shares are at k = 32, all refinements on.

| Family | Distractors | Growth exponent | Groundness + decomposition |
| --- | --- | --- | --- |
| S | one shared `s : Nat → Nat`, `≤` on `Nat` | 1.91–1.93 | 94–97% |
| T1 | distinct `fᵢ : Nat → Nat`, `≤` on `Nat` | 1.80–1.83 | 90–95% |
| T2 | distinct carrier types `Tᵢ`, each with its own `LE` | 1.15–1.35 | 31–51% |
| T3 | distinct predicates `Pᵢ` | 1.92–1.93 | 99% |

- Switching off pair pruning alone, or candidate pruning alone, changes no cell.
- Typing matters only when the lemmas have distinct types (T2). With static typing and candidate pruning both off, T2 has 7.2–10.1 times the clauses at k = 32, with exponent about 1.8. Either filter alone does the whole job.
- Static typing also removes 2–3% of the clauses in S and T3.

**Real goals.**

- **Coverage runs.** At the final N, groundness plus decomposition is 85–96% of the clauses for every size of H, and about 70–74% even for one-node proofs.
- **Real distractors.** 50 proved goals, spread across proof sizes, each run with k = 2 to 32 compiler-accepted core lemmas added, chosen at random or with a matching head symbol:
  - the median per-goal growth exponent is 1.87 (random) and 1.73 (near);
  - at k = 32 the median CNF is about 500 times its size at k = 0;
  - the median largest k at which the original proof is still found within the limits is 16 (random) and 12 (near): 32 for one-node proofs, 16 for two, 8 for three or four, and 4 for five or more;
  - almost every failure is the 2.5 GB memory cap, which falls at about 10 to 12 million clauses.

So the quadratic growth of 7.2 holds on real, typed problems. Reducing groundness and decomposition remains the main open problem (9.4).

### 7.5 Where the clauses are, and what milestone 8 removed

Milestone 8 measured the CNF with diagnostics that replay the encoder's own builders in a counting CNF. They recount every family exactly, and attribute each clause to its cause (`eval/m8b/DIAG.md`, `eval/m8c1/SCALE.md`, `eval/m8c2a/R3SIM.md`). The points are the 200 goals of the rewriting probe (9.6) at N = 5, each with the probe's equality rules and without them: 400 points.

**Before milestone 8, at N = 5:**

- decomposition is 64% of the clauses with the rules (87% without), and groundness 34% (12%);
- 82–84% of decomposition is between objects at different nodes. Universe levels and type templates dominate it: with the rules, `succ` on levels is 32% of it and `List` 20%;
- groundness is 91% rigid-position candidates. In real models, candidates at descendant and unrelated nodes are used, so restricting candidates to ancestors would lose proofs;
- the label width W is 18–35 bits.

**Node bounds and exclusive pairs**, pooled clauses before and after:

| points | N = 5 | N = 10 |
| --- | --- | --- |
| with the rules | 2.50 times fewer | 1.70 times fewer |
| without rules | 3.38 times fewer | 2.11 times fewer |

The per-point median is 2.03 times with the rules at N = 5. The gain falls with N because fewer pairs are excluded. After both, groundness and decomposition are still 97% of the clauses with the rules. 14 of the 400 points exit early.

**Reductions measured and not built:**

- **Typing by static unification.** This would replace whole type-template objects by the triangular solved form of their unifier, with shared residual objects. Simulated exactly, it removes 0.75% of the clauses with the rules (11% without). 94% of the type-template objects are still needed, because polymorphic lemmas bind bare type variables to whole templates.
- **Universe levels as a finite domain.** The closure of the level terms exceeds 100,000 values on a third of the points.
- **Dropping groundness for rigidly matched head variables.** It would reach 0.1% of groundness with the rules. The unrestricted version is unsound: a cycle through target variables leaves a class with no rigid member (M8_PLAN 3.7.2).

## 8. Decoding: from a model to a checked proof

The decoder replays the proof tree in `MetaM`, finishes any argument that unification leaves open with the value the model chose, and has the kernel check the result.

1. **Read the skeleton.** `readSkeleton` reads each used node's clause, goal or data position, children and, for a local clause, its introducing node.
2. **Replay a node.** Starting from a metavariable for the goal:
   - introduce the binders of the goal position, recording the new free variables against the node;
   - build the head term: a constant via `mkConstWithFreshMVarLevels`, after preprocessing its type with its own parameter names, recording its level metavariables against the level slots; the free variable recorded at the introducing node; the split recipe (`And.left`, `And.right`, `Iff.mp` or `Iff.mpr` with the extra premise as a metavariable); or the built-in constructor;
   - open its non-Prop binders as metavariables and its premises, including the extra premise of `Iff.mp` or `Iff.mpr`, as **synthetic opaque** metavariables, then unify its conclusion with the target using `isDefEq` under reducible transparency. Head unification therefore cannot assign a premise, which only its child fills; this matters when a head mentions its own premise, as in `List.head_reverse`. It still compares such a premise with the target's proof by proof irrelevance, so clause variables determined through the premise's type stay determined;
   - replay each premise child on its metavariable. A data child (`replayData`) unifies the data clause's result type with the variable's type, then its value with the variable.
3. **Ground what is left from the model.** For each slot still unassigned, term or level, take the candidate whose `sv` is true and rebuild its expression:
   - a ground term: its representative;
   - an eigenvariable: the free variable introduced at that node;
   - a template position: the same position of that node's instantiated target, head or value, reached with the compiler's `decompose`;
   - a value object: the value built at that node.

   A ground term containing a proof that mentions a hypothesis has no representative valid in the decoder. It takes its expression from an occurrence of the same term in the replay instead, which proof irrelevance makes correct. Each value is type-checked in the variable's own local context, so Lean checks scope, before it is assigned.
4. **Finish.** Instantiate metavariables, fail if any remains, run `Meta.check`, and close the user's goal so the kernel checks the term.

**Dead literals.** With node bounds, `cl` and `gp` literals that the encoder folded to `false` read as false. Groundness witnesses exist only for live pairs, so the decoder needs no change.

**Unifier settings.** The whole decode runs with `foApprox` and `ctxApprox` on, the settings the elaborator gives tactics, whoever calls it. A caller with every approximation off, such as a bare `MetaM`, could otherwise fail on a valid model, because a value's metavariable sometimes has to be restricted to a smaller local context. The restriction is sound, because the scope clauses (6.7) guarantee that every grounding is in scope.

Messages:

- **CNF unsatisfiable:** "no proof with at most N nodes exists in the class".
- **Satisfiable but the decoder fails:** "decoder failed (bug)", with the skeleton. This has been caused by three encoder bugs (before milestone 7) and by the two decoder bugs fixed above (in milestone 7). The decoder rejected every one of them, and never accepted one as a proof.
- **A grounding with an unknown type is rejected by Lean:** a "documented limitation" message naming the variable and node.

Lean's `isDefEq` is stronger than the encoder's matching; for example, it solves `Nat.succ ?n =?= 1` by literal arithmetic. That is harmless, because every model is consistent syntactically.

## 9. Status and tests

Milestones 0 to 8 are complete, and the full suite (`Test/run_all.sh`) passes with all refinements on.

| # | Milestone | Key acceptance result |
| --- | --- | --- |
| 0 | SAT plumbing | 902 checks: pigeonhole, random CNFs against brute force, every gadget including the ladder |
| 1 | Forest encoder | T1 to T9 at their exact minimal N; CNF sizes equal to the prototype's on 78 instances |
| 2 | `∀`, `→`, atoms | L1 to L4, F4, G1, G2, rejections R1 to R4 |
| 3 | Connectives | L5 to L8, F1, opaque atoms and the other amendments (A1 to A4) |
| 4 | Typing and universe levels | `Eq.refl`, F2, F3, and the ill-typed grounding case E3 |
| 5 | Built arguments | D1 to D7, local data functions, level normalisation (N1) |
| 6 | Refinements | identical answers with each refinement on or off; benchmark of 7.3 |
| 7 | Evaluation on real goals | 6,300 goals from Lean core and `Std` (9.5); three bugs found and fixed with regression tests M7-R1 to M7-R3; `countOnly` equal to a full encode on every check; `EVAL.md` regenerates byte-identically from the data files |
| 8 | Scale | node bounds and exclusive pairs (6.10.1, 6.10.2), exact and on by default: 0 mismatches in every differential with each on, the mutation checks fire, the off-switch gives milestone 7's DIMACS on 54 encodings, and no disagreement with earlier per-N answers on 500 real-goal runs (9.6) |

### 9.1 Named tests

Every success is also run with one node fewer and must fail with the exact no-proof message, so each node count is minimal.

| Test | Statement or purpose | Expected |
| --- | --- | --- |
| L1 | `x ≤ w` from `h1`, `h2`, `h3` and `Nat.le_trans` | 5 nodes |
| L2 | `(A → B) → (B → C) → A → C` | 3 |
| L3 | `Q a` from `∀ y, P y → Q y` and `P a` | 2 |
| L4 | `n ≤ n` with `Nat.le_refl` | 1 |
| L5, L6 | `A ∧ B`; `A ∨ B` | 3; 2 |
| L7 | `∃ x, x ≤ b` from `a ≤ b` | 2 |
| L8 | `B` from `h : A ∧ B` | 1 |
| F1 | `(A → A) ∧ A`: a hypothesis used out of scope | no proof at 6 |
| F2 | `∃ x : Nat, ∀ y, x = y`: eigenvariable escape | no proof at 6 |
| F3 | `2 + 2 = 4`: needs computation | no proof at 6 |
| F4 | L1 with 4 nodes | no proof |
| G1 | an argument grounded but not forced by unification | succeeds |
| G2 | an ill-typed grounding | no proof, with or without the static filter |
| A1 | `h : A ∨ B ⊢ A ∨ B` and `h : A ∧ B ⊢ A ∧ B` | 1 |
| A2 | a context hypothesis with one split path that is not a clause | that path dropped, with a note |
| A3 | `∃ x, ∀ y, R x y`; `∀ y, ∃ x, R x y`, from `∀ n, R n n` | no proof at 6; 2 |
| A4 | a grounded value containing another; a ground term containing a proof | succeed |
| E1 | `n = n` with `Eq.refl` | 1 |
| E3 | `h : ∀ (S : Type) (y : S), P0 ⊢ P0` | 1, proof `h T t` |
| U1 | the unknown-type path, forced by an option | documented-limitation message |
| N1 | a lemma stated with `max u v` used at `max v u` | 1 |
| D1 | `∃ n : Nat, n ≤ n` with `[Nat.le_refl, Nat.zero]` | 3 |
| D2 | `∃ n : Nat, True` with `[Nat.zero]`; with `[]` | 3; no proof at 6 |
| D3 | `∃ n, Q n` from `∀ m, Q (Nat.succ m)` with `[Nat.zero]` | 3 |
| D4 | a built value with a built argument | succeeds |
| D5 | A3 with `[Nat.zero, Nat.succ]` added | no proof at 6 |
| D6 | `∃ n, Nat.succ n = 1`: the numeral limitation | no proof at 6 |
| D7 | `∃ n : Nat, n = 1` with `[Eq.refl]` | 2 |
| M7-R1a to R1e | a clause whose head mentions its own premise, with and without binders, and the real goal `List.getLast_eq_head_reverse` | succeed (synthetic opaque premises, section 8) |
| M7-R2a, R2b | `∀ x : Nat, x ≠ x.succ` from `Ne.symm` and `Nat.succ_ne_self`, and the real goal from `Nat.pred_eq_self_iff`, decoded with every approximation off in the caller | 4 nodes; succeed (unifier settings, section 8) |
| M7-R3a, R3b | `decide (¬ b = true) = decide (b = false)` with `[Decidable.decide.congr_simp, Bool.not_eq_true]`; `x = x` for `x : List (α × β)` with `[Eq.refl]` | 2; 1 (type templates preprocessed, 4.5) |
| M8C1 | the early exit with and without `verbose`, with node bounds off, and the bounds model check (`checkBounds`) | no-proof message before solving; the explanation line |

The tests of milestone 7 are in `Test/M7Lean.lean`, named R1 to R3 there; here they are prefixed M7 to keep them apart from the rejection tests R1 to R4 of milestone 2. M8C1 is `Test/M8C1Lean.lean`. A mutation check shows that M7-R3 fails with the template fix reverted, and the template invariant (4.5) fails on 1,036 corpus goals with it reverted.

### 9.2 Validation

- **Differential tests** against `Reference`, with every N up to 5: plain forests 7,500 comparisons, forests with binders 7,500, forests with data constants 15,000, all with 0 mismatches. The data run includes 447 proofs that use a data node.
- **Each refinement alone** also gives 0 mismatches in all three differentials.
- **Mutation checks** fire: switching off scope, the occurs check, the open bit, or the data kind filter each produces mismatches.
- **Option invariance.** The Lean suite gives identical answers with the static typing filter off and with all refinements off.
- **Unit tests** check that every object kind's label is allocated exactly once.
- **`countOnly`** equals a full encode, in variables and in every family's count, on all 44 checks: each instance of 7.3, with all refinements on, all off, node bounds alone, and both milestone 8 refinements.
- **Milestone 8.**
  - The three differentials give 0 mismatches with both milestone 8 refinements off, with node bounds, and with both.
  - Mutation checks fire. Tightening the size bound by one loses every proof at its minimal N (556 of 556, 503 of 503, 825 of 825). Treating a goal object and a head object as exclusive gives false proofs.
  - Dropping the scope term e(c) changes no answer and only makes CNFs larger.
  - With both flags off, 54 encodings are byte-identical to milestone 7's.
  - The Lean suite passes in all three settings with the bounds model check.
  - The diagnostics' recount equals the encoder's counts, with hand-count tests (`test_m8diag`).
  - Per-N exactness checks against earlier runs, on real goals, found no disagreement: the rewriting probe's 200 runs, and the 300 runs of 9.6.

### 9.3 Running the tests

- `Test/run_all.sh`: the full suite, including every test above and the `countOnly` test.
- `Test/refinements.sh`: the three differentials with each refinement on its own.
- `Test/bench.py`: the benchmark of section 7.3.
- `SOLVE_BY_SAT_SOLVER=<path>` runs everything against another DIMACS solver.
- `python3 eval/report.py` regenerates `EVAL.md` from the evaluation's data files, which are kept on the archived `eval-m7` branch (tag `m7-data`).
- `python3 eval/m8a/report.py`, and likewise for `m8b`, `m8c1`, `m8c2a` and `m8d`, regenerate milestone 8's reports from their data files, which are kept on tag `m8-data`.

### 9.4 Open directions

1. **Shrink groundness and decomposition further.** After milestone 8's reductions they are still 97% of the CNF with many lemmas (7.5). The exact reductions that remain look small (7.5). A tighter universe-level domain, built from the level instances that matching can produce, is untried.
2. **Rewriting, case analysis and induction.** These are milestone 9, where the motive is forced or chosen from finitely many candidates. Rewriting comes first, because it would reach the most goals (9.5, 9.6). Generating equality rules only for symbols on a possible rewriting path is the main lever, because rules for every symbol multiply the CNF 13 to 18 times (9.6).
3. **Search over N.** The tactic needs `N`. A wrapper that tries increasing values would return a minimal proof without the user choosing a bound. The evaluation harness's N loop is a prototype.
4. **A written correctness proof.** Section 6.11 is an argument, not a proof; a careful write-up, or a Lean formalisation of the encoding, would back the soundness and completeness claims.
5. **A lazy, incremental option**, revisited when the project is complete. It would solve with most decomposition and groundness clauses left out, add the clauses the model violates, and repeat. It would be offered alongside the one-shot mode, not in its place.

### 9.5 Evaluation on real goals (milestone 7)

Milestone 7 ran the tactic on 3,000 theorem statements of Lean core and `Std` (Tier A) and 3,000 goals from inside their proofs (Tier B). Each goal's H is the set of lemmas its real proof uses (the oracle H), N ≤ 10, under a 2.5 GB memory cap. `EVAL.md` has every table; this is a summary.

| | Tier A | Tier B |
| --- | --- | --- |
| proved | 140 (4.7%) | 836 (27.9%) |
| proved, among goals whose statement and H the compiler fully accepts | 92 of 857 (10.7%) | 765 of 1,015 (75.4%) |
| median N of the proofs | 3 | 1 |
| memory crash at the cap | 807 | 490 |
| like-for-like `solve_by_elim` (same H) closes | 977 | 2,069 |

- **Why goals fail.** The commonest reason, for 74.7% of unproved Tier B goals, is that the compiler rejects an H constant, almost always because a clause variable is applied to arguments. `congrArg` alone is rejected in 75.7% of those goals. These are the rewriting constants that elaborated `simp` proofs leave behind.
- **What rewriting could reach.** At most 946 more Tier B goals have only rewriting constants as obstacles. Only 12 have only case-analysis or induction obstacles on data, and none has only case-split obstacles. This is an upper bound: definitional unfolding, instances and proof size can still block a goal.
- **Against the baseline.** Like-for-like `solve_by_elim` also closes 96.3% of the Tier B goals `solve_by_sat` proves, about 80 times faster. Most of the 89 goals only `solve_by_sat` proves use a built-in `↔` or `∧` projection. The tactic's distinctive contributions are minimal proofs and certified "no proof with at most N nodes" answers.
- **Hand reviews.** Where `solve_by_elim` wins, the obstacle is definitional unfolding, instances or a rejected constant, never proof size. Among goals the tactic should be able to prove and does not, the commonest cause is an instance argument: instances are dropped from H.

### 9.6 Milestone 8: the rewriting probe and the scale evaluation

`M8_PLAN.md` pre-registers every stage; the reports are under `eval/m8a/` to `eval/m8d/`.

**The rewriting probe (8a).** It gave the unchanged tactic generated, kernel-checked equality rules: congruence and substitution for every symbol of a goal and its H, and `L = R` for every `↔` head in H, proved by `propext`. It ran on 100 Tier B and 50 Tier A goals whose only obstacles are rewriting constants, and on 50 proved controls, at N ≤ 10.

- **Rewriting works where the CNF fits.** 21 goals that milestone 7 did not prove are proved, at N = 1 to 8. The `propext` equations prove 8 of the 28 Tier B goals with a `propext` obstacle.
- **The rules are expensive.** They multiply the CNF at N = 5 by a median of 13 to 18 (5 for the controls). No goal with more than 10 accepted rules is proved, and most of milestone 7's certified "no proof ≤ 10" answers become resource limits.
- **With node bounds and exclusive pairs** (a rerun of the same 200 runs):
  - every control is proved;
  - 3 crashes become certified answers, and 18 become solver timeouts;
  - solving is 1.75 times faster;
  - but no further rewriting goal is proved.

**The scale evaluation (8d).** The tactic as users run it: node bounds and exclusive pairs on, milestone 7's oracle H, and no rules. It ran on samples of milestone 7's memory crashes, with proved and no-proof goals as exactness controls.

| group (population) | runs | proved | certified "no proof ≤ 10" | solver timeout | memory crash |
| --- | --- | --- | --- | --- | --- |
| Tier B memory crashes (490) | 100 | 4 | 34 | 4 | 58 |
| Tier A memory crashes (807) | 100 | 0 | 36 | 5 | 59 |
| proved controls (976) | 50 | 50 | | | |
| no-proof controls (3,083) | 50 | | 49 | 1 | |

- **Scaled to the populations.** About 20 more Tier B proofs (Wilson 95% interval: 8 to 48) and about 460 more certified answers. The memory crashes fall from 1,297 to about 760, which is 13% of the main run's 6,000 goals.
- **Exactness.** No disagreement with milestone 7 at any of the 1,737 N that both answered.
- **Speed.** The controls' N loop takes 0.39 to 0.53 of milestone 7's time.
- **Early exits.** 21 sampled goals get "no proof at any N" in under a second.
- **The remaining crashes reach higher N** than in milestone 7.

So milestone 8 makes the tactic faster and more decisive. More proofs need milestone 9's scope.


## 10. Changes from the original PDF draft

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

## 11. Changes made during implementation

The first version of this specification was written before any code. Implementation corrected it in the places below, each recorded in NOTES.md with its reason, and this revision incorporates them.

| Section | Change | Reason |
| --- | --- | --- |
| 2, 4.2 | Every target and head is also an opaque atom | otherwise `h : A ∨ B` could not prove `A ∨ B` |
| 2.1, 4.2 | Context hypotheses that are not clauses are ignored, per split path | one stray hypothesis blocked every proof, because the context is reverted |
| 3 | Solver search order, `SOLVE_BY_SAT_SOLVER`, model verification | the bundled CaDiCaL is not next to a compiled test binary |
| 4.1 | Universe levels normalised with `Level.normalize` | `max u v` and `max v u` did not match |
| 4.3 | Plain eigenvariables are not data clauses; data positions only when a data clause can match | each saves CNF size without changing which goals are provable |
| 5.3 | `open` bit introduced in milestone 3, present only when needed | `∃ x, A` contains a `fun` |
| 5.3 | Rank width `clog2(N·(rt + rh) + gh + 2)` | the original bound was a heuristic; this one is proven sufficient |
| 5.3 | Each label allocated once, with a unit test | a missed cache disabled matching twice |
| 6.6 | Parent link covers data child indices | the decoder caught a false proof without it |
| 6.8 | Static typing decision, type templates only when needed, unknown-type policy | size, and a defined behaviour for unknown types |
| 6.10 | Pair pruning keeps an `idx`-differs clause; frame pruning uses the whole subforest | dropping either would be unsound |
| 8 | Open arguments are grounded from the model; representatives of proof-containing terms come from the replay | the original decoder could not finish a grounded but unforced argument |
| 9 | `∃ n : Nat, n = 1` with `Eq.refl` is provable in 2 nodes (D7); D6 is the numeral limitation | the original expectation was wrong: the witness is forced to `1` |
| 7.3 | Benchmark lemmas share the symbol `s` | needed to reproduce the original table |
| 4.5 | Type templates are built from the preprocessed inferred type; the invariant is checked by `solve_by_sat.checkTemplates` | milestone 7: the raw type made the typing clause compare unnormalised with normalised types, excluding real proofs |
| 8 | Premises are opened as synthetic opaque metavariables | milestone 7: a head that mentions its own premise let head unification assign the premise before its child |
| 8 | The decode runs with `foApprox` and `ctxApprox` on, whoever calls it | milestone 7: a caller with every approximation off failed on a valid model |
| 3 | `EncodeOptions.countOnly` | milestone 7: counting CNFs too large to build in memory |
| 3 | `vm.overcommit_memory = 1` on the development machine | the intermittent "not enough memory" was the kernel refusing `lake`'s fork |
| 3, 6.10.1 | Node–clause bounds (`nodeBounds`), with the early exit and the dead-literal mechanism, on by default | milestone 8: about half the clauses of large CNFs can never be used, in any model |
| 6.10.2 | Exclusive pairs (`exclusivePairs`), on by default | milestone 8: decomposition between objects that are never active together |
| 5.3 | `idx` counts only the objects built | milestone 8: a by-product of node bounds; exact for every answer |
| 3 | `checkBounds`, and mutation flags `boundsScope`, `boundsTight`, `exclusiveMutant` | milestone 8: tests of the new refinements |
| 7.5, 9.4 | Typing by static unification, finite-domain levels and narrow groundness were measured and not built | milestone 8: each would remove too little, or does not fit |
