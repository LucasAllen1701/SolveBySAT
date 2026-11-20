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

## Milestone 7: evaluation (EVAL_PLAN.md)

The plan was read from `~/Downloads/EVAL_PLAN.md`. The copy at the repo root had been
moved to the Trash (identical md5).

### Pre-registration (fixed before the first run; constants in `Test/EvalCommon.lean`)

- **Source.** `Init` + `Std` of Lean 4.36.0. Measured import cost, peak RSS: `Init`
  456 MB, `Init`+`Std` 713 MB (668 / 1,167 modules, 79,778 theorems). Std fits, so both
  are used. Std does not import `Lean`.
- **Tier A filters, applied in order.** A theorem is dropped if:
  1. it is not a theorem, or its type is not a proposition;
  2. it has an internal auxiliary name: after stripping the `_private.…` prefix, some name
     component starts with `_` (`_proof_N`, `_simp_N_N`, `_auxLemma`, `_unary`, …);
  3. it is an equation lemma: `Meta.isEqnThm`, or last component `eq_N` / `eq_def` /
     `eq_unfold`;
  4. it is matcher-derived (some prefix of the name is a matcher), or a recursor;
  5. *(decision, beyond the plan's list)* it is compiler-generated: last component one of
     `inj`, `injEq`, `sizeOf_spec`, `congr_simp`, `induct`, `induct_unfolding`,
     `mutual_induct`, `fun_cases`, `fun_cases_unfolding`, `splitter`. These are
     auxiliary in the plan's sense, though not named in it. Names users also write, such
     as `ext`, `ext_iff`, `eta` and `elim`, are kept.

  *Decision:* private theorems with an ordinary name are user-written lemmas, so they are
  kept as goals and as H constants. The plan's "internal names" is read as names with an
  internal component.
- **Tier A sample.** 3,000, seed 70001 (partial Fisher–Yates with the splitmix64 of
  `Test/Util.lean`), over the remaining theorems in name order.
- **Oracle H (§2.3), in order.** A constant is dropped if it is:
  - a built-in rule;
  - auxiliary (rule 2 above, a matcher or under one, a recursor, `casesOn`/`recOn`/
    `brecOn`, `noConfusion`);
  - an instance (`Meta.isInstance`).

  Every constant whose type is a proposition is kept as `proof`. Any other constant is
  kept as `data` unless it is a type former (`isTypeFormerType`).
  *Deviation (fixed after inspecting the first extraction, before any coverage run):* the
  plan keeps "a theorem or axiom whose type is a proposition". Read literally, that drops
  the constructors of inductive propositions (`Eq.refl` 1,314 uses, `HEq.refl`,
  `Nonempty.intro`, `WF.*`) and Prop-typed definitions (`rfl`, 393 uses). These are the
  tactic's own test lemmas, so all proof constants are kept. The first version also
  mislabelled the axiom `Classical.choice : Nonempty α → α`, which is a data constant by
  SPEC 2.1.
  *Decision:* "the constants in its proof term" looks through internal auxiliary theorems
  (`_proof_N`, `_simp_N`, …). The elaborator abstracts these out of the proof, so they are
  part of it; without this, many oracle Hs would be nearly empty. The same expanded set is
  used to detect elimination constants. The auxiliary constants themselves are then
  dropped by the filter.
- **Elimination constants.** A recursor, an auxiliary recursor (`casesOn`, `recOn`,
  `brecOn`), a matcher, `Eq.mpr`, `Eq.rec`, `Eq.ndrec`, `Eq.subst`, `False.elim`,
  `absurd`.
- **Tier B.**
  - 1,000 theorems sampled from the Tier A sample, seed 70002.
  - Walk: λ-bodies (binders entered as local declarations), `let` (zeta: the value is
    walked, then the body with the value substituted), application heads and arguments,
    `mdata`, `proj`. Binder types are not walked. The visit budget is 20,000 nodes per
    theorem; a cut walk keeps the goals found so far, and cuts are counted.
  - A goal is a proof-valued application with at least one argument whose head is a
    constant or a local hypothesis. It is stored closed over its enclosing binders
    (`∀ ctx, T`) as (theorem, position in walk order). The harness rebuilds it with the
    same walker.
  - Dedupe by (closed goal type up to α-equivalence, H): first within the theorem, then
    against goals already taken from earlier theorems (name order). The per-theorem cap is
    10 (seeded sample, stream seed 70003); the total cap is 3,000 (seed 70004).
  - Sanity check: `isDefEq (inferType (fun ctx => e)) (∀ ctx, T)`.
  - Node estimate: proof-valued spines headed by a constant or a local hypothesis inside
    the oracle term.
- **Heartbeats** for corpus MetaM work: 400,000 (`maxHeartbeats`).
- **Coverage limits (§3, §5), fixed now.**
  - Nmax = 10.
  - Solver: CaDiCaL `-t 20` (wall-clock seconds; `cadical --help` in 2.1.2: `-t <sec>  set
    wall clock time limit`).
  - 120 s wall time per goal; each shard process under `ulimit -v` 2.5 GB.
  - The baseline heartbeat budget will be fixed in 7b, before the pilot.
- **Lean API checks (4.36.0).**
  - `Expr.getUsedConstants : Expr → Array Name`, `Meta.isInstance : Name → CoreM Bool`,
    `Meta.isEqnThm : Name → CoreM Bool`, `isMatcherCore`, `isRecCore`, `isAuxRecursor`,
    `isCasesOnRecursor`, `isNoConfusion`, `privateToUserName?`, `Expr.eqv` (the `BEq Expr`
    instance) all exist as expected.
  - `solve_by_elim`'s configuration is `Lean.Meta.SolveByElim.SolveByElimConfig`. Its depth
    is `maxDepth` (default 6 there, 50 in `ApplyRulesConfig`), and it also has `symm`,
    `exfalso`, `intro`, `constructor` and `backtracking` (all default true).
  - `exact?` and `apply?` are `Lean.Meta.LibrarySearch.librarySearch`.
  - `maxHeartbeats` is a field of `Core.Context.Cold`, not of `Core.Context`; it is still
    settable as `{ maxHeartbeats := … }`.
  - `importModules (loadExts := true)` needs `enableInitializersExecution` (unsafe) first.
- **Deviation: memory cap by cgroup, not `ulimit -v`.** `ulimit -v` limits address
  space, and the import reserves more than 4 GB of it for 707 MB of RSS (mapped `.olean`
  files, thread stacks). Under `ulimit -v` 2.5, 3 or 4 GB the process dies at start
  ("failed to create thread"); at 6 GB it runs. The cap therefore uses a user cgroup:
  `systemd-run --user --scope -p MemoryMax=2500M -p MemorySwapMax=0`, which limits
  resident memory (checked: a 600 MB allocation under `MemoryMax=300M` is killed). The
  2.5 GB figure is unchanged.

### 7a: corpus extraction (results)

`lake exe eval_corpus extract eval`, under the cgroup cap: 15 s, 778 MB peak. Two runs
give byte-identical `corpus_A.jsonl`, `corpus_B.jsonl` and `corpus_stats.txt`.

- **Tier A.** 117,002 constants in `Init`+`Std`. Dropped:
  - not a theorem: 37,224
  - internal auxiliary name: 22,888
  - equation lemma: 5,331
  - compiler-generated: 3,275
  - matcher-derived: 272

  48,012 remain, from which a sample of 3,000 is drawn. Of these, 1,176 (39%) have proofs
  that use an elimination constant.
- **Tier B.** 1,000 theorems; 13 walks cut at the budget; 0 walk errors. There are
  28,189 candidates. Dropped:
  - duplicates within a theorem: 14,217
  - duplicates of earlier theorems' goals: 22
  - over the per-theorem cap: 8,049

  5,901 goals from 993 theorems remain, giving a sample of 3,000. Of these, 452 have
  oracle terms that use an elimination constant. Sanity check failures: **0 / 3,000**.
  Node estimate: 1 for 668 goals, 2–10 for 1,689, over 10 for 643.
- **Oracle H.**
  - Tier A: 42,923 constants kept. Dropped: type formers 20,635, instances 11,276,
    auxiliary 3,248, built-in rules 663. 37 goals have an empty H.
  - Tier B: 27,707 kept. Dropped: type formers 17,929, instances 9,585, auxiliary 1,543,
    built-in rules 203. 23 goals have an empty H.
- **Observation (no action).** By §2.3's rule, function symbols of the statement such as
  `HAdd.hAdd`, `OfNat.ofNat` and `List.length` are kept as data constants, so they become
  data clauses. This enlarges H beyond the lemmas actually applied. The effect will show
  in 7b sizes.

### Pre-registration amendment (after 7a)

Follows EVAL_PLAN.md §10, which was added on 18 November 2026 after the 7a review and
before any coverage run. From here on the plan is read from the repo root copy (identical
to `~/Downloads/EVAL_PLAN(1).md`). §10.1 accepts the 7a deviations recorded above.

- **H_main (§10.2), implemented in `Eval.splitH`.**
  - Every proof constant is kept.
  - A data constant is kept only if it occurs (`getUsedConstants`) neither in the goal's
    closed type (Tier A: the theorem's type; Tier B: `∀ ctx, T`) nor in the type of any
    proof constant kept in that goal's H.
  - Each record also keeps the 7a set as `H_full`, plus `H_data_full` (its data
    constants) and `H_data_dropped` (data constants of `H_full` not in `H_main`).
  - The old field `H` is replaced by `H_main` and `H_full`. Main coverage runs use
    `H_main`; the R1b side run (300 Tier B goals) uses `H_full`.
- **Self-reference assertion.** No goal may have its own declaration (Tier A) or source
  theorem (Tier B) in H; if one does, it is removed and the record is flagged
  `self_in_H`. **Hits: 0 in Tier A, 0 in Tier B.**
- **Regenerated under the cgroup cap.** 15.7 s, 779 MB peak. Two runs are byte-identical
  (`corpus_A` 853c14cb7ed3, `corpus_B` cad3bf0fd2f4, `corpus_stats` 57719e399207).
  The goal sets are unchanged from 7a: the same 3,000 + 3,000 ids, and `H_full` equals
  7a's `H` on every goal.
  *Decision:* Tier B dedupe stays on (goal, `H_full`), as in 7a, so the accepted goal set
  does not move. Dedupe on (goal, `H_main`) would merge 0 further goals.
- **Sizes (min / median / p90 / max).**

  | tier | set | all | proof | data |
  | --- | --- | --- | --- | --- |
  | A | H_full | 0 / 10 / 30 / 129 | 0 / 4 / 16 / 91 | 0 / 5 / 16 / 67 |
  | A | H_main | 0 / 6 / 19 / 98 | 0 / 4 / 16 / 91 | 0 / 1 / 3 / 24 |
  | B | H_full | 0 / 7 / 18 / 84 | 0 / 2 / 9 / 51 | 0 / 4 / 11 / 37 |
  | B | H_main | 0 / 2 / 10 / 56 | 0 / 2 / 9 / 51 | 0 / 0 / 2 / 21 |

- **Data constants dropped.**
  - Tier A: 2,625 of 3,000 goals lost data constants (16,185 of 20,232 dropped).
  - Tier B: 2,642 goals lost data constants (13,616 of 14,908 dropped).
  - Most often dropped (Tier A): `OfNat.ofNat` 976, `Bool.true` 650, `HAdd.hAdd` 486,
    `Array.size` 339, `Option.some` 335, `Bool.false` 304, `List.cons` 270, `HSub.hSub`
    267, `Decidable.decide` 245, `Option.none` 223, `Neg.neg` 217, `ite` 201, `List.nil`
    190, `Nat.cast` 182, `HMul.hMul` 165, `Subtype.val` 156, `Std.DHashMap.Raw.buckets`
    155, `BEq.beq` 138, `List.length` 136, `Ord.mk` 135.
  - Tier B is nearly the same, with `HAppend.hAppend` in place of `Ord.mk`.
  - Goals with an empty `H_main`: A 50, B 62. With an empty `H_full`: A 37, B 23.
- **Data constants kept.** At least one is kept in 1,615 Tier A goals and 619 Tier B goals.
  Examples:
  - `A/Array.all_map'`: `Array.mk`
  - `A/List.mapM_subtype`: `List.cons`, `List.nil`
  - `A/Std.TreeMap.minKey!_modify_eq_minKey!`: `Std.TreeMap.inner`
  - `A/Std.IterM.TerminationMeasures.Finite.rel_of_skip`: `Option.some`,
    `Std.IterStep.successor`
  - `A/…Option.any_dmap`: `Option.none`
- **Open point for review (no change made).** Most kept data constants are not witnesses.
  They are polymorphic combinators whose result type is a type variable, so SPEC 2.1
  calls them data: `id` (A 955, B 450), `Eq.mpr` (809 / 200), `Eq.mp` (304 / 158),
  `False.elim`, `dite`. Of the goals that keep any data constant, 660 / 1,615 (A) and
  392 / 619 (B) keep *only* such combinators (`id`, `Eq.mp`, `Eq.mpr`, `Eq.ndrec`,
  `Eq.rec`, `False.elim`, `absurd`, `cast`, `dite`, `ite`).
  - `id` usually comes from `show`/type ascriptions in the proof.
  - `Eq.mpr`, `False.elim` and the others are elimination constants, which 3.3 rule 3
    already catches.

  The rule of §10.2 was applied as written.

### 7b step 0: combinator rules of EVAL_PLAN §10.4 (corpus)

- **Implemented in `Eval.splitH`.** After the §10.2 data rule, `id` (transparent) and
  every elimination constant are removed from `H_main` and listed in `H_main_removed`
  with the reason (`id` or `elimination`).
  - Elimination constants here are those of §2.1, plus `Eq.mp`, `cast`, `dite` and `ite`
    when they survive the data rule. That is exactly when they are still in `H_main`
    after it, so an `ite` that occurs in the statement or in a kept lemma's type is never
    touched.
  - The four §10.4 constants are added to the record's `elim` list, and therefore to
    `uses_elim`.
  - `H_full` is unchanged: it is the 7a set used by R1b.
- **Compiler check.** Each of the 8 distinct constants removed in the corpus (`id`,
  `Eq.mpr`, `Eq.mp`, `False.elim`, `dite`, `absurd`, `ite`, `cast`), compiled alone with
  the goal `True`, is rejected, so the change affects classification only. **The compiler
  accepts none of them.** In every case the message is "the result type of `c` … has the
  clause variable … as its head symbol".
- **Regenerated under the cgroup cap.** 16.5 s, 777 MB peak. Two runs are byte-identical
  (`corpus_A` e108aab72d74, `corpus_B` 10a93687d7fe, `corpus_stats` a332af976598). Goal ids
  and `H_full` are unchanged.
- **Removed by §10.4.**
  - Tier A: 2,257 removals in 1,099 goals: `id` 955, `Eq.mpr` 809, `Eq.mp` 304, `dite` 91,
    `False.elim` 88, `absurd` 6, `ite` 2, `cast` 2.
  - Tier B: 871 removals in 546 goals: `id` 450, `Eq.mpr` 200, `Eq.mp` 158, `False.elim` 49,
    `dite` 14.
- **New `H_main` sizes (min / median / p90 / max).**

  | tier | all | proof | data |
  | --- | --- | --- | --- |
  | A | 0 / 5 / 17 / 94 (was 0 / 6 / 19 / 98) | 0 / 4 / 16 / 91 | 0 / 0 / 2 / 21 |
  | B | 0 / 2 / 10 / 53 (was 0 / 2 / 10 / 56) | 0 / 2 / 9 / 51 | 0 / 0 / 0 / 19 |

  - Goals keeping at least one data constant: A 955, B 227.
  - Goals with an empty `H_main`: A 51, B 66.
  - The most frequent data constants left are witness-like: `List.nil`,
    `Lean.Omega.LinearCombo.mk`, `Subtype.mk`, `Array.mk`, `…TreeMap.inner`,
    `Option.none`.
- **New elimination counts.**
  - Tier A: 1,269 (was 1,176). The 93 new ones are goals whose only elimination is one
    of the four §10.4 constants (`Eq.mp` 304 uses, `dite` 91, `ite` 2, `cast` 2).
  - Tier B: 534 (was 452), with 82 new (`Eq.mp` 158, `dite` 14).

### 7b: the coverage harness (EVAL_PLAN §3.1, §3.2, §5, §10.3, §10.4)

- **Files.**
  - `Test/EvalRun.lean` (`lake exe eval_run`): one process per shard.
  - `Test/eval_driver.py`: spec files, shards, cap, watchdog, crash records, resume.
  - `Test/EvalNamed.lean`: the SPEC 9.1 named tests as closed goals.
  - `Test/eval_pilot.py`: the pilot report and projection.
  - Spec files: `eval/specs_{named,pilot,full}.jsonl`. They are deterministic and contain
    120 pilot specs and 6,300 full-run specs (3,000 A, 3,000 B, 300 R1b).
- **The tactic is unchanged.** The harness calls the library's `compile`, `encode` (default
  `EncodeOptions`, as the tactic) and `decode`. Its only own code on that path is the solver
  call. That call writes the same DIMACS file and runs CaDiCaL with `-q -t <s>` through
  `Test/memrun.py`, which gives the solver's peak RSS. It parses the output with the
  library's `parseSolverOutput` and checks the model against every clause.
- **Per goal (§3.1).**
  1. `compile goal []`; on failure, `goal_rejected(reason)`.
  2. `compile goal [c]` for each c in H (`H_main`, or `H_full` for R1b), recording
     accepted and rejected constants with the message.
  3. `compile goal accepted`, then N = 1 … 10.
     - The loop has 120 s in total, and each solver call is limited to
       `min(20 s, remaining)`. It stops at the first timeout or memout.
     - SAT is decoded, checked with `isDefEq` and kernel-checked (`Kernel.Environment.addDecl`
       on a copy of the environment). A failure is a `decoder_bug` and stops the run (exit 3).
     - The documented-limitation message gives `limitation`.
  4. At the final N (also for `no_proof_le_Nmax`): variables, clauses, per-family counts,
     encode ms, solve s and solver peak MB. Each N's sizes and times are also logged.
- **Outcomes.** `proved(N)`, `no_proof_le_Nmax`, `timeout(N, solver|loop)`,
  `memout(N, solver|spawn)`, `limitation`, `goal_rejected`, `compile_error`,
  `crash(shard, oom|watchdog|signal|unknown)`. `decoder_bug`, `solver_error` and
  `harness_error` stop the run.
  *Decision:* `memout(N, spawn)` covers ENOMEM when spawning the solver near the cap. That
  is a resource limit, not a harness error, and it was seen in testing.
- **Baselines (§3.2, §10.3, §10.4).** Each runs from a fresh state (`saveState`/`restore`)
  with 200,000 heartbeats (`maxHeartbeats`, `withCurrHeartbeats`), with its wall time
  recorded. Tier B goals are run after `introNP nctx`, in the goal's context.
  - `solve_by_elim` reproduces `solve_by_elim [H]` exactly: `mkAssumptionSet` gives H plus
    the defaults `rfl`, `trivial`, `congrFun`, `congrArg` and the local hypotheses.
    Like-for-like is `{ maxDepth := 10, symm := false, exfalso := false }` (intro and
    constructor on); default is `{ maxDepth := 10 }`.
    *Decision:* the baselines get all of `H_main`, not only the constants our compiler
    accepts.
  - `exact?` / `apply?` are one call, since they are the same search in 4.36 (`intros`, then
    `librarySearch` with `solveByElim` depth 6, `star := true`, `all := false`). The result
    `none` means closed; `some []` is none; otherwise `exact?` has not closed and `apply?`
    is `partial`, with the suggestion count and the fewest remaining goals.
  - **`librarySearch` cannot exclude constants.** Candidates come from the discrimination
    tree; neither the `tactic` nor the `allowFailure` hook sees the lemma. So each closure
    is `closed_self` (the term mentions the goal's own declaration or source theorem) or
    `closed_other` (§10.4).
  - Heartbeat and recursion-depth exhaustion are outcomes (`heartbeats`, `max_rec_depth`).
    This needs `tryCatchRuntimeEx`: in 4.36 a plain `try … catch` in `MetaM` does not catch
    runtime exceptions. The first version missed this and stopped a test run with a
    harness error.
  - Warm-up: one untimed `librarySearch` on `True` per shard process, before its first
    goal; time and RSS go to `warmup.jsonl`. It costs about 0.6 s, with RSS 730 → 905 MB.
- **Crashes, watchdog, resume (§10.3, §10.4).**
  - Before each goal the shard appends a started marker, and before each N a progress
    marker `{key, N}`. A goal with markers and no result is `crash(shard, cause)` with
    `last_N` and `elapsed_s`, and the shard restarts on the remaining goals.
  - The cause is `watchdog` (the driver killed the shard after 300 s on one goal), `oom`
    (the run slice's `memory.events` `oom_kill` count rose), `signal N`, or `unknown` (a
    marker found when a new driver starts).
  - Results are appended one line at a time. A trailing partial line is dropped before
    every shard start, and a rerun skips every key with a result.
- **Memory incident (18 November, before the fixes below).** Two test runs overlapped. A
  test command was killed, but its driver's shard survived, and the next test started a
  second run. Two 2.5 GB-capped shards plus VS Code exhausted RAM: the journal shows a
  *global* OOM that killed VS Code's electron processes and the agent's shell, and the
  machine was restarted. No data was affected. Fixes:
  - one driver at a time (`eval/.driver.lock`, `flock`);
  - shards and the cgroup keeper get `PR_SET_PDEATHSIG = SIGKILL`, so they die with the
    driver;
  - *deviation from the 7a record:* the 2.5 GB cap is now on the whole per-run slice
    (`systemctl --user set-property --runtime evalrunPID.slice MemoryMax=2500M
    MemorySwapMax=0`), so shard, solver and keeper share one cap. Per-shard scopes remain
    inside it;
  - solver inputs go to `OUTDIR/tmp` on disk (`TMPDIR`), cleared after every shard: `/tmp`
    is a tmpfs, so files left by killed solvers would hold RAM. Lean's `createTempFile`
    follows `TMPDIR` (checked).
- **Acceptance before the pilot.**
  - **Named tests:** all 36 cases of L1 to D7 (including the two-part rows, G2 with the
    static filter off, and U1 with `forgetTypes`) give the test suite's result through the
    harness. Every `min k` is proved at exactly k; F1–F3, G2, A3a, D2b, D5 and D6 give
    `no_proof_le_Nmax` (no proof up to 10, so none at 6); F4 is proved at 5 (none at 4);
    U1 gives `limitation`.
  - **Resume:** 12 Tier A specs in shards of 5.
    - (a) SIGKILL to the shard alone, during goal 3: `crash(shard, signal 9)`, and the
      shard restarts.
    - (b) SIGKILL to the driver during goal 8: its shard died with it. The rerun recorded
      that goal as `crash(shard, unknown)` and finished the rest.
    - Result: 12 specs, 12 distinct started keys, 12 result lines, 0 missing, 0
      duplicated, 0 extra.
  - **Forced OOM:** `A/Array.mem_of_mem_erase` under a 1,200 MB cap gives
    `crash(shard, oom)` at `last_N` 6, after the warm-up (peak 903 MB). At the real 2,500 MB
    cap it also gives `crash(shard, oom)`, at N = 9 after 33 s. In the resume test, 8 of 12
    Tier A goals (|H_main| 8–9) ran out of memory at 2.5 GB.
- **Fixed before the pilot (pre-registered).**
  - Shard size 50.
  - R1b sample: 300 Tier B goals, `random.Random(70005).sample` over corpus order.
  - Pilot: 50 Tier A goals (seed 70006), 50 Tier B goals (seed 70007), and the first 20 of
    the R1b sample.
  - The limits are those above.
- **Pilot interruption: CaDiCaL's timeout output (spec check corrected).** At its `-t`
  limit, CaDiCaL 2.1.2 prints the *comment* line `c UNKNOWN` (not `s UNKNOWN`) and exits 0.
  This was checked with a 13-into-12 pigeonhole under `-t 1`, with and without `-q`. The
  harness looked for `s UNKNOWN`, so the first solver timeout of the pilot
  (`main:B/UInt16.sizeOf/1`, 20.0 s) was reported as `solver_error` and stopped the run
  after 81 of 120 goals.
  - Fixed: exit 0 with `UNKNOWN` in the output is a timeout.
  - Only that goal was affected, because any earlier timeout would have stopped the run
    the same way. Its result line and markers were removed, and the pilot was resumed;
    the 80 results before it stand.
  - No filter or limit changed.

### 7b: pilot (120 goals; `eval/pilot/`, report by `Test/eval_pilot.py eval/pilot`)

- **Completion.** 120 of 120 results. 0 `decoder_bug`, 0 harness or solver errors after the
  timeout fix above. Wall time 33.4 min in total (two driver runs).
- **Outcomes.**

  | run | tier | proved | no proof ≤ 10 | crash (oom) | goal rejected | timeout |
  | --- | --- | --- | --- | --- | --- | --- |
  | main | A (50) | 2 | 29 | 13 | 6 | 0 |
  | main | B (50) | 16 | 23 | 7 | 3 | 1 (solver) |
  | R1b | B (20) | 2 | 11 | 7 | 0 | 0 |

  Proofs were found at N = 1 (9), 2 (6), 3 (3), 4 (1), 6 (1). No watchdog crash occurred:
  every crash was the 2.5 GB cap.
- **Baselines** (only for goals whose shard did not crash: 37 of 50 in Tier A, 43 of 50 in
  Tier B).
  - `solve_by_elim`, like-for-like and default alike: Tier A closed 12, heartbeats 12,
    failed 12, max_rec_depth 1; Tier B closed 29, heartbeats 8, failed 6.
  - `exact?`: Tier A `closed_self` 36, `closed_other` 1; Tier B `closed_other` 21, `none`
    17, `closed_self` 5. `apply?`: the same closures, with `partial` in place of `none`.
- **Warm-up.** 23 shard starts (one per crash restart); 589 ms on average (max 612); RSS
  729 → 905 MB.
- **Time.** About 16 s per goal on average, plus 0.8 s overhead per goal. By |H_main|
  bucket: 0–5 about 7–8 s (13 s in R1b with H_full); 6–10 32–44 s; 11–20 30–50 s.
- **Projection of the full run (6,300 goals): 30.6 h.**
  - By run and tier: main A 15.4 h, main B 13.9 h, R1b 1.3 h.
  - By outcome:
    - main A: no proof 8.2 h, oom 4.9 h, rejected 1.8 h, proved 0.6 h;
    - main B: no proof 7.0 h, oom 3.6 h, timeout 1.8 h, rejected 1.4 h, proved 0.1 h;
    - R1b: oom 0.8 h, no proof 0.5 h.
  - This is over the 8 h of §5, so a sample-size reduction is proposed and awaits approval
    (§10.3). Nothing has been tuned on the pilot.
- **Gap found by the pilot (not yet changed).** A shard OOM during the `solve_by_sat` N loop
  also loses that goal's baselines, because they run after it. That is 13 of 50 Tier A
  goals and 7 of 50 Tier B goals in the pilot, so R4 would miss them. Proposed fix: run the
  baselines first. They take milliseconds and start from a fresh state, so the order
  changes no result.

### 7b: full run on the test machine (EVAL_PLAN §10.5)

EVAL_PLAN §10.5 was added on 18 November 2026. It sets out the decisions taken after the
pilot: no sample reduction, baselines first, like-for-like `solve_by_elim` without default
lemmas, a rule for parallel shards, calibration, and a push after each shard.

- **Test machine (recorded 19 November 2026).**
  - CPU: Intel Core i7-10510U @ 1.80 GHz, 4 physical cores (8 threads), 1 socket.
  - RAM: 7,735 MiB (7.55 GiB) in total, about 2.2 GiB already in use before any run
    (mostly a Firefox session, about 1.6 GiB, plus the Claude Code session).
  - Swap: 2 GiB partition (`/dev/nvme0n1p2`). The original machine had none. The
    evaluation slices set `MemorySwapMax=0`, so the cap still bounds resident memory.
  - OS: Arch Linux, kernel 7.3.4-arch1-2; systemd 262 (262.2-1-arch).
  - cgroup v2; the user manager delegates `cpu memory pids`.
  - Disk: 419 GB free on `/`. `/tmp` is a tmpfs (3.8 GiB), so solver inputs stay in
    `OUTDIR/tmp` as before.
- **Parallel shards (§10.5 decision 4).** The rule allows
  P ≤ min(4 − 1, ⌊(7.55 − 2) / 2.6⌋) = min(3, 2) = 2. Counting RAM as 8.11 GB gives the
  same. *Decision (owner):* **P = 1**. With about 2.2 GB already in use, two 2.5 GB shards
  would leave too little headroom. The parallel-mode resume and OOM checks are therefore
  not needed.
- **Environment check failed at first: the build. Fixed by setting `vm.overcommit_memory = 1` (deviation).**
  - After the toolchain was installed, `lake build eval_corpus eval_run` sometimes failed:
    `lake` could not spawn `clang` and `lean` ("resource exhausted (error code: 12, not
    enough memory)"). A clean rebuild reproduced it with 6 failed spawns, with about
    4.4 GiB free, no cgroup limit and `ulimit -v` unlimited.
  - Cause, from the kernel log: `__vm_enough_memory: … comm: lake, bytes: 10737459200 not
    enough memory for the allocation` (also 11811205120). In heuristic mode
    (`vm.overcommit_memory = 0`) the kernel refuses any single commit larger than RAM +
    swap, which is 9.55 GiB here. `lake` holds about 10 to 11 GiB of accounted private
    arenas (1 to 4 GiB each, flag `ac` in `smaps`) for about 128 MB resident. When it
    forks to spawn a child, that whole amount is charged at once and refused. This is
    reserved address space, not memory pressure.
  - The development machine had the same failure: the intermittent `lake` ENOMEM of
    milestone 5 and the solver-spawn ENOMEM of milestone 1. It most likely also explains
    the spawn ENOMEM seen there in 7b testing. The pilot has 0 `memout(N, spawn)`
    outcomes, so no pilot result depends on it.
  - The shard is also a forking process with a large reserved address space, so under
    mode 0 `memout(N, spawn)` would measure a kernel heuristic, not the pre-registered
    2.5 GB cap.
  - *Fix (owner-approved, 19 November 2026):* `vm.overcommit_memory = 1`, made persistent
    in `/etc/sysctl.d/99-solvebysat-eval.conf`. Resident memory is still bounded by the
    cgroup slices, so the cap is unchanged. Two clean rebuilds after the change: 0 ENOMEM,
    0 kernel refusals. No code, filter or limit changed.
- **Environment checks (after the fix), 19 November 2026. All pass.**
  - Build: two clean rebuilds, `lake build` then `lake build eval_corpus eval_run`, give 0
    errors. *Gap in CLAUDE.md's check list:* the named harness also needs
    `lake build Test.EvalNamed`. It is loaded at run time, not linked, so a clean build
    does not produce it, and the first named run stopped with "object file … EvalNamed.olean
    does not exist". CLAUDE.md now lists it.
  - Corpus determinism: the rebuild under the cap (16.1 s, 788 MB peak) is byte-identical
    after the header: `corpus_A` 82c42f9261ad, `corpus_B` e74e5dd25bd8, `corpus_stats`
    a332af976598.
  - `Test/run_all.sh`: exit 0 in 15 min 17 s (log `eval/calib/run_all.log`). M0 902/902;
    M1 19/19 (differentials: 7,500 comparisons with 2,551 provable and 0 mismatches; with
    binders 7,500 / 2,346 / 0; with data 15,000 / 3,854 / 0); M4 unit 4/4; M5 10/10; every
    `#guard_msgs` and expected-error check as before.
  - Named cases through the harness, on the committed (pre-step-3) harness: 36 of 36
    agree with the test suite. Every `min k` is proved at k; F1–F3, G2, G2-nostatic, A3a,
    D2b, D5 and D6 give `no_proof_le_Nmax`; F4 is proved at 5; U1 gives `limitation`.
  - Memory cap: `systemd-run --user --scope -p MemoryMax=300M -p MemorySwapMax=0` kills a
    600 MB allocation (exit 137) and lets a 100 MB one finish.
- **Harness changes (step 3; EVAL_PLAN §10.5 decisions 2–4).** The tactic, encoder,
  decoder, corpus, filters and limits are unchanged.
  - *Baselines first (decision 2).* Per goal, `Test/EvalRun.lean` now runs the three
    baselines, then the `solve_by_sat` N loop.
    - Each baseline, and the N loop after them, is its own `runMeta` call, which rebuilds
      the goal. Each therefore starts from a fresh Core and Meta state.
      *Decision:* this is stricter than `saveState`/`restore`, because in 4.36
      `SavedState.restore` keeps `Meta.Cache` ("`Meta.Cache` is kept, except for the type
      class resolution cache"). Running the baselines first in a shared MetaM could then
      warm caches for the N loop.
    - The shard records `rss_before_baselines_mb`, `rss_after_baselines_mb` and
      `hwm_after_baselines_mb`.
    - The baselines are written to `OUTDIR/baselines.jsonl` as soon as they finish. The
      driver merges that line into the goal's crash record (`oom`, `watchdog`, `signal`,
      or `unknown` on resume). *Found while testing:* without this, the baselines lived
      only in the shard's final result line, so a crash in the N loop still lost them.
      The first version of the change had this gap; the forced-OOM test showed it.
    - Started markers also carry the phase (`{key, phase: baselines|sat}`), and crash
      records get `phase`. A crash during the baselines (`phase: baselines`) loses the
      N loop instead.
    - Baselines no longer depend on the N loop's result. Before, a decoder bug skipped
      them; a decoder bug still stops the run.
  - *Like-for-like `solve_by_elim` (decision 3).* The lemmas are `H_main` alone, with the
    local hypotheses, `symm := false`, `exfalso := false`, `maxDepth := 10`. The default
    configuration still adds `rfl`, `trivial`, `congrFun` and `congrArg`.
    *API check (4.36.0):* `mkAssumptionSet (noDefaults := true)`, which is `only`, also
    drops the local hypotheses (`if noDefaults && !star then pure []`). So it is called
    with `false`, and the four defaults are left out of the lemma list instead.
  - *Header (decision 4).* `header.json` now records `parallel_shards` (1), `machine`
    (CPU, physical cores, threads, RAM, swap, OS, kernel, systemd,
    `vm_overcommit_memory`), `min_free_mb`, the baseline order and the like-for-like
    definition. P = 1, so there is no parallel mode and no parallel-mode checks.
  - *Stop conditions of the full-run instructions, in `Test/eval_driver.py`.*
    - Exit 7: the memory outside the run slice falls below 1,024 MB. This is measured as
      `MemAvailable` minus what the slice may still take (cap − `memory.current`), so it
      counts the slice at its full cap and only falls when the rest of the machine
      grows. At the start it is about 2,860 MB. The shard is killed, the unfinished
      goal's markers are removed so that a rerun runs it again (an external stop, not a
      property of the goal), and the stop goes to `driver.jsonl`.
    - Exit 8: a crash cause other than `oom` or `watchdog` occurs a second time in OUTDIR.
  - *Publishing (decision 6).*
    - `--after-shard CMD` runs `Test/eval_publish.sh` after each completed shard. That
      script writes `STATUS.md` with `Test/eval_status.py`, commits OUTDIR and pushes to
      `eval-m7` (3 tries; a failed push is retried after the next shard).
    - `Test/eval_full.sh` is the detached wrapper. On a stop it appends a short record to
      NOTES.md and pushes; on completion it appends the outcome tables.
    - The status projection uses the pilot's per-stratum mean times until a stratum has 5
      finished goals in the full run, plus the pilot's 0.8 s overhead per goal, and shows
      the observed throughput too.
- **Acceptance after the changes.**
  - *Resume* (`eval/test_runs/resume_test.sh`, 12 Tier A specs, shards of 5): (a) SIGKILL
    to the shard gives `crash(shard, signal 9)` and a restart; (b) SIGKILL to the driver
    kills its shard too ("still alive? no"), and the rerun records `crash(shard, unknown)`.
    12 specs, 12 distinct started keys, 12 result lines, 0 missing, 0 duplicated,
    0 extra. Every crash record has its baselines.
  - *Forced OOM* (`eval/test_runs/oom_test.sh`): at a 1,200 MB cap, `crash(shard, oom)` at
    `last_N` 6, as on the development machine. At the real 2,500 MB cap, `crash(shard, oom)`
    at `last_N` 10. The development machine gave 9, and so did a run here earlier today
    with the first version of the change. So the exact N at which this goal reaches the
    cap varies by one between runs. Both records carry the baselines.
  - *Stops:* forced low-memory threshold before any goal (exit 7, no markers left); during
    a goal, with 1.5 GB allocated outside the slice and the threshold at 2,000 MB
    (headroom 1,346 MB, exit 7, that goal's markers removed, `unfinished_rerun` logged);
    two SIGTERMs to the shard (two `crash(shard, signal 15)`, then exit 8). Outputs are
    under `eval/test_runs/stop_*`.
- **Calibration (§10.5 decision 5), 19 November 2026. Passed; no stop condition.**
  - Test suite: `Test/run_all.sh`, exit 0 (above).
  - Named cases on the changed harness: 36 of 36 identical to the run on the committed
    harness (`eval/calib/named/`).
  - Pilot again: 120 goals with the new baseline order (`eval/calib/pilot/`), 38.0 min
    wall in one driver run. The goal-by-goal comparison with the development machine's
    `eval/pilot/` is `eval/calib/compare.txt`, from `Test/eval_compare.py`.
    - 0 decoder bugs, solver errors or harness errors. **0 different proved N.** The same
      20 goals are proved, at the same N.
    - 117 of 120 `solve_by_sat` outcomes are identical. Three resource differences, all
      at a limit, with identical CNFs at every N:
      - `main:B/List.foldl_push_eq_append/4` (|H| 4): `crash(oom)` at N = 10 on the
        development machine; `no_proof_le_Nmax` here. N = 10 has 9.93 M clauses; the
        solver's peak is 1,324 MB and the shard's high-water mark 1,801 MB, so the slice
        total sits at the 2,500 MB cap and the outcome flips with small changes in
        timing or memory.
      - `main:B/String.Slice.sliceTo_sliceTo/12`: `crash(oom)` with `last_N` 7 there, 8
        here. Same cause; `A/Array.mem_of_mem_erase` in the OOM test moved 9 → 10 the
        same way.
      - `main:B/UInt16.sizeOf/1` (|H| 16): solver timeout at N = 10 there, at N = 9 here.
        Its N = 9 solve took 19.6 s there, under the 20 s limit; this machine is slower
        (N = 8: 9.5 s there, 11.1 s here; median loop time over the 63 goals that are
        `no_proof_le_Nmax` on both is 1.11× there).
    - Goals that hit a time limit: 1 (`UInt16.sizeOf/1`), as in the development pilot.
    - Baselines: now present for all 100 main-run goals (80 in the development pilot,
      where shard OOMs lost 20). `sbe_default` and `library_search` are identical on every
      goal that has them in both runs. `sbe_like` changed on 4 goals, as decision 3
      expects (it lost `rfl`, `trivial`, `congrFun` and `congrArg`): `heartbeats → closed`
      3, `heartbeats → failed` 1. All 26 crashes are in the N loop (`phase: sat`); none
      occurred during the baselines. Shard RSS grows over the baselines by a median of 0
      and at most 79 MB.
    - Outcomes here: main A proved 2, no proof 29, crash(oom) 13, goal rejected 6; main B
      proved 16, no proof 24, crash(oom) 6, goal rejected 3, timeout(solver) 1; R1b
      proved 2, no proof 11, crash(oom) 7.
    - Warm-up: 21 shard starts, 727 ms on average, RSS 741 → 911 MB.
  - Projection for the full run on this machine (`Test/eval_pilot.py eval/calib/pilot`):
    **35.5 h** (main A 19.4 h, main B 14.8 h, R1b 1.4 h), against 30.6 h on the
    development machine.
- **Full run started** 19 November 2026, 10:15, detached (`setsid nohup Test/eval_full.sh`),
  P = 1, results in `eval/full/`.
- **Commit author rewrite (owner-approved, 19 November).** This machine's global git
  config used a private address, so GitHub refused the pushes (GH007, email privacy).
  The repo now sets `user.email` to the noreply address of the earlier history. The 4
  unpushed commits were re-created with that address: same trees, messages and dates,
  built with `commit-tree`/`update-ref` so that the running driver's files were never
  touched. Old → new hashes: 445f29a → 977c867, 1b777b2 → c81e323, 6ef9ea2 → c3a3ec8,
  e9f77e7 → ef0c75b. `eval/full/header.json` records the start commit as `6ef9ea2`, which
  is now `c3a3ec8` (same tree).
- **Full run stopped (recorded automatically by `Test/eval_full.sh`, 2026-11-19 17:00:25).**
  Driver exit 3: Driver ended: STOPPED: decoder bug or solver error (see results.jsonl)..
  Last driver output:
  ```
  crash(shard, oom) on main:A/List.getElem_scanl
  crash(shard, oom) on main:A/List.getLast?_drop
  STOP: "decoder_bug" on main:A/List.getLast_eq_head_reverse: "solve_by_sat: decoder failed on a satisfiable CNF (bug).\nskeleton: fun α#0 l#1 h => Eq.symm(List.head_reverse(fun a0@g5 => h(List.reverse_eq_nil_iff.mp(a0@g5))))\nerror: Tactic `introN` failed: The metavariable below has already been assigned\n\nNote: This likely indicates an internal error in this tactic or a prior one\n\ncase h\nα✝ : Type u_1\nl✝ : List α✝\nh✝ : l✝ = [] → False\n⊢ l✝.reverse = [] → False"
  STOP: shard exited with 3 (decoder bug or solver error; see results.jsonl)
  === driver exit 3 2026-11-19 17:00:25
  ```
  - Goals done: 774 of 6300 - Crashes by cause: oom 233 

### 7b: decoder bug in the full run (`List.getLast_eq_head_reverse`), found and fixed

- **Stop.** The full run stopped at 17:00 on 19 November after 774 of 6,300 goals (all Tier
  A), with `decoder_bug` on `main:A/List.getLast_eq_head_reverse`. At N = 5 (429,047
  variables, 3,120,313 clauses) the CNF was SAT, with skeleton
  `fun α l h => Eq.symm (List.head_reverse (fun a0 => h (List.reverse_eq_nil_iff.mp a0)))`.
  The replay failed: "`introN` failed: The metavariable below has already been
  assigned", on goal `l.reverse = [] → False`.
- **Reproduced with the tactic alone**, outside the harness:
  `solve_by_sat [Eq.symm, List.head_reverse, List.reverse_eq_nil_iff] (nodes := 5)` on
  `type_of% @List.getLast_eq_head_reverse` gives the same error and skeleton (75 s). A
  3-node problem reproduces it in 1.5 s: `lem : ∀ n (h : P n → False), f n h = 0`, with
  hypothesis `hp : P n → False`, on the goal `f n hp = 0`.
- **Cause: the decoder (SPEC §8 replay), not the compiler or the encoder.**
  - `List.head_reverse : (h : l.reverse ≠ []) → l.reverse.head h = l.getLast _` has a
    head that mentions its own premise.
  - A proof inside a term compiles to `⟨proof⟩` (SPEC §4.4). SPEC §2 rejects a premise
    mentioned in a *binder type*, but not one mentioned in the *head*. So the clause is
    in the class, and the encoding is right: `⟨proof⟩` in the head matches `⟨proof⟩` in
    the target.
  - The replay opens the premise as a natural metavariable `?h`. Unifying the head with
    the target (`… head ?h =?= … head (_proof_1 h✝)`) then *assigns* `?h` to the target's
    proof. Replaying the child on `?h` afterwards breaks SPEC §8's assumption that each
    premise is filled by its child.
  - When the premise has binders, `introN` refuses the assigned metavariable: this bug.
    When it has none, `introN 0` does not check, and the child's `assign` silently
    overwrote the earlier assignment. That gave a correct term by proof irrelevance,
    which is why no earlier test caught it.
  - The compiler's `⟨proof⟩` erasure and the encoder are unchanged and correct. Only the
    decoder is at fault: it relied on an invariant (premise metavariables are unassigned
    until their child is replayed) that the class does not guarantee.
- **Fix (`SolveBySat/Decode.lean`, `instantiateClause`).** Premise metavariables, both
  binder premises and the `Iff.mp`/`Iff.mpr` premise, are created as synthetic opaque.
  - Head unification can then no longer assign them. It compares a premise with the
    target's proof by proof irrelevance, which still unifies their *types*, so clause
    variables determined through the premise are still determined.
  - Only the child fills the premise. `MVarId.assign`, used by the replay, and `introN`
    both work on synthetic opaque metavariables.
  - Built-in rules (`And.intro` and the others) are unaffected: their premises never
    occur in a head.
  - Deviation from the SPEC §8 text: "open its binders as metavariables" now reads
    "… premises as synthetic opaque metavariables".
- **Regression tests: `Test/M7Lean.lean`, added to `Test/run_all.sh` and the
  `LeanTests` lib.** Each success has its minimality check.
  - R1a: a premise with a binder, 3 nodes, with the printed term
    `fun P f lem n hp => lem n fun a => hp a`.
  - R1b: the same with `¬`.
  - R1c: a premise without binders, 2 nodes.
  - R1d: a premise without binders, where the target holds a different proof (`q r`)
    from the child's (`hq`). The term `lem n hq` is accepted by the kernel by proof
    irrelevance.
  - R1e: the full-run goal itself, at 5 nodes, with no proof at 4 (about 2 min).
  - With the fix reverted, R1a, R1b and R1e fail with "decoder failed on a satisfiable
    CNF". R1c and R1d pass either way: they guard the silent-overwrite path.
- **Regression (after the fix):** `Test/run_all.sh` exit 0 in 17 min 21 s
  (`eval/calib/run_all_fix.log`). M0 902/902; M1 19/19 (differentials 7,500 / 2,551 / 0
  mismatches; with binders 7,500 / 2,346 / 0); M4 unit 4/4; M5 10/10 (with data
  15,000 / 3,854 / 0); `Test/M2.lean`, `M3.lean`, `M4Lean.lean`, `M5Lean.lean` and the
  new `M7Lean.lean` all pass. Named cases through the harness: 36 of 36 identical to
  before the fix (outcome, N and skeleton; `eval/fix_check/named/`).
- **Effect on results so far.** The changed code runs only after a SAT answer, and the N
  loop stops at its first SAT. So the only results it can affect are the goals that
  reached SAT. The CNFs, solver calls, crashes, timeouts, rejections and baselines are
  untouched. Check (`eval/fix_check/`, `compare.txt`): the 64 full-run goals that
  reached SAT (63 `proved` plus the bug) and the 20 proved goals of the calibration pilot
  were rerun with the fix. That is 83 distinct goals; `A/Int16.le_of_lt` is in both sets.
  - 82 of 83 are identical in outcome, N and skeleton.
  - The bug goal is now `proved` at N = 5.
  - No goal changes N or skeleton.
  - The 773 other results of `eval/full/` and the calibration therefore stand as
    computed.
- **Not yet resumed: waiting for the owner.** Proposal: remove the `decoder_bug` line and
  that goal's markers from `eval/full/`, as was done in the pilot for the `solver_error`
  goal, so that the resumed run recomputes it with the fix. Then resume
  `Test/eval_full.sh`, recording the fix commit as the commit of the resumed part.
- **Resumed (owner-approved, 19 November 2026).** The `decoder_bug` result line of
  `main:A/List.getLast_eq_head_reverse`, its 8 started and progress markers and its
  baselines line were removed from `eval/full/`. The removed lines stay in git history at
  `ef9805f`. `results.jsonl` went from 774 to 773 lines. The run resumed with the same
  wrapper (`Test/eval_full.sh`) on commit `2394acf`, which has the decoder fix.
  `eval/full/header.json` is kept as written at the start: commit `6ef9ea2`, now
  `c3a3ec8`. Results written after the resume come from the fixed decoder; per the check
  above, that differs from the start commit only on goals whose CNF is SAT, and there
  only in being able to decode the case of this bug. No filter, seed or limit changed.
  - In the resumed run, `main:A/List.getLast_eq_head_reverse` is `proved` at N = 5, with
    the skeleton the failed decode had reported.
  - On resume, the driver numbers the remaining goals' shards from `shard_0000.jsonl`
    again, overwriting the first part's shard spec lists. These are input lists only, and
    the originals are in git history at `342d184`. Shard counts in `STATUS.md` are
    computed from the full spec order, not from these files.
- **Full run stopped (recorded automatically by `Test/eval_full.sh`, 2026-11-20 15:38:38).**
  Driver exit 3: Driver ended: STOPPED: decoder bug or solver error (see results.jsonl)..
  Last driver output:
  ```
  crash(shard, oom) on main:B/Nat.pos_of_lt_mul_left/1
  crash(shard, oom) on main:B/Nat.pos_of_lt_mul_left/2
  STOP: "decoder_bug" on main:B/Nat.pred_eq_self_iff/22: "solve_by_sat: decoder failed on a satisfiable CNF (bug).\nskeleton: fun n#0 n#1 x_0#2 x_0#3 h2@g0 a5@g0 => Ne.symm(fun a0@g2 => Nat.succ_ne_self(a0@g2), a5@g0)\nerror: node 3: the head ?a = ?b of a0@g2 does not unify with the target Nat.succ ?n = ?n"
  STOP: shard exited with 3 (decoder bug or solver error; see results.jsonl)
  === driver exit 3 2026-11-20 15:38:37
  ```
  - Goals done: 4246 of 6300 - Crashes by cause: oom 1010 
