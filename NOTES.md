# Implementation notes

Deviations from SPEC.md, places where the spec was wrong or unverified, and the reason
for each. Grouped by milestone.

## Environment

- Toolchain: Lean 4.36.0 (`lean-toolchain`), Lake 5.0.0. Lean core and `Std` only.
- Reference prototype verified on this machine: `tests.py` all 13 pass; `diff.py 1500 5`
  gives 7,500 comparisons, 2,461 provable, 0 mismatches, 157 forests with minimum ≥ 2
  (matches SPEC §9.3 exactly).

## Milestone 0: SAT plumbing

- **Bundled CaDiCaL (SPEC §3, "not verified").** Confirmed: Lean 4.36.0 ships
  `cadical` (v2.1.2) in the toolchain's `bin/`. `bv_decide` finds it as
  `IO.appPath.parent / "cadical"` with fallback `"cadical"` on `PATH`
  (`Lean/Meta/Tactic/BVDecide/TacticContext.lean`). `IO.appPath` is the `lean` binary
  only when running inside the elaborator; in a compiled test executable it is the test
  binary. So `Solver.findSolver` tries, in order: `$SOLVE_BY_SAT_SOLVER`,
  `IO.appPath.parent/cadical`, `Lean.findSysroot/bin/cadical`, `cadical` on `PATH`.
- **Addition: `SOLVE_BY_SAT_SOLVER` override.** Lets the tests run against another
  DIMACS solver (e.g. the prototype's `cdcl`, or `/usr/bin/cadical` 3.0.1). `-q` is
  passed only when the solver's file name is `cadical`. M0 passes with all three solvers.
- **Addition: model verification.** `runSolver` checks every returned model against the
  CNF and fails loudly otherwise; a buggy solver cannot produce a false SAT.
- **Addition to the acceptance tests.** Besides pigeonhole 7→6 and 300 random CNFs, M0
  checks (a) that constant folding in `addClause` preserves the meaning of each random
  clause set, and (b) the `eq`/`lt`/`amo` gadgets exhaustively against their meaning on
  300 random instances. A mutation of `lt` or `eq` (dropping one clause) makes (b) fail.
- **At-most-one** is pairwise, as in the prototype; the ladder encoding is milestone 6.
- **Lean API corrections** (not named in the spec, but affect the port): `String.trim`
  does not exist in 4.36.0; it is `String.trimAscii`, returning a `String.Slice`.
  `String.drop` also returns a `String.Slice`.

## Milestone 1: forest encoder

- **Port fidelity check (addition).** `Encode.encode` follows `enc.py` family by family:
  same emission order, lazy label allocation, constant folding. Test/M1 requires the
  variable *and* clause count of every forest test T1–T9 at every N = 1..6 to equal the
  prototype's (78 instances; table produced by `Test/proto/proto_counts.py`). The T1 per-family
  counts at N = 5 also equal the prototype's. This check found a real porting bug (rigid
  labels were not cached, so every use got fresh bits); the T-tests caught the same bug.
- **Prototype quirk: template height.** `enc.py`'s `height` recurses into Python strings,
  so a variable leaf counts 1 if its name is one character and 2 otherwise (T6's `cc`,
  and every variable in `diff.py`'s forests). This only widens `rank` (`RB`); it is not a
  semantic rule. `Term.height` counts every variable leaf as 1 (the prototype's value for
  one-character names, conservative w.r.t. a 0-height leaf). `proto_counts.py` patches
  `height` to this definition; on T1–T9 the generated sizes coincide with the unpatched
  prototype's anyway.
- **Rank width (SPEC §5.3).** The spec says `d` is "the greatest template depth"; the
  prototype (followed here) takes it as the height of the whole atom including the
  predicate level, with the variable-leaf convention above.
- **Symbol table.** The prototype keys the eigenvariable symbol as `('EV', 0)`, which would
  collide with a user constant named `EV`. Here the eigenvariable key is `none` and real
  symbols are `some (name, arity)`. No effect on the tests.
- **Skeleton reading** (SPEC §8 step 1) is pure, so `readSkeleton`/`renderSkeleton` live
  in `Encode.lean`, not `Decode.lean`; milestone 2's decoder will call them.
- **Differential generator.** `rnd_problem` is ported with the same shape probabilities,
  but Lean's forests differ from Python's because the RNG differs. Result on 1,500 seeds ×
  N ≤ 5: 7,500 comparisons, 2,551 provable, 0 mismatches, 167 forests with smallest
  proof ≥ 2 (prototype: 7,500 / 2,461 / 0 / 157).
- **Mutation checks** stop each worker at its first mismatch. The prototype ships no
  mutation script, so these are new code; both fire (scope off: e.g. seed 774 N 2; occurs
  off: e.g. seed 1444 N 2).
- **Parallelism.** The differential test runs in 4 worker threads (`test_m1 [seeds]
  [workers]`). With 8 workers, spawning the solver failed with ENOMEM on this machine
  (about 2.5 GB available); 4 is the default.
- **`Reference`** names eigenvariable constants `ev#k`, as `diff.py` does; a user symbol
  with that prefix would be misread. Only the generated forests use the reference.
- **Not yet built (by design):** the built-in `u(β, β)` clause of 6.3 (milestone 3), typing
  in 6.8 and the `open` bit (milestone 4). The prototype omits them too.

## Milestone 2: Lean front and back end for `∀`, `→`, atoms

- **Rank width replaced (instruction, milestone 2).** `RB = clog2(N·(rt + rh) + gh + 2)`,
  where `rt`/`rh` are the most rigid (non-ground application) positions in any target / any
  head, and `gh` the largest ground-term height. Reason it suffices: ground objects have
  rank = height ≤ gh; every active rigid object is a rigid position of its node's one target
  or one head, so a strictly increasing chain of non-ground classes above the ground terms
  has at most N·(rt + rh) members; eigenvariables have rank 0. All milestone 1 tests pass
  with it (T1–T9, differential 7,500 / 0 mismatches, both mutations fire). The CNFs are
  smaller (T1 at N = 5: 1,225 / 16,910 instead of 1,505 / 22,270). The size cross-check
  against the prototype runs with `EncodeOptions.protoRank := true`, which restores the
  old width, so that check still compares exact prototype numbers.
- **Static typing in 6.8 (instruction, milestone 2).** Compile records a type template for
  every static variable, every non-ground template position and every ground term. A
  grounding candidate is dropped when both its type and the variable's type are ground
  templates and differ; otherwise it is kept with no typing clause (the full rule is
  milestone 4). Type templates may contain `pi`/`lam` with de Bruijn `bvar i` leaves, so
  closed function types compare up to binder names; a type that cannot be compiled is
  "unknown" and filters nothing. Level objects and `⟨proof⟩` are never candidates for a
  clause variable (different kind; a clause variable is never a proof since Prop binders
  are premises). Test G2 shows the filter matters: without it the solver grounds
  `y : Nat` to `Q : Nat → Prop` and the decoder rejects the term.
- **Ill-typed grounding that only the full typing rule prevents (recorded per
  instruction, not an encoder bug).** With `h : ∀ (S : Type) (y : S), P0` and the context
  `T : Type, t : T, Q : T → Prop`, the goal `P0` has the 1-node proof `h T t`. The type of
  `y` is `S`, a clause variable, so the static filter cannot apply, and the model grounded
  `S := T`, `y := T`. The decoder reports: "ill-typed grounding of y#5 at node 0: the model
  gives T : Type, the variable has type T". Milestone 4's typing clause
  (`L(type of y) = L(type of candidate)`) forbids exactly this. Not in the test suite yet;
  it becomes a milestone 4 test.
- **Decoder: undetermined but grounded arguments (spec gap, SPEC §8).** §2.2 admits a
  clause variable whose value no equation forces, provided it equals a term occurring in
  the proof (groundness, 6.8). §8 recomputes values only with Lean's unifier and fails "if
  any metavariable remains", so it would report a bug on such valid models (G1:
  `h : ∀ y, Q y → P0`, `q : ∀ z, Q z`, `k : Nat`; the unifier only equates `y` and `z`).
  The decoder therefore reads the remaining values from the model: for each open slot it
  takes the candidate whose `sv` is true, rebuilds the candidate's expression (a ground
  term, an eigenvariable introduced at some node, or a template position of some node's
  instantiated target or head, reached with the same `decompose` used by Compile), and
  assigns it after checking the type in the variable's own local context (so scope is
  checked by Lean). This is the "second decoder" of §8, used to finish the term rather
  than only for debugging. Limitation: a ground term that contains a proof subterm has no
  closed expression; grounding to it fails with an explicit error.
- **Preprocessing of head types in the decoder.** Constant types in `H` are compiled after
  preprocessing (§4.1), but the decoder's head term has the original type. The decoder
  preprocesses the head's type before opening its binders, so the conclusion is
  syntactically the compiled head; otherwise reducible `isDefEq` would have to unfold
  `Not`/`GE.ge` itself.
- **Lean API and constant checks (spec written without a toolchain).**
  `Lean.Meta.instantiateMVars` does not exist; it is `Lean.instantiateMVars`.
  `MVarId.revertAll`, `MVarId.introN`, `forallMetaTelescopeReducing` (with a binder
  limit), `mkConstWithFreshMVarLevels`, `zetaReduce`, `Core.betaReduce`, `Core.transform`,
  `Meta.check`, `realizeGlobalConstNoOverloadWithInfo`, `Expr.eqv` exist as expected.
  `Nat.le_trans : ∀ {n m k : Nat}, n ≤ m → m ≤ k → n ≤ k` and
  `Nat.le_refl : ∀ (n : Nat), n ≤ n` match the spec, and `≤` elaborates on both sides
  to `@LE.le Nat instLENat`. `Not` is now tagged `@[implicit_reducible]` (`Ne`, `GE.ge`,
  `GT.gt` are `@[reducible]`); preprocessing unfolds the four by instantiating their
  definitions, so this does not matter.
- **Symbols (§4.4).** A constant `c.{l₁…lₘ} a₁…aₖ` is the symbol `c:<name>` over the levels
  then the arguments; its key is (name, m + k), which is equivalent to `(c, m, k)` since
  `m` is fixed per constant. Literals are `lit:<value>`, projections `proj:<S>:<i>`.
- **Milestone boundaries.** Until milestone 3, `∧ ∨ ∃ ↔ True` in targets and heads are
  ordinary atoms with a constant head. Universe-polymorphic constants in `H` and binders
  inside terms are rejected naming milestone 4; non-Prop constants in `H` name milestone 5.
- **Clause head before premises.** Compile reads a clause's head before its premises so
  that `Or.elim` is rejected for its bare-variable head (§2.1), not for a premise.
  Numbering is unchanged.
- **Unspecified details.** `(nodes := N)` defaults to 8 when omitted. `nodes := 0` fails
  with the "no proof" message without building a CNF. Option `solve_by_sat.verbose`
  reports the CNF size and the skeleton; `solve_by_sat.staticTyping` exists for test G2.
- **Tests.** L1–L4 and F4 as in §9.2. Minimality is checked with `#guard_msgs` on the
  exact "no proof with at most N−1 nodes" error, which is stronger than
  `fail_if_success` (that would accept any error). Extra tests: G1, G2, and rejection
  messages R1–R4.

## Milestone 3: connectives

Amendments to the spec given with milestone 3 (recorded here as instructed):

1. **Opaque atoms.** Every target and every clause head, connective or not, is also an
   opaque atom. A target `A ∨ B`, `∃ x, A`, `A ∧ B`, `A ↔ B` or `True` can be closed by its
   built-in rule or by a clause whose head is syntactically that proposition. A hypothesis
   whose head is `∨`, `∃` or `True` is kept as a clause with that opaque head; `∧` and `↔`
   heads get both the split clauses and the opaque one. (Tests A1a–A1c.)
2. **Root hypotheses that are not clauses.** A Prop binder of the root goal that cannot be
   compiled as a clause is introduced but gives no clause; the reason is reported under
   `solve_by_sat.verbose`. Constants listed in `H` are still rejected. This is applied per
   split path: e.g. for `h : A ∧ (∀ f : Nat → Nat, f 0 = 0)` the clauses `h` (opaque) and
   `h.left` are kept and `h.right` is dropped with a note. (Test A2; M2's R2 now expects
   the note and "no proof", and R2b keeps the rejection for a listed constant.)
3. **Scope test without universe polymorphism.** `(R : Nat → Nat → Prop) (r : ∀ n, R n n)`:
   `∃ x, ∀ y, R x y` fails with "no proof" at 6 nodes; `∀ y, ∃ x, R x y` succeeds (2
   nodes, minimal). (Test A3.)
4. **Decoder grounding.** A test where a grounded variable's value contains another
   grounded variable (A4a), and ground terms containing a proof (A4b). See the decoder
   entry below for how the representative is obtained.

Implementation notes and deviations:

- **Binders inside terms and the `open` bit, brought forward from milestone 4.** `∃ x, A`
  is `@Exists α (fun x => A)`, so the opaque atom of amendment 1 always contains a `fun`.
  Templates now have `lam`/`pi` over the binder type and the body, with de Bruijn
  `bvar:i` leaves (§4.4). Compile opens each term binder as a local declaration so types
  can still be inferred, and converts its variable back to `bvar:i`. The label gains the
  1-bit `open` field (§5.3): constant `open(t)` for rigid and ground objects, 0 for slots
  and eigenvariables. A slot can therefore never equal an open term, so no clause
  variable captures a bound variable. Open objects are never grounding candidates. The
  field is present only when some template is open (otherwise it would be the constant 0
  everywhere), so M1 forests keep their exact sizes. Open ground subterms (e.g. `bvar:0`)
  stay shared ground objects with `open = 1`. Sharing is sound because de Bruijn terms
  are equal exactly when they are α-equivalent. Type templates for positions under a
  term binder that mention the bound variable are "unknown".
- **Built-in clauses** (§4.2 table) are local to their goal position, with head = the
  target's opaque atom, and carry `cl(β, c) ⇒ u(β, β)` (§6.3). The prototype has no
  built-ins. `∃` over a proposition (`∃ h : P, Q`) is rejected (a witness would be a proof).
  An `∃` whose body is not a literal `fun` is η-expanded (`A := p w`).
- **Head splitting.** Each split path (opaque, `left`/`right` for `∧`, `mp`/`mpr` for `↔`,
  recursively) is compiled as its own clause, with fresh binders so split clauses share
  no static names, and with its own copies of the premise goal positions. The decoder
  rebuilds the clause proof from a recipe of steps: open binders as metavariables,
  `And.left`/`And.right`, `Iff.mp`/`Iff.mpr` with the extra premise as a metavariable.
  A component that is itself a `∀` adds binders (they are opened by the next step).
- **Ground representatives (amendment 4).** Each ground term records a representative
  expression when it has a closed one. A ground term whose proof subterm mentions a
  hypothesis (e.g. `⟨3, hp⟩` with `hp` a local hypothesis) has no representative that is
  valid in the decoder: the compile-time free variable `hp` is not the decoder's. So the
  decoder takes its representative from the replay instead: every occurrence of the term
  in a replayed target or head (at the same template paths) is a candidate expression,
  and the first one that is in the variable's scope and well typed is assigned (each
  attempt is rolled back on failure). Proof irrelevance makes any occurrence correct.
  Test A4b grounds `s` this way; its printed proof term shows `⟨3, hp⟩`.
- **Bug found by the decoder (soundness backstop).** The new `open` field reintroduced the
  M1 bug pattern: `return` inside `let l ← match …` in `Encode.lab` skipped the label
  cache for slots, so every use of a slot got fresh bits and matching constrained
  nothing. The decoder rejected every "proof" ("head … does not unify with the target"),
  as §6.11 says it must. Fixed, and all `lab` branches now use `pure`.
- **Lean API checks.** `And.intro`, `Or.inl`, `Or.inr`, `Exists.intro.{u}` (`{α : Sort u}
  {p : α → Prop} (w : α) (h : p w)`), `Iff.intro`, `True.intro`, `And.left`, `And.right`,
  `Iff.mp`, `Iff.mpr`, `mkArrow` (now in `CoreM`), `Expr.isAppOfArity`,
  `Meta.saveState`/`SavedState.restore` all as expected. `∃ x, …` elaborates to a literal
  `fun`.
- **Regression (end of milestone 3, full `Test/run_all.sh` run, exit 0):** L5–L8 succeed
  with their spec node counts, and each fails with one node fewer with the exact "no proof
  with at most N−1 nodes" message (`#guard_msgs`), so the counts are minimal. F1 fails with
  "no proof with at most 6 nodes exists in the class" (`#guard_msgs`) and the verbatim
  `fail_if_success` form. Every milestone 0–2 test still passes: M0 902/902, M1 17/17
  (T1–T9 exact minimal N, 78 prototype sizes, differential 7,500 comparisons / 0
  mismatches, both mutations fire), M2 L1–L4 with minimality, F4, G1, G2, R1–R4 (R2
  updated per amendment 2, R2b added).

## Milestone 4: typing clause and universe levels

- **Typing clause (SPEC §6.8).** For each kept grounding candidate `o` of a term variable
  `b` at node α: `sv ⇒ L(type of b at α) = L(type of o)`. Type templates are instantiated
  per node as new objects (`Obj.trigid`, owned by a variable or a template position;
  variable leaves are the slots of the owner's frame, closed subterms are ground objects).
  They are active with their owner, take part in decomposition, the occurs check and
  escape sets, and are never candidates. Ground terms that occur only in type templates
  get idx codes but are never candidates. A pair is decided statically when both types
  are closed (unless `staticTyping` is off, in which case the clause compares the two
  constant labels, with the same result). A pair with an unknown type gets no typing
  clause.
- **When type templates are encoded.** Only if some known type is not closed, or the
  static filter is off. Otherwise every pair is decided statically and the templates
  would only widen the tables. L1 therefore has the same size before and after:

  | Test | before (typing clause off) | after |
  | --- | --- | --- |
  | L1 (N = 5) | 1,365 variables / 19,590 clauses | 1,365 / 19,590 |
  | E1 `n = n` by `Eq.refl` (N = 1) | 46 / 147 | 61 / 212 |

  "Before" is the option `solve_by_sat.typingClause false`, with the static filter on
  (the milestone 3 encoding plus level variables, which `Eq.refl` needs).
- **Universe levels (§4.3, §4.4).** The universe parameters of a constant in `H` are
  static variables of kind `level`, fresh for every clause made from it (one per split
  path). Level variables have only level candidates (non-open rigid level objects and
  ground level terms) and no typing clause; term variables never get level candidates.
  The decoder records the level metavariables of `mkConstWithFreshMVarLevels` against
  these slots and grounds any left open from the model, like term variables. Universe
  parameters of the goal stay constants.
- **Rank and idx widths with type objects.** idx counts the objects actually built
  (`rigid + type rigid + ground + N·E + 1`; for an untyped forest this equals the
  prototype's `N·T + ground + N·E + 1`). The rank bound adds, per goal and per clause, the
  rigid positions of the type templates attached to it (its variables' and positions'
  types): `RB = clog2(N·(rt + rh) + gh + 2)`, with `gh` over all ground terms, those of
  type templates included. The `open` bit also considers type templates.
- **Requirement 2, unknown types.** A candidate or variable whose type template is unknown
  gets no typing clause (the candidate is kept). If the decoder then cannot assign the
  grounding, it reports "solve_by_sat: documented limitation (NOTES.md, milestone 4): the
  model grounds `b` at node α to a candidate whose type, or the variable's type, is
  unknown to the encoder, so no typing clause applied to the pair; Lean rejects it: …"
  with the skeleton, and not "decoder failed (bug)". In this fragment I found no
  statement that produces an unknown type. The type of a closed subterm is closed, open
  positions are never candidates, proofs in types become `⟨proof⟩`, and `let` is inlined
  by preprocessing. So test U1 forces the path with the testing option
  `solve_by_sat.forgetTypes` (every type unknown) on G2 and checks the message prefix.
- **Requirement 3, label allocation.** `Encode.lab` counts fresh allocations per object.
  `test_m4` builds a typed forest with term and level slots, rigid term and rigid level
  objects, ground term and ground level objects, and a type-template object, at N = 1, 2, 3.
  It requires every object to be allocated exactly once, cached, and of width `W`.
  Reintroducing the milestone 1/3 bug (`return` in one branch of `lab`) on a copy makes it
  fail ("allocated 4 times …").
- **Requirement 4, binders in the differential test.** `Reference` unifies de Bruijn terms
  first-order (`bvar:i` is a constant) and accepts a proof only if every clause variable's
  fully resolved value is closed. The generator gets a `binders` mode that adds
  `lam(T, body)` and `bvar:i` leaves under binders; the default mode draws exactly the
  same random stream as before. Result: 7,500 comparisons, 2,346 provable, 0 mismatches,
  115 forests with smallest proof ≥ 2, 770 of 1,500 forests contain a bound variable.
  Mutation: with the `open` bit off (`EncodeOptions.openBit := false`) mismatches appear
  (e.g. seed 1472 N 2: reference false, SAT true).
- **Tests changed.** M2 R4: `congrArg` is now compiled, so it is rejected for the reason
  SPEC §2.1 gives ("the clause variable f#8 is applied to arguments in f a₁: not first
  order") instead of the milestone 2 "milestone 4" message. M2 G2 without the static
  filter: it now expects the exact "no proof" message, where in milestone 2 it expected a
  decoder failure.
- **Lean API checks.** `Eq.refl : ∀ {α : Sort u_1} (a : α), a = a` (one universe
  parameter, as the spec assumes). `isLevelMVarAssigned`, `isLevelDefEq`,
  `instantiateLevelMVars`, `Level.mvarId!` exist as expected. `#guard_msgs` has no
  substring mode in 4.36, so U1 uses a small `expect_error_with` tactic defined in the
  test file.
- **Note on the baseline run.** A baseline full run started at the beginning of this
  milestone overlapped with the first compiler edit, so its M2 result is not a clean
  milestone 3 baseline (R4 saw the new `congrArg` message). The milestone 3 Regression
  line above cites the full run at the end of milestone 3 instead.
- **Regression (end of milestone 4, full `Test/run_all.sh` run, exit 0):** E1, E2, E3 succeed
  with their node counts and E1/E3 fail with one node fewer (`#guard_msgs`); F2 and F3 fail
  with the exact "no proof with at most 6 nodes" message; G2 with the static filter off
  gives "no proof"; U1 gives the documented-limitation message. Every milestone 0–3 test
  still passes: M0 902/902; M1 19/19 (T1–T9 exact minimal N, 78 prototype sizes,
  differential 7,500 / 0 mismatches, binder differential 7,500 / 0 mismatches, scope,
  occurs and open-bit mutations fire); test_m4 4/4; M2 L1–L4 with minimality, F4, G1, G2,
  R1–R4; M3 L5–L8 with minimality, F1, A1–A4.
- **The milestone 2 ill-typed case is test E3** in `Test/M4Lean.lean`:
  `theorem E3 (T : Type) (P0 : Prop) (t : T) (Q : T → Prop) (h : ∀ (S : Type) (y : S), P0) : P0`
  with `solve_by_sat [] (nodes := 1)`. It succeeds in 1 node, and `#guard_msgs` on
  `#print E3` checks that the proof term is exactly `fun T P0 t Q h => h T t`. With
  `(nodes := 0)` it fails with "no proof with at most 0 nodes".

## Between milestones 4 and 5

- **(a) Static filter off, whole Lean suite.** `Test/M2.lean`, `Test/M3.lean` and
  `Test/M4Lean.lean` were run with `lake env lean -Dweak.solve_by_sat.staticTyping=false`
  and compared with the default run, after masking only the CNF sizes in the verbose
  lines. The outputs are identical: exit codes, every `#guard_msgs` message, every
  decoded skeleton and every printed proof term. The sizes do differ (the option took
  effect), e.g. L1 1,365 / 19,590 by default against 1,465 / 21,410 with the filter off.
  The static filter is therefore an optimisation only, on this suite.
- **(b) Universe levels are normalised in preprocessing.** `Level.normalize` exists in
  4.36 (`Level → Level`). It sorts the arguments of `max` (parameters by name), absorbs
  subsumed terms (`max (u+1) (max v u)` → `max (u+1) v`), turns `imax u (v+1)` into a `max`,
  and pushes `succ` inside `max`. `preprocess` applies it to every level
  (`Expr.replaceLevel`). The decoder must reproduce the compiled template exactly, so
  for a constant it preprocesses the constant's type with its own parameter names first
  and only then instantiates the parameters with fresh level metavariables (normalising
  after instantiation could order `max` arguments by metavariable id instead).
  Test N1 (`Test/M5.lean`): `theorem maxL (f : Sort (max u v) → Sort u) : f = f` proves
  `(f : Sort (max v u) → Sort u) : f = f` in 1 node. With normalisation removed (checked
  on a copy) the same call gives "no proof with at most 1 nodes": without it,
  `max ?u ?v = max v u` forces `?u := v` while `Sort ?u = Sort u` forces `?u := u`.
  Limitation: normalisation gives each statement a canonical form separately; it does
  not decide equalities such as `max ?a ?b = max u v` modulo commutativity when the
  orders of the lemma's and the goal's parameter names disagree. Matching stays
  syntactic on normalised levels.

## Milestone 5: built arguments (SPEC §6.9)

- **Data clauses.** A constant of `H` whose type is not a proposition is a data clause,
  unless its result type is a Sort (a type former such as `Nat`, which is rejected:
  "neither a proof nor a data constant"). An eigenvariable is a data clause when its type
  is a function type whose result is neither a proposition nor a Sort (e.g.
  `f : Nat → Int`). Non-Prop binders are clause variables, Prop binders are premises, and
  the head is the result type. The value template is the constant (with its universe
  parameters as level variables) or the eigenvariable applied to all its binders.
- **Deviation: a plain eigenvariable (no binders, e.g. `k : Nat`) is not a data clause.**
  It is already a grounding candidate (6.8), so a data node for it would only cost a
  node: any proof using one becomes a proof with one node fewer by grounding instead. The
  set of goals provable within N nodes is unchanged. Without this rule every goal with a
  `Nat` in its context (L1, L4, …) would have data clauses, and every CNF would grow.
- **Requirement 2: eigenvariable data clauses are local.** Such a clause is local to the
  goal position whose binder it is (`localOf`), so §6.3 applies unchanged:
  `cl ⇒ some u(β, γ)`, `u(β, γ) ∧ cl ⇒ gp(γ, g)`, `u(β, γ) ⇒ anc(γ, β)`, and the introducer
  link copies `Env` (which contains the eigenvariable itself) into the value. Tests E1–E3:
  `∀ f : Nat → Int, ∃ i : Int, True` builds `f Nat.zero` (4 nodes, minimal);
  `(∀ f : Nat → Int, True) ∧ ∃ i : Int, True` has no proof at 6 nodes, because `f` lives
  only in the left branch.
- **Requirement 1: data positions.** A clause variable gets a data position only if its
  type is not a proposition, not a function type (syntactic `∀`) and not a Sort; its type
  compiles as an atom (a clause-variable head, e.g. `y : S`, gets none); and the type's
  head symbol is the head symbol of some data clause (a position that no data clause can
  match would only add clauses). Compilation runs in two passes: pass 1 finds the data
  clauses, and only if there is at least one does pass 2 add data positions. With no data
  clause every earlier CNF is unchanged. Checked: the M1 prototype sizes, and every
  verbose size in Test/M2–M4, are identical except A4a (`g : Nat → Int` is now a data
  clause; 783 / 5,720 → 1,146 / 10,243, same proof).
- **Encoding.** Data positions are optional child indices after the premises: at most one
  child, none required, and `cl ∧ y(α, β, k) ⇒ gp(β, data position)`. The parent link
  (6.6) covers these indices too. Matching (6.4) adds the static filter (proof clauses
  only at proposition positions, data clauses only at data positions) and, for a data
  clause on a data position, `gp ∧ cl ⇒ L(β, goal, b) = L(value at β)`. The value is a
  per-node object (`Obj.value`), active only when the node applies the clause, even if
  closed. Its non-ground subterms are per-node too, and its ground subterms are shared
  ground objects (grounding candidates, like those of any template). Value positions
  carry type templates for the typing clause.
- **Requirement 3: groundness through a data child.** Value objects are grounding
  candidates. `test_m5` checks a forest where `w` is determined by nothing and no term of
  its type occurs: there is no proof with 2 nodes, and with 3 nodes
  (`ex(p, w:=z)`) the true groundness witness of `w` is the value object of its data
  child (`Obj.value 2 2 #[] z0`). Without the data clause there is no proof at 6 nodes.
- **Bug found by the decoder.** The parent link initially covered premise indices only,
  so a data child's copy of the variable it builds was unconstrained. `∃ n : Nat, n = 1`
  then became "provable" with a chain of four `Nat.succ` nodes, and the decoder refused it
  (`Nat.succ ?n` against `0`). Fixed by linking every child index. Lean's `isDefEq` solved
  `Nat.succ ?n =?= 1` with `?n := 0` (literal offset unification), which is stronger than
  the encoder's syntactic matching. That is harmless because models are syntactically
  consistent.
- **Decoder.** `replayData` builds the data clause's value on the metavariable of the
  variable being built: result type `isDefEq` the variable's type (reducible), then value
  `isDefEq` the variable. A grounding candidate that is a value object reads the node's
  built value.
- **Spec conflict, numeral test (requirement 4, last item).** `∃ n : Nat, n = 1` with
  [Nat.succ, Nat.zero, Eq.refl] does not give "no proof": it has the 2-node proof
  `Exists.intro 1 (Eq.refl 1)`, also with [Eq.refl] alone. `Eq.refl` forces the witness to
  equal `1`, and `1` occurs in the statement, so it is a determined argument (SPEC §2.2),
  as in L7. I did not change the encoder to force the expected answer. The test is kept
  verbatim in `Test/M5Pending.lean` (not in `run_all.sh`, currently failing) pending a
  decision.
- **Numeral limitation.** `∃ n : Nat, Nat.succ n = 1` is true (`⟨0, rfl⟩`), but has no
  proof at 6 nodes with [Nat.succ, Nat.zero, Eq.refl] (test D6). `Nat.succ ?n` never
  matches the numeral `1`, which is `OfNat.ofNat Nat 1 (instOfNatNat 1)`, and no unfolding
  or literal arithmetic is done (SPEC §2.4, "Unfolding and computation").
- **Requirement 5: Reference and the differential test.** `Reference` now proves data
  positions with data clauses (unifying the built variable with the value), applies the
  static filter, treats data children as optional, and implements groundness (6.8,
  untyped). The candidates are the instantiated rigid template positions of the nodes of
  the proof (targets, heads, values), the forest's ground subterms, and the
  eigenvariables of the nodes of the proof. A variable that unification leaves open is
  equated with each candidate in turn (the encoder may choose any). Sanity check: with
  groundness, `Reference` gives the expected minimal N on T1, T4, T4b, T5 and T6b. The
  data generator adds data types `N`/`M`, data constants `z : N := z0` (always) and,
  randomly, `s : N → N`, `m : N → M`, `w : M`, typed clause variables, data positions by
  the compiler's rule, and sometimes `N` as a nullary proposition. Result, groundness on
  in both: 15,000 comparisons (3,000 seeds × N ≤ 5), 3,854 provable, 0 mismatches, 191
  forests with smallest proof ≥ 2, 447 SAT proofs that use a data node. Mutation: with
  the 6.9 static filter off (`EncodeOptions.dataFilter := false`) mismatches appear (e.g.
  seed 68 N 1: a data clause closes the proposition `N`). The default is 3,000 seeds
  because groundness makes deep proofs rarer than in M1's 1,500.
- **Requirement 6, sizes.** D1 `∃ n : Nat, n ≤ n` (N = 3): 288 variables / 1,259 clauses.
  D3 `(q : ∀ m, Q (Nat.succ m)) : ∃ n, Q n` (N = 3): 1,155 variables / 4,793 clauses.
- **Tests changed.** M2: `solve_by_sat [Nat.zero]` on `True` used to be rejected
  ("data constants are milestone 5"); it now succeeds. The rejection test now uses the
  type former `Nat`.
- **Lean API checks.** `Int.ofNat : Nat → Int`, `Nat.succ : Nat → Nat`, `Nat.zero : Nat`,
  `Level.normalize`, `Expr.replaceLevel`, `mkFreshLevelMVar`,
  `Expr.instantiateLevelParams` as expected.
- **Environment.** Lake builds sometimes fail with "resource exhausted (error code: 12,
  not enough memory)" when spawning `lean` (no swap, about 3.8 GB available). This is very
  likely the cause of the earlier intermittent "build failed" (milestones 2 and 3). A
  retry succeeds.
- **Regression (end of milestone 5, full `Test/run_all.sh` run, exit 0):** D1–D4 and E1, E3
  succeed with their node counts and each success fails with one node fewer
  (`#guard_msgs`); D2 with [], D5, D6 and E2 give the exact "no proof" message; N1
  succeeds. Every milestone 0–4 test still passes: M0 902/902; M1 19/19 (T1–T9,
  prototype sizes, both differentials with 0 mismatches, scope, occurs and open-bit
  mutations fire); test_m4 4/4; test_m5 10/10; Test/M2, M3, M4Lean with no errors (M2's
  data-constant test updated as above). Test/M5Pending.lean is excluded and fails as
  described.
- **Numeral test resolved (after milestone 5 acceptance).** The expectation was revised:
  `∃ n : Nat, n = 1` with [Eq.refl] is a success test, test D7 in `Test/M5Lean.lean`
  (2 nodes, `Exists.intro 1 (Eq.refl 1)`, and "no proof with at most 1 nodes"), run by
  `run_all.sh`; `Test/M5Pending.lean` is removed. **D6 is the numeral limitation test:**
  `∃ n : Nat, Nat.succ n = 1` is true (`⟨0, rfl⟩`) but has no proof in the class.

## Milestone 6: refinements (SPEC §6.10) and the ladder at-most-one

- **Flags (requirement 1).** `EncodeOptions` has one flag per refinement: `symmetry`,
  `pairPruning`, `candidatePruning`, `framePruning`, `ladderAmo`. All default to true.
  `EncodeOptions.config` maps the names `all`, `none`, `symmetry`, `pair`, `candidate`,
  `frame` and `ladder` to option sets: `none` is everything off, and a single name turns on
  that refinement alone. `test_m1` and `test_m5` take the config as their third argument,
  and `Test/refinements.sh` runs both with each refinement alone. In Lean the option
  `solve_by_sat.refinements` (default true) switches all five off. The prototype size
  cross-check in M1 runs with `EncodeOptions.allOff { protoRank := true }`, so it still
  compares against enc.py byte for byte in size.
- **Ladder AMO (`CNF.amoLadder`).** The ladder uses auxiliaries `s₁ … s_{n−1}`, where `sᵢ`
  means one of `x₁ … xᵢ` is true. Its clauses are `xᵢ ⇒ sᵢ`, `sᵢ₋₁ ⇒ sᵢ` and
  `xᵢ ⇒ ¬sᵢ₋₁`: 3n − 4 clauses and n − 1 auxiliaries. It is used for 6 or more literals;
  below 6 the pairwise encoding has no more clauses and needs no auxiliaries. M0's gadget
  check now includes the ladder: for every assignment of the original variables it tests
  "some extension satisfies the gadget ⇔ at most one is true", counting a repeated literal
  twice. During development a deliberately broken ladder (one wrong index) made this check
  fail on 42 instances.
- **Symmetry breaking (requirement 4): breadth-first numbering.** For every β in
  1 … N − 2 there is the clause `¬y(a, β, k) ∨ ¬y(a′, β+1, k′)` whenever
  (a′, k′) <lex (a, k). Here `y(a, β, k)` says node β is child k of node a. Consecutive
  nodes therefore have nondecreasing (parent, child index), which is the BFS order.
  *Completeness:* the nodes of any proof tree can be renumbered in BFS order (root 0,
  then by parent number, then by child index). Parents still get smaller numbers than
  their children, so the tree-shape family of 6.2 holds. The renumbering changes no
  matching, link or scope fact, so it maps every model to one that also satisfies the
  symmetry clauses.
  *Changed proof terms (node counts unchanged):*
  - forest T1: `le_trans(h1, le_trans(h2, h3))` became `le_trans(le_trans(h1, h2), h3)`,
    5 nodes. Test unchanged, since it checks only the node count.
  - forest T2b: now `m(fun ha => bb(ha), a)`, 4 nodes. Test unchanged.
  - Lean L1: now `Nat.le_trans (Nat.le_trans h1 h2) h3`, 5 nodes. No test prints this
    term, so no `#guard_msgs` changed.
  No other printed proof changed. All `#print` guards in M2–M5Lean are identical with
  refinements on and off.
- **Pair pruning.** For a pair of objects whose static templates (the atom, type or value
  at that position, from `tmplOf`) do not unify after renaming apart
  (`Term.unifiableApart`), the encoder adds only the clause "their idx bits differ". It
  skips the label-equality and decomposition clauses for that pair. The pair is not simply
  dropped: dropping it would let the solver give two non-unifiable objects the same index,
  and that is unsound. The idx width is unchanged and still at least the number of
  classes, so distinct classes can always get distinct indices.
- **Candidate pruning.** In groundness (6.8), a candidate whose type template does not
  unify with the variable's type template (after renaming apart) is skipped. The pruning
  applies only when that pair's typing is not already decided statically.
- **Why pair and candidate pruning never remove a real proof (requirement 3).** Take a
  real proof and the instance values it assigns: every template variable gets a concrete
  term. Two objects share an index in a model only when their values in that proof are
  equal. The two values are instances of their static templates, each under its own
  substitution. With the variables renamed apart, the union of the two substitutions is a
  single substitution that makes the two templates equal, so the templates unify apart.
  By contraposition, templates that do not unify apart are never equal in any proof, and
  "idx differs" excludes no proof.
  The same argument covers candidates. A proof grounds a variable to a term whose type
  equals the variable's type, both instances of their type templates. So the candidate's
  type template and the variable's type template unify apart. A candidate that fails this
  test can never be the witness of a proof.
  Renaming apart matters: two templates may share a variable name by accident, and
  without renaming their unification would be too strict. It is only an over-
  approximation that may keep useless pairs, never one that prunes needed ones.
- **Frame pruning (requirement 2).** `Forest.varsBelow` is a fixpoint that computes, for
  each goal position and each clause, the variables occurring anywhere below it. That
  covers targets, data variables, eigenvariable types, target types, local clauses with
  their heads, values, variable types, head types and value types, then recursively the
  premise and data-position goals. A variable is linked into a child (6.6 parent link)
  only if it is in `belowG[child]`. The introducer link uses `belowC[c]`. Soundness: a
  variable absent from the whole subforest cannot affect any constraint there, so its
  link equalities only fix bits nobody reads.
- **Acceptance with all refinements on (requirement 5).** Every milestone 0–5 test gives
  the same answer and minimal node count. Differentials with all on: plain 7,500 / 0
  mismatches, binders 7,500 / 0, data 15,000 / 0. Each refinement alone
  (`Test/refinements.sh`) also gives 0 mismatches in all three differentials, and every
  mutation check still fires. The Lean suite with `-Dweak.solve_by_sat.refinements=false`
  gives the same answers and messages.
- **SPEC §7.3 table.** The table is reproduced exactly (all 9 cells, e.g. 9 lemmas N = 12:
  571,956 variables / 5,354,456 clauses) only if all monotonicity lemmas share the symbol
  `s` (`le (s m) (s n)`). SPEC does not say this; distinct symbols give smaller numbers.
  The prototype figures use the prototype's rank width (`proto` config). The "before"
  rows below use this implementation's rank width (milestone 2), hence fewer variables.
- **Benchmark (requirement 6).** Produced by `Test/bench.py`, which drives the `bench`
  executable. Peak memory comes from `os.wait4`, because `/usr/bin/time` is absent.
  "Before" = all refinements off, "after" = all on. Encoder peak memory includes the Lean
  runtime: about 100 MB for forests, about 430 MB for L1 and D3, which import `Init`.

  | instance | N | | vars | clauses | encode ms | encoder MB | solve s | solver MB |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | §7.3, 1 lemma | 5 | before | 1,225 | 16,910 | 5 | 105 | 0.01 | 16 |
  | | | after | 1,237 | 14,283 | 5 | 101 | 0.01 | 16 |
  | §7.3, 1 lemma | 8 | before | 2,744 | 52,800 | 17 | 103 | 0.04 | 16 |
  | | | after | 2,829 | 44,119 | 14 | 103 | 0.01 | 16 |
  | §7.3, 1 lemma | 12 | before | 5,460 | 141,128 | 45 | 113 | 0.40 | 31 |
  | | | after | 5,723 | 116,999 | 36 | 109 | 0.03 | 17 |
  | §7.3, 5 lemmas | 5 | before | 19,215 | 193,350 | 61 | 120 | 0.07 | 25 |
  | | | after | 19,292 | 189,563 | 60 | 119 | 0.06 | 25 |
  | §7.3, 5 lemmas | 8 | before | 57,912 | 620,176 | 192 | 161 | 0.23 | 74 |
  | | | after | 58,101 | 608,135 | 187 | 161 | 0.28 | 77 |
  | §7.3, 5 lemmas | 12 | before | 150,636 | 1,681,688 | 514 | 281 | 1.00 | 199 |
  | | | after | 151,055 | 1,649,015 | 508 | 280 | 0.86 | 196 |
  | §7.3, 9 lemmas | 5 | before | 69,125 | 618,190 | 194 | 161 | 0.24 | 74 |
  | | | after | 69,242 | 613,943 | 195 | 160 | 0.24 | 74 |
  | §7.3, 9 lemmas | 8 | before | 215,240 | 1,978,320 | 722 | 297 | 0.93 | 214 |
  | | | after | 215,493 | 1,965,351 | 604 | 305 | 1.04 | 230 |
  | §7.3, 9 lemmas | 12 | before | 552,684 | 5,159,936 | 1,575 | 596 | 3.48 | 621 |
  | | | after | 553,199 | 5,126,687 | 1,565 | 597 | 3.27 | 619 |
  | L1 | 5 | before | 1,365 | 19,590 | 6 | 431 | 0.01 | 26 |
  | | | after | 1,377 | 16,523 | 5 | 431 | 0.01 | 26 |
  | D3 | 3 | before | 1,155 | 4,793 | 1 | 427 | 0.00 | 26 |
  | | | after | 1,155 | 4,602 | 1 | 427 | 0.00 | 26 |

  All instances are SAT. Variables rise slightly because of the ladder auxiliaries.
  *Where the gains are and are not.* The per-family clause counts (bench forest, measured)
  explain the gap.
  - 1 lemma, N = 12: links drop 53,280 → 29,280 (frame pruning) and tree shape
    2,213 → 1,474. Symmetry adds 715 clauses but cuts solve time 0.40 s → 0.03 s.
  - 9 lemmas, N = 8: groundness (1,104,280) and decomposition (723,392) are 92% of the
    clauses, and neither changes. Candidate pruning needs type templates, and the §7.3
    forest is untyped. Pair pruning finds nothing to prune, because every head is
    `le(_, _)` or `le(s _, s _)` with the shared `s`, so all templates unify apart.
  The refinements therefore do not change how §7.3 scales with the number of lemmas. On
  that forest, groundness and decomposition dominate.
- **Lean API checks.** No new Lean API names in this milestone. The refinements are pure
  encoder code.
- **Regression (end of milestone 6, full `Test/run_all.sh` with all refinements on,
  exit 0):** every milestone 0–5 test passes with the same answer and minimal node count.
  - M0: 902/902, including the ladder gadgets.
  - M1: 19/19. T1–T9 are minimal and the prototype sizes match with refinements off. The
    plain and binders differentials have 0 mismatches, and the scope, occurs and open-bit
    mutations fire.
  - test_m4: passes. test_m5: 10/10 (data differential 0 mismatches, data-filter mutation
    fires).
  - Test/M2, M3, M4Lean and M5Lean: no errors, with all `#guard_msgs` unchanged.
  - Each refinement alone: 0 mismatches in all three differentials.
