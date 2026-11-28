# Solve By SAT: milestone 9 design note

Lucas Allen · 21 November 2026; renumbered and revised 24 November 2026; revised after milestone 8, 27 November 2026

**Status: accepted (27 November 2026), with the owner's decisions in section 10.** `M9_PLAN.md` in the repository plans and pre-registers the stages, and records what is built (9a-1 and 9a-2 by 28 November). A copy of this note is kept at the root of the repository on branch `m9`, identical to the claude.ai project's, so that Claude Code can read it. The two are changed together.

- This revision rewrites section 6 (rewriting), from milestone 8's rewriting probe and measurements, and updates sections 7 to 10.
- Families 1 and 2 (sections 4 and 5) are unchanged in substance.
- Once accepted, the note is the basis of `M9_PLAN.md` in the repository. That plan pre-registers each stage, as `M8_PLAN.md` did.

## 1. Aim

Let `solve_by_sat` mimic `cases`, `induction` and `rw` wherever the motive these tactics need is forced, or can be chosen from a finite set of candidates. The SAT solver can then pick it in the same way it picks a grounding (SPEC 6.8).

Requirements carried over from milestones 0 to 8:

- **One shot.** The CNF is still built once, and stays polynomial in N and the size of H.
- **Opt-in, at the user's expense.** Each new capability is a tactic option, off by default. It costs CNF size and solve time, and the user chooses whether to pay.
- **Nothing changes when the options are off.** With every milestone 9 option off, the DIMACS output is identical to milestone 8's for every test and corpus goal. This is checked mechanically, as in milestone 8 (54 reference encodings, plus the differential suites).
- **Soundness by the kernel, and a decoder failure is a bug.** So every rule must decode for every model. In particular, every motive the decoder builds must be type-correct by construction, which means checking it statically, at compile time.
- **The standing rules** of the handoff note apply unchanged. So do milestone 8's refinements: node bounds and exclusive pairs stay on, and every new clause must respect them.

## 2. The central observation

A motive is the function `α → Prop` that an eliminator needs, such as `motive` in `Nat.rec`, `Eq.mpr` and `Or.elim`. The ∃ case is a useful comparison. `Exists.intro` also takes a motive `p`, but the encoding never solves for it: it is read off the target `∃ x, A`. What the encoding solves for is the first-order witness.

For eliminators, finding the motive is rarely the difficulty. In the cases that matter it is forced, or is one of a few candidates. The difficulty is the goal the motive produces. The encoding works because every goal is an instance of a static template in the clause forest (SPEC 10: "still static, but only because the fragment excludes goals whose shape depends on an instantiation"). An eliminator can produce a goal that is not.

| Family | Eliminators | Motive | New goals static? | Encoder change |
| --- | --- | --- | --- | --- |
| 1 | `Or.elim`, `Exists.elim`, `False.elim`, `Classical.byContradiction`, `Classical.byCases` | the current goal | yes: the same goal with more hypotheses | a "resume" node mode |
| 2 | `casesOn` and `rec` of inductive types; listed induction principles | the goal with one eigenvariable abstracted | yes: the same template, one slot substituted | a "re-entry with substitution" node mode |
| 3A | `Eq.mpr` and `congrArg`, specialised per symbol and position; `propext` on `↔` heads | fixed per rule at compile time | yes | none: generated clauses only |
| 3B | `Eq.mpr` with the motive chosen by the solver | the goal with a chosen subterm abstracted | no | dynamic targets ("twins") |

## 3. Scope: what mathematicians actually do

Restricting to the moves mathematicians make brings most of these tactics into reach, because those moves are overwhelmingly of the forced kinds.

| Move in a written proof | Lean | Family | In reach? |
| --- | --- | --- | --- |
| "By induction on n" | `induction n` | 2 | yes |
| "By strong induction on n" | `induction n using …` | 2 | yes, as a listed principle |
| "Either n = 0 or n = k + 1" | `cases n` | 2 | yes |
| "We have A or B. Case A: …" | `rcases h with h \| h` | 1 | yes |
| "Take x with P x" | `obtain ⟨x, hx⟩ := h` | 1 | yes |
| "This contradicts h" | `absurd`, `False.elim` | 1 | yes |
| "Suppose not" | `by_contra` | 1 | yes, classically |
| "Either p holds or it doesn't" | `by_cases p` | 1, plus a choice of p | partly: p must be an atom of the forest |
| "Substituting x = t" | `subst`, `rw [h]` | 3A | yes |
| "Rewriting with a lemma" | `rw [Nat.add_comm]` | 3A | yes, at a cost in nodes |
| "Rewriting with an equivalence" | `rw [Nat.not_le]` | 3A | yes, through `propext` (6.3) |
| "By definition of f" | `unfold f`, `rw [f]` | 3A | yes, if the equation lemmas are in H |
| "Simplifying", "by algebra", "by arithmetic" | `simp`, `ring`, `omega`, `linarith`, `norm_num`, `decide` | none | no |
| "Rewriting inside the sum" | `simp` under binders, `Finset.sum_congr` | none | no: congruence under a binder is higher order |
| "By induction on the derivation of h" | `induction h` on an indexed family | 2, extended | later |
| "Using the claim twice" | `have` | none | no: proofs are trees, and a cut formula is a free choice |

So the restriction is enough for case analysis and induction. It is also enough for rewriting at first-order positions, if we accept the cost in nodes. It is not enough for normalisation and decision procedures, which are a large share of real proof steps. Those stay out by design: they compute, and the reduction is a search over a fixed proof shape.

## 4. Family 1: the motive is the current goal

### 4.1 Rules

- **Case split on a disjunction** (`Or.elim`). For each clause `c` whose head, or one of whose split paths, has the form `A ∨ B`, there is an elimination clause. Such clauses can be global clauses, local hypotheses or split paths. The elimination clause has `c`'s premises plus two case children. Case child 1 solves the current goal with a new local hypothesis `A`, and case child 2 with `B`.
- **Destructuring an existential** (`Exists.elim`). The same for heads `∃ x, A`, with one case child. It introduces a fresh eigenvariable `x` and the local hypothesis `A`.
- **Ex falso** (`False.elim`). One rule with premise `False`. Since `Not` is unfolded (SPEC 4.1), `absurd` needs nothing more: `False` is proved by a hypothesis `¬A`, which is a clause with head `False` and premise `A`.
- **Proof by contradiction** (`Classical.byContradiction`, optional). It is specialised per goal position `g`, like the introduction rules. One case child solves `False` with a local hypothesis `¬C`: a clause with head `False` whose one premise resumes `g` as it stood at the node that introduced the hypothesis. Its frame is `g`'s goal frame, which is static because the rule is specialised per `g`.
- **Case split on a proposition** (`Classical.byCases`, optional, the most expensive). Two case children, with the hypotheses `p` and `¬p`. Here `p` is not forced. It is chosen from the atom templates of the forest (targets, heads and premises), instantiated at the node, and its clause variables are grounded as usual (SPEC 6.8).

Each rule is specialised per static disjunction, existential or atom, as the introduction rules are specialised per target (SPEC 4.2). Disjunctions with proposition variables (`?a ∨ ?b`) stay out of reach, because they would need atoms to be first-class terms.

### 4.2 Encoding: resuming a goal

The new ingredient is a node that solves an earlier node's goal again, rather than a new goal position. A node either **enters** its goal position, as now, or **resumes** it.

- **A case child resumes.** It has `gp(β, g)` for its parent's `g`, its goal slots are linked to the parent's goal slots under the condition `gp(α, g)`, and it gets no new eigenvariable codes for `eig(g)`.
- **The eigenvariable constraint** of SPEC 6.7 becomes conditional on entering.
- **Local clauses of `g` stay usable**, because the node that entered `g` is still an ancestor, and `u(β, γ)` already names a node. To avoid symmetric duplicates, `u` must name the entering node.

The hypotheses a case child adds are local clauses owned by an (elimination clause, case index) pair. Their frame is static: it is the elimination clause's own frame (SPEC 4.4), whatever goal the rule is applied to. They are linked from the elimination node's clause slots through the parent link (6.6). An eigenvariable introduced by `Exists.elim` gets the case child's eigenvariable code, so the existing escape and scope constraints (6.7) keep it out of the resumed goal.

**Node bounds (SPEC 6.10.1)** must learn the new edges. A resumed goal position's least depth and least size are computed over resume edges too, and the scope term e(c) covers the case hypotheses. The bounds argument has to be rechecked for resume nodes before family 1 is built.

### 4.3 Cost

- **Matching.** These rules apply at every proposition position, so matching (6.4) cannot filter them out. But their head is the goal itself, so they add almost no matching clauses.
- **Links.** Linking a resumed goal's slots adds about N²·G·F·W clauses per elimination clause and case index. This is comparable to or larger than the links family (6.6), so it must be measured.
- **Search.** There is a larger branching factor at every node.
- **`byCases`** also adds groundness work for every candidate atom.

### 4.4 Tests

- **Successes:** `A ∨ B → B ∨ A`; `(∃ x, P x ∧ Q x) → ∃ x, P x`; `A → ¬A → B`; `¬¬A → A` by contradiction.
- **Escape:** `∀ y, (∃ x, P x) → P y` must fail, because the eigenvariable cannot leave its case child.
- **Checks:** minimality as now, and a mutation check for each new constraint (resume linking, the conditional eigenvariable constraint).

## 5. Family 2: the motive abstracts an eigenvariable

### 5.1 Rules

- **Cases and structural induction** on a binder `b` of a goal position whose type is a non-indexed inductive type: `Nat`, `List α`, `Bool`, and user structures and inductive types. The rules come from the type's recursor or `casesOn`, one child per constructor. `rec` gives one induction hypothesis per recursive field; `casesOn` gives none.
- **Listed induction principles**, such as a strong-induction principle. Accept a theorem of the shape `∀ (motive : α → Prop), premises → ∀ n, motive n`, in which the motive is only ever applied to terms. The motive is then instantiated by abstracting `b`, as `induction n using …` does. This is closest to the original idea of adding hypotheses to H. It needs its own option, because the compiler rejects these constants as ordinary clauses: the motive is a clause variable applied to arguments.
- **Lean's own eliminators.** For `Nat`, Lean's `induction` and `cases` use custom eliminators (the `induction_eliminator` and `cases_eliminator` attributes), which state the cases as `0` and `n + 1`. Core lemmas are stated in that form, and the raw `Nat.zero` and `Nat.succ n` match neither syntactically (SPEC 2.4). So the default principle per type should be the one Lean's tactics use, treated as a listed principle. Check the names against the toolchain. Milestone 7 also found `Nat.casesAuxOn` and `Nat.recAux` among real proofs' elimination constants.

### 5.2 Encoding: re-entry with substitution

Induction on `b` is applied at the node α that entered `g`. Each case child β re-enters the same goal position `g`, as follows.

- **Binders before `b`:** their goal slots are linked to α's.
- **`b` itself:** its slot is set to the term the principle gives for that case, built as a template at β over fresh eigenvariables introduced at β. That term is a constructor applied to fresh eigenvariables, or `k + 1` for Lean's `Nat` eliminator.
- **Binders after `b`:** they get fresh eigenvariables at β. Their Prop binders are introduced again as local clauses of `g` at β.

The induction hypothesis for a recursive field `k` is a local clause made from the goal formula of `g` from `b` onwards:

- head `tgt(g)`, with the slot of `b` set to `k`;
- the binders after `b` as clause variables;
- the Prop binders after `b` as premises.

It is static per (goal position, binder, case, field).

Generalisation comes free. The binders after `b` become clause variables of the induction hypothesis, so inducting on `b` generalises over everything bound after it. The choice of motive becomes the choice of binder to induct on, which the solver makes. Generalising over binders bound before `b` would need binder reordering. That could be allowed for binders that neither `b`'s type nor the binders between them depend on.

As for family 1, node bounds must cover re-entry edges.

### 5.3 Restrictions

- **Non-indexed types only**, at first. Induction on an indexed family (`induction h` for `h : x ≤ y`) also abstracts the indices, and is left for later.
- **Only binders of the goal position.** An eigenvariable introduced at an ancestor node may occur in hypotheses outside `g`, which would have to be reverted.
- **Type-correct motives.** Abstracting every occurrence of `b`, which re-entry does, should give a type-correct motive. Confirm this for binders whose types mention `b`, and reject statically where it fails.
- **`subst` is not here.** Substituting an equation `h : x = t` by re-entry is only correct when `t` mentions nothing bound after `x`. It is simpler to treat `subst` as rewriting (family 3A).

### 5.4 Tests

- `∀ n : Nat, n = 0 ∨ ∃ k, n = k + 1`, by cases.
- `∀ n, P n` from `P 0` and `∀ k, P k → P (k + 1)`, listed as hypotheses. With the raw `Nat.rec` this must fail, and with Lean's eliminator it must succeed. This tests re-entry without lemmas about the constructors.
- A test that needs a generalised induction hypothesis: the step uses the hypothesis at a different value of a later binder.
- An integration test with family 3A: an induction whose step needs a congruence step, such as `∀ n, 0 + n = n` with the core lemmas about `+` on `n + 1`. Choose the exact lemmas against the toolchain.

## 6. Family 3: rewriting

### 6.1 What milestone 8 showed

The rewriting probe (8a; SPEC 9.6) gave the unchanged tactic equality rules as generated, kernel-checked lemmas, on 150 goals whose only obstacles are rewriting constants. Its results, with the measurements of 8b to 8c-2a, set this design.

- **Rewriting works where the CNF fits.** 21 goals were proved, at N = 1 to 8. By the rules their proofs use:

  | rules used | proofs |
  | --- | --- |
  | a `propext` equation only | 8 |
  | substitution only | 5 |
  | congruence only | 3 |
  | substitution and congruence | 3 |
  | no generated rule (just `Eq.refl` or `Eq.symm`, added in H) | 2 |

  A `propext` equation is one extra split path per `↔` head. It is the cheapest rule and the most effective, and 7 of its 8 proofs have 1 or 2 nodes.
- **The rules were expensive** for a structural reason. Each was universally quantified over all of its symbol's other arguments, including types, instances and universe levels. A goal had a median of 8 accepted rules, yet they multiplied its CNF at N = 5 by a median of 13 to 18. No goal with more than 10 accepted rules was proved.
- **The cost is in types and levels.** With the rules, level symbols are 38% of decomposition, against 12% without. Type-template objects take part in 80% of it.
  - Typing by static unification (8c-2a) could not remove these objects: 94% of them are still needed, because polymorphic rules bind bare type variables to whole templates.
  - So the type and level variables have to be removed where the rules are made, not afterwards.
- **Scale alone did not help.** Node bounds and exclusive pairs halve the CNF but made no further rewriting goal provable (8c-1).

### 6.2 Design principles

- **The rules are clauses of the forest**, generated by the compiler when an option is on. There are no generated declarations: the decoder builds each proof term directly, with `congrArg`, `Eq.mpr` and `propext`. With every rewriting option off, the forest, and so the CNF, is unchanged.
- **Rules are monomorphic where possible (6.4).** A rule is instantiated at the types, instances and universe levels of an actual occurrence of its symbol, instead of being quantified over them.
- **Rules are selected (6.5).** A rule is generated only where a rewrite could take place: at a position of a term of interest, on a path to an occurrence of something that can be rewritten.
- **The proof class grows by exactly the generated rules.** SPEC 2.2 gains them as clauses, and the rule set is a deterministic function of the goal, H and the options. `verbose` lists the rules generated and the reason for each. Selection can leave out a rule that some proof needs. That is a limit of the class, stated in its definition, not a completeness bug.
- **Static motive checks.** At compile time each rule's motive is built with placeholder arguments and type-checked once. A rule whose motive fails the check is dropped and reported. The decoder can then never meet an ill-typed motive.

### 6.3 Stage 9a-1: `↔` as equations

- **The rule.** Every clause with an `↔` head, on any split path, gets two more split paths: head `L = R` with proof recipe `propext h`, and head `R = L` with recipe `(propext h).symm`. That covers global clauses, local hypotheses and nested split paths.
  - The two orientations cost one clause each, and they save the `Eq.symm` node that 3 of 8a's proofs needed.
  - The heads are equations between Prop terms, so no Prop variable is ever a head, and the fragment stays first order.
  - This is the design recommended on 24 November 2026 (handoff note).
- **Option:** `solve_by_sat.iffEq`, off by default.
- **What it adds over 8a.**
  - It covers local hypotheses `h : A ↔ B`, which the probe could not (amendment 4.1).
  - It needs no H constant and no generated declaration.
- **What it proves alone.** Goals that are an `↔` lemma read as an equation, such as `(¬ a ≤ b) = (b < a)` from `Nat.not_le`. Rewriting under a symbol needs 9a-2.
- **Tests.**
  - The hand examples of amendment 4.1, decision 5.
  - A local-hypothesis example.
  - A nested split path: an `↔` inside an `∧` head.
  - The off-switch.
  - A mutation check: swapping `propext`'s orientation in the decoder must be caught by the kernel.

### 6.4 Stage 9a-2: equality rules, instantiated at occurrences

**The rules**, as in 8a:

- **Substitution** for a predicate symbol `P` at an eligible position `i`: head `P x₁ … t … xₙ`, premises `t = s` and `P x₁ … s … xₙ`. The proof is `Eq.mpr (congrArg (fun y => P x₁ … y … xₙ) h) p`.
- **Congruence** for a function symbol `f` at an eligible position `i`: head `f x₁ … t … xₙ = f x₁ … s … xₙ`, premise `t = s`. The proof is `congrArg (fun y => f x₁ … y … xₙ) h`.
- **The equality core.** `Eq.refl`, `Eq.symm` and `Eq.trans` as built-in clauses when the option is on, unless H already has them. `Eq.trans` has a middle term that only groundness can determine, so its cost is measured separately and it has its own switch.

**Eligible positions** are as in 8a (amendment 4.1, decision 3). They are explicit arguments whose values are terms, not types, instances or proofs. They exclude any argument on which another argument's type, or the result type, depends.

**Instantiation at occurrences (new).** The arguments of an occurrence of `f` divide into its **context** and its **eligible positions**:

- the **context** is its universe levels and the arguments at ineligible positions, such as types and instances;
- the **eligible positions** are the term arguments the rules may rewrite.

A rule is generated per (symbol, position, context) that occurs in the forest, with the context fixed as it occurs. Only the eligible positions become clause variables.

| The occurrence's context is | The rule's context is | The rule is |
| --- | --- | --- |
| ground, for example `@HAdd.hAdd Nat Nat Nat _` | ground | a global clause with no type, instance or level variables |
| over the root's eigenvariables, for example `α` and `inst` of the goal | the root's eigenvariable slots, which are constant labels (SPEC 6.7) | a clause local to the root goal position (SPEC 4.4), with no type, instance or level variables |
| over clause variables of a clause from H | those clause variables | polymorphic in them alone, as in 8a |

Every rule is still a valid lemma instance, because the context only specialises universally quantified arguments, so this is sound. The goal is reverted, so its type parameters and instances are root eigenvariables, and they are in scope at every node. The first two rows should cover most of the goals of 8a, whose types are concrete (`Nat`, `Int32`, `String`) or the goal's own parameters. 9a-2 measures how many rules fall in each row.

Two occurrences with the same context share a rule. Contexts that differ only in a level parameter's name are compared after `Level.normalize` (SPEC 4.1).

### 6.5 Selection: rules only on rewriting paths

**Sources.** The equations available for rewriting:

- heads `l = r` of H clauses and local hypotheses, on any split path;
- the `propext` paths of 6.3, when `iffEq` is on.

The **source symbols** are the head symbols of each side `l` and `r` that is not a variable. A side that is a variable can match anything, so it adds no source symbol. Its other side still does.

**Terms of interest.** Every argument template of:

- the targets of the goal positions, which include the premises of H clauses and the data positions;
- the sides of the sources, because a chain of rewrites rewrites inside an earlier right-hand side.

**Paths.** Take each rigid occurrence of a source symbol in a term of interest, and the spine from that term's root down to it.

- **Substitution.** Generate a rule for the atom's predicate symbol at the argument position where the spine starts.
- **Congruence.** For every function symbol `f` on the spine, above the occurrence itself, generate a rule at the argument position that the spine goes through.
- In each case the context is taken from that occurrence.

Each rule is generated once per (symbol, position, context), however many paths pass through it.

**Strict and liberal.** This rule is strict: a variable leaf in a term of interest is not treated as a possible occurrence. The liberal variant also lets a variable leaf count, and then selects every eligible position above it. 9a-2 counts the rules each variant would generate, but builds only the strict one. The substitution and congruence rules that 8a's 11 proofs with such rules used should all sit on spines down to a symbol of the equation each proof rewrote with. 9a-2 checks this from their forests, and any exception is reported.

**User override.** `rewriteSymbols := [f, g, …]` replaces the automatic choice of symbols, but keeps the eligibility, context and spine rules.

### 6.6 Cost expected, and how it is measured

- **Fewer and lighter rules.** Instantiation at occurrences removes the type, instance and level variables that made 8a's rules expensive (6.1). Selection removes rules on symbols that no equation touches. Neither saving is known yet.
- **The first measurement of 9a-2,** before any evaluation, uses the 400 points of milestone 8 at N = 5 and N = 10, with node bounds and exclusive pairs on. It compares three CNFs:
  - with 8a's rules given as lemmas, as in 8c-1;
  - with the in-tactic rules;
  - without rules.

  It also counts rules by table row (6.4) and the strict against the liberal variant (6.5).
- **The family shares are recounted** with milestone 8's diagnostics, extended to the new clauses. The share of level symbols in decomposition is the key number: 38% with 8a's rules, against 12% without.

### 6.7 What stays out

- **Rewriting under binders** (`fun`, `∀`, `∃` in terms): congruence under a binder is higher order.
- **`Decidable`-dependent positions** (`decide p`, `if p then … else …`). Their instance depends on the rewritten argument, so those positions are not eligible. The generated `congr_simp` lemmas, which oracle H often contains, still cover them as ordinary clauses.
- **`simp`'s own steps** (`of_eq_true`, `eq_true`, `eq_false`, `congrFun'`). A user's rewriting proof does not need them.
- **Rewriting at a Prop position with a Prop variable** as the rewritten side. The sources' sides may be propositions (6.3), but a rule never has a Prop variable as its head.

### 6.8 Route 3B: native rewrite nodes (later, if 3A is too costly)

The solver chooses the instance of the left-hand side `a`, which must be a subterm of the current goal, as a candidate choice like groundness. The motive abstracts its occurrences. The new goal `G[a := b]` is not an instance of any template, so each rewrite needs a twin object for each of the target's objects. A twin's label is `b`'s if its class is `a`'s. Otherwise the twin has the same symbol, with twin children.

- **Cost.** Twins join decomposition (SPEC 6.5), one of the two dominant families. A pool of R rewrite slots (`rewrites := R`) bounds the cost to about R times the size of a target.
- **The decoder must build the motive from the model.** The encoding has no congruence closure: decomposition goes from equal labels to equal children, never back. So a model may give an occurrence of `a` a different label and leave it unrewritten. That is sound only if the decoder abstracts the positions the model rewrote, rather than every occurrence via `kabstract`.
- **Chains.** A later rewrite may need an occurrence inside an earlier right-hand side, so one rewrite's twins must be built over an earlier rewrite's twins.

Prototype route 3B in Python before any Lean work, as the original encoding was. Consider it only if 9a's evaluation shows that the node cost of 3A, about d + 1 nodes for a rewrite at depth d, is what blocks proofs.

## 7. User-facing options

A sketch; the names are settled in M9_PLAN. Each is also a `set_option solve_by_sat.…`.

```lean
solve_by_sat [H] (nodes := N)
  (iffEq := true)                         -- 9a-1: L = R and R = L paths for ↔ heads
  (rewrite := true)                       -- 9a-2: selected congruence and substitution rules,
                                          --       and Eq.refl, Eq.symm, Eq.trans
  (rewriteSymbols := [HAdd.hAdd, …])      -- 9a-2: override the automatic choice of symbols
  (eqTrans := false)                      -- 9a-2: leave Eq.trans out
  (cases := true)                         -- family 1: Or.elim, Exists.elim, False.elim
  (byContra := true) (byCases := true)    -- family 1, classical, more expensive
  (induction := [Nat.rec, …])             -- family 2: recursors and listed principles
```

All options default to off. `solve_by_sat.verbose` reports the clauses each option added, per family, and lists the generated rules, so the user sees what they are paying for. Check every constant name against the installed toolchain.

## 8. Correctness obligations

- **Proof class.** Extend SPEC 2.2 with each new rule, and state when a tree with these nodes is a proof. For 3A, the class is backward chaining with H plus the generated rules of 6.3 to 6.5.
- **Reference prover.**
  - The rules of family 3A are ordinary clauses, so the reference prover needs no change. The differential suites need forests that contain them, generated by the same code as the compiler's rules.
  - Families 1 and 2 extend `Reference.lean` with the same rules. This is the only completeness check on the encoder.
- **Mutation checks,** one for each new constraint:
  - for 3A: position eligibility, the static motive check, and the context of an instantiated rule;
  - for family 1: resume linking and the conditional eigenvariable codes;
  - for family 2: substituted slots and the induction hypothesis's frame.
- **Static motive checks.** Show at compile time that every motive the decoder can build is type-correct (5.3, 6.2). Otherwise a model could fail to decode, which the standing rule counts as a bug.
- **Node bounds.** Every new kind of edge (resume, re-entry) must keep the bounds argument of SPEC 6.10.1 valid. Check it on models, as milestone 8 did.
- **The off-switch invariant** of section 1, over every test and corpus goal.

## 9. What milestones 7 and 8 measured

**Milestone 7's E5 analysis** (EVAL.md E5) mapped the obstacles of every unproved, accepted main-run goal onto these families. A goal's obstacles are its rejected H constants and the elimination constants of its oracle proof.

| Obstacles all in | Tier A | Tier B |
| --- | --- | --- |
| 3A (rewriting) | 522 (20.2%) | 946 (50.7%) |
| family 1 (motive is the goal) | 4 | 0 |
| family 2 (cases and induction on data) | 53 | 12 |
| 3A, 1 or 2, no out-of-reach obstacle | 722 | 991 |
| out of reach (for example `funext`, `of_decide_eq_true`) | 333 | 171 |

- **The upper bound.** If every 3A-only goal became provable, Tier B coverage would be at most 59.4% (from 27.9%), and Tier A at most 22.1% (from 4.7%).
- **Families 1 and 2 almost never stand alone.** They matter mostly in combination with 3A.
- **This is a loose bound.** 8a proved 14% of a sample of the goals E5 counts as rewriting-only, and two of those needed no rewriting at all.

**Milestone 8** (SPEC 7.5 and 9.6):

- The rewriting probe proved 21 of 150 rewriting-only goals, at a CNF cost of 13 to 18 times (6.1).
- Node bounds and exclusive pairs, now on by default, halve the CNF and turn about a third of milestone 7's memory crashes into certified answers. They made no further rewriting goal provable.
- So the cost of the rules themselves is what 9a must cut.

## 10. Proposed order, acceptance, and open questions

**Order.** Each stage stops for a check before the next.

| Stage | Work | Accepted when |
| --- | --- | --- |
| 9a-1 | `↔` as equations (6.3) | The off-switch gives milestone 8's DIMACS. The hand examples and the local-hypothesis test pass. The differentials have 0 mismatches. The mutation checks fire. |
| 9a-2 | Equality rules, instantiated at occurrences and selected (6.4, 6.5) | The same, plus the static motive check on every rule of the corpus goals, and the measurement of 6.6 |
| 9a-3 | Evaluation of 9a, pre-registered in M9_PLAN | See below |
| 9b | Family 1 (section 4) | As for 9a, with the node-bounds check for resume edges |
| 9c | Family 2 (section 5) | The same, for re-entry edges |
| 9d | Route 3B (6.8), only if 9a-3 shows that the node cost of 3A blocks proofs | Python prototype first |

**9a-3 evaluation, to be pre-registered in M9_PLAN.**

- **8a's 200 specs**, with in-tactic rewriting in place of the probe's lemmas, against 8c-1's rerun of the same specs. Two checks:
  - every goal 8c-1 proved without a generated rule must still be proved;
  - a goal it proved with one, and does not prove now, is listed and explained: either the selection left a rule out, or the rule's context is different.
- **A fresh, seeded sample** of the E5 rewriting-only goals not used in 8a, from both tiers, with milestone 7's controls.

**The first prompt of milestone 9** also fixes milestone 8's report hazard: each `report.py` under `eval/m8a/` to `eval/m8d/` stops with "the data is on tag m8-data" when its data is absent, instead of writing a stub.

**The owner's decisions** (27 November 2026), as recommended:

1. **Rules are made per use (6.4).** They are not 8a's fully polymorphic rules, which are independent of occurrences but 13 to 18 times as costly.
2. **Strict selection (6.5)** is built first. The liberal variant is only counted, and may be added later as an option if 9a-3 shows rules missing.
3. **`Eq.trans` is in** the `rewrite` option by default, with the switch `eqTrans` to leave it out.
4. **Every milestone 9 option starts off.** Defaults, including `iffEq`'s, are decided after 9a-3.

**Still open.**

1. **Family 1 details.** These are unchanged from the earlier revision:
   - is a resume mode better than copying goal positions per elimination clause?
   - should elimination rules be specialised per goal position or conditioned on `gp(α, g)`?
   - which atoms are candidates for `byCases`?
2. **Indexed families** for `induction h`, left for later.
3. **Out of scope.** Lemma reuse (`have`), normalisation (`simp`) and decision procedures stay out. Revisit them only with a different design, such as calling a certified procedure on static goal positions, which would give up the one-shot property.
