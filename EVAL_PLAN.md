# Solve By SAT: evaluation plan (milestone 7)

Lucas Allen · 18 November 2026

**Status: every stage is done (7a to 7d-2), and the scope-or-scale decision is taken (section 10.11). Next: the end of milestone 7, then milestone 8.** This plan covers open directions 1 and 2 of SPEC 9.4 as far as measurement goes: how much real Lean the class covers, and how CNF size behaves on typed problems. It does not change the encoder, except for an optional count-only mode (section 4.1).

## 1. Questions

| # | Question | Answered by |
| --- | --- | --- |
| Q1 | **Coverage.** What fraction of real Lean goals have a proof in the class, using the lemmas their actual proof uses, and at what N? | section 3 |
| Q2 | **Why not.** For the goals that fail, which limitations block them, and how often? | section 3.3 |
| Q3 | **Typed scaling.** On typed problems, how much do candidate pruning, pair pruning and the static typing filter cut groundness and decomposition? How does CNF size grow with the number of lemmas? | section 4 |
| Q4 | **Baselines.** How does the tactic compare with `solve_by_elim` given the same lemmas, and with `exact?` and `apply?` searching the whole library? | section 3.2 |

Together the answers decide whether the next effort goes into scope or scale (section 7).

## 2. Corpus

**Source.** Lean core `Init` of the installed toolchain (4.36.0), plus `Std` if memory allows. There is no Mathlib, in line with the project's dependencies.

**Pre-registration.** All filters, seeds, sample sizes and limits are fixed before the first full run and recorded in NOTES.md. They are not changed after seeing results. If one must change, the reason is recorded and everything it affects is rerun.

### 2.1 Tier A: theorem statements

- **Goals.** Every `theorem` in the source whose type is a proposition, excluding auxiliary declarations: internal names, equation lemmas, matchers, recursors, `_proof_` and `_auxLemma` constants. The goal is the theorem's type, with an empty context.
- **Oracle H.** The constants in its proof term (`Expr.getUsedConstants`), filtered as in 2.3.
- **Recorded.** Proof-term size, and whether the proof uses an elimination constant (a recursor, `casesOn`, a matcher, `Eq.mpr`, `Eq.rec`, `Eq.ndrec`, `Eq.subst`, `False.elim`, `absurd`).
- **Sample.** Everything if at most 3,000 remain after filtering, otherwise a seeded uniform sample of 3,000.

### 2.2 Tier B: goals inside proofs

Top-level statements are biased: many core theorems are proved by `simp`, `omega`, `decide` or induction. Tier B approximates the goals a user closes with `exact` or `apply` in the middle of a proof.

- **Goals.** Walk the proof terms of a seeded sample of 1,000 Tier A theorems, entering binders as local declarations. Every subterm whose type is a proposition, and whose head is a constant or a local hypothesis applied to at least one argument, gives a goal. The goal is that subterm's type, in the local context of its enclosing binders.
- **Oracle H.** The constants in the subterm, filtered as in 2.3.
- **Dedupe and caps.** Deduplicate by (goal type up to α-equivalence, H). Take at most 10 goals per theorem, so long proofs do not dominate, and at most 3,000 in total.
- **Sanity check.** `inferType` of the oracle subterm is defeq to the recorded goal type.
- **Oracle node estimate.** The number of proof-valued subterms headed by a constant or local hypothesis. This roughly matches the node count of SPEC 1 when the oracle term is itself in the class.

### 2.3 Oracle H filter

Keep a constant if it is:

- a theorem or axiom whose type is a proposition; or
- a data constant per SPEC 2.1 (non-Prop type, result not a Sort).

Drop:

- instances (`Meta.isInstance`), since the goal's templates already fix them;
- the built-in rule constants (`And.intro`, `Or.inl`, `Or.inr`, `Exists.intro`, `Iff.intro`, `True.intro`, `And.left`, `And.right`, `Iff.mp`, `Iff.mpr`);
- auxiliary constants (matchers, recursors, internal names).

Constants that the compiler rejects stay in the record, with the rejection message, but are left out of the H that is passed to the tactic.

## 3. Coverage runs

### 3.1 The tactic

For each goal:

1. Compile the goal. If it is rejected: `goal_rejected(reason)`.
2. Compile each H constant. Record the accepted ones, and the rejected ones with their reasons.
3. For N = 1, …, Nmax with Nmax = 10: encode, then solve under the time limit. At the first SAT result, decode and kernel-check, giving `proved(N)`.
   - If every N up to Nmax is UNSAT: `no_proof_le_Nmax`.
   - If a resource limit is hit: `timeout(N)` or `memout(N)`.
   - The documented-limitation message: `limitation`.
   - A decoder failure is `decoder_bug`. It **stops the run** and is investigated under the standing rule.
4. At the final N, record variables, clauses, per-family clause counts (the breakdown used for SPEC 7.3), encode time, solve time, peak memory, and the skeleton.

The N loop lives in the harness, not the tactic. It is a prototype for open direction 3 (search over N), but it is not that feature.

### 3.2 Baselines

Each baseline runs on the same goal, in the same local context, from a fresh state, with the same heartbeat budget and a recorded wall time.

- **`solve_by_elim [H]`** with the oracle H and a maximum depth of at least Nmax. This is the like-for-like baseline: a backtracking search over essentially the same fragment.
- **`exact?`**, searching the whole imported environment.
- **`apply?`**, recorded as `closed` (a suggestion closes the goal), `partial` (it leaves goals, with their count) or `none`.

Check the configuration names of these tactics against the toolchain.

### 3.3 Classifying failures (Q2)

Each goal that is not proved gets one primary reason, assigned by rules in this order:

1. goal rejected, with its reason;
2. an H constant needed by the oracle term was rejected, with its reason;
3. the oracle term uses an elimination constant (2.1);
4. the goal or the oracle term contains numerals (`OfNat.ofNat`) in a position that matching would need to see through;
5. `timeout` or `memout`;
6. `no_proof_le_Nmax` with none of the above: **unexplained**.

A seeded sample of 50 unexplained goals (or all of them, if there are fewer) is reviewed by hand, and each is classified in NOTES.md. Typical expected causes are defeq unfolding, instance mismatches and coercions.

### 3.4 Soft completeness check

A Tier B goal is **oracle-in-class** if:

- every constant in its oracle term is accepted;
- the term uses no elimination constant; and
- its oracle node estimate is at most Nmax.

Every oracle-in-class goal that ends as `no_proof_le_Nmax` is listed and classified by hand. This is not automatically a bug, because the estimate is rough and defeq can hide behind an elaborated term. It is the only completeness probe on real data, so each case gets an explanation.

## 4. Typed scaling (Q3)

### 4.1 Synthetic, controlled

Reuse the chain of SPEC 7.3: prove `x ≤ w` from `x ≤ y`, `y ≤ z`, `z ≤ w` and `Nat.le_trans`. Add k distractors of the form `∀ m n, R m n → R (f m) (f n)`, all from one family:

| Family | Distractors | Expected effect |
| --- | --- | --- |
| S | `f` is one shared symbol `s : Nat → Nat`, `R` is `≤` on `Nat` | reproduces the shape of 7.3; little pruning possible |
| T1 | distinct `fᵢ : Nat → Nat`, `R` is `≤` on `Nat` | pair pruning can separate `fᵢ` from `fⱼ` |
| T2 | distinct carrier types `Tᵢ`, each with its own `LE` instance, `fᵢ : Tᵢ → Tᵢ` | candidate pruning and static typing can act |
| T3 | distinct predicates `Pᵢ : Nat → Nat → Prop` | matching filters at compile time |

All instances go through the Lean compile path, so type templates are real, unlike `bench.py`.

**Grid.** k ∈ {0, 4, 8, 16, 32} and N ∈ {5, 8, 12}, under five configurations:

- all refinements on;
- all refinements off;
- all on except `candidatePruning`;
- all on except `pairPruning`;
- all on with `staticTyping` off.

**Count-only mode.** The large cells will not fit in memory. If the encoder can count clauses per family without storing them at modest cost, add a `countOnly` mode. It must not change semantics, and a test must show its counts equal a full encode on every instance in the 7.3 table. Otherwise, record those cells as `memout` with the last size reached.

**Report.** Per-family clause counts; the share of groundness plus decomposition; and the growth exponent in k (log-log slope from k = 8 to k = 32) for each family and configuration. In 7.3 that exponent is about 2.

### 4.2 Real distractors

- **Goals.** A seeded sample of up to 50 goals proved in section 3, spread across N.
- **Distractors.** Add k ∈ {0, 2, 4, 8, 16, 32} lemmas from the pool of compiler-accepted core lemmas, selected in two ways:
  - **random:** uniform from the pool;
  - **near:** lemmas whose head predicate symbol matches the head of the goal or of an oracle lemma. This is the hard case that premise selection produces.
- **Runs.** Search N from 1 up to the goal's minimal N from section 3. Record clause counts, times and memory, and whether a smaller N was found (a distractor can give a shorter proof).
- **Monotonicity invariant.** Adding lemmas cannot remove a proof. So every run that stays within the limits must find a proof at or below the original N. A violation **stops the run** and is investigated as a completeness bug.
- **Report.** The largest feasible k per goal, within a fixed budget of 20 s solve time and 2.5 GB per call. Give the median and distribution, separately for random and near.

## 5. Limits and environment

- **Executable.** The harness is a Lean executable (for example `lake exe solve_by_sat_eval`) that imports `Init`, plus `Std` if it fits. Measure the import's memory first.
- **Memory.** The machine has 3.8 GB and no swap. Shard the goals and run one shard process at a time, each under `ulimit -v` (2.5 GB to start).
- **Time limits.**
  - Solver: 20 s per call, using CaDiCaL's time-limit option (check `cadical --help`).
  - Lean baselines: one fixed heartbeat budget.
  - Each goal: 120 s wall time in total.
- **Resumability.** Append each goal's result to JSONL as soon as it finishes, so a crash loses at most one goal. A rerun skips completed ids.
- **Header.** Each output file records the toolchain, the git commit, every option, the seeds and the limits.
- **Pilot.** Before the full run, run a 100-goal pilot (50 per tier). If the pilot projects the full run at more than about 8 hours, reduce the sample sizes before the full run and record the change.

## 6. Outputs

**Data files** in `eval/`:

- `corpus_A.jsonl`, `corpus_B.jsonl`
- `results.jsonl`
- `scaling_synthetic.jsonl`, `scaling_real.jsonl`

**Report.** `eval/report.py` generates `EVAL.md` from the JSONL files alone, with these tables:

| Table | Content |
| --- | --- |
| R1 Funnel | per tier: goals → goal accepted → H fully accepted → proved at N ≤ Nmax |
| R2 Failure reasons | counts per reason of 3.3, with two examples each |
| R3 Node counts | histogram of minimal N; oracle estimate against found N |
| R4 Baselines | 2×2 overlaps of `solve_by_sat` against `solve_by_elim` and against `exact?`; median and p90 times |
| R5 Synthetic scaling | clauses per family, k and configuration; growth exponents |
| R6 Real distractors | clauses and time against k, random and near; largest feasible k |
| R7 Soft completeness | every case of 3.4, with its classification |

**NOTES.md.** A "Milestone 7" section with every deviation and filter decision, ending with the Regression line.

## 7. Reading the results

These rules are fixed now, before any data comes in. The thresholds are indicative.

- **Scope first** if under about 20% of Tier B goals are proved with oracle H, and R2 is dominated by one or two reasons that a targeted extension could address (for example numerals, rewriting with `Eq.mpr`, or unfolding). R2 then names the extension.
- **Scale first** if a fair share of goals is in the class, but R6 shows the feasible k falling well short of what premise selection would supply, which is tens of lemmas. Concretely: in-class goals become infeasible around k = 16 to 32 with near distractors.
- **Scale is less urgent than SPEC 7.3 suggests** if the typed families show a growth exponent near 1, or if pruning removes most of groundness and decomposition. SPEC 7.3 then gets a typed table, and the order of 9.4 is revisited.
- **Value against baselines.** Suppose `solve_by_elim` with the same H proves nearly everything `solve_by_sat` proves, and faster. Then the tactic's distinctive contributions are:
  - minimal proofs;
  - certified "no proof with at most N nodes" answers.

  In that case, R4 should single out the goals where `solve_by_elim` fails and `solve_by_sat` succeeds, and say why: depth, backtracking order, or metavariables shared between subgoals.

## 8. Threats to validity

- **Oracle H is optimistic.** It assumes premise selection is solved. Section 4.2 measures the cost side of relaxing this, but not the selection itself.
- **Core proofs are tactic-heavy.** Tier A undercounts what the tactic could prove with other lemmas. Tier B corrects this only in part.
- **Elaborated terms.** Tier B goals come from elaborated terms, in which implicit arguments and instances are already filled. The goal statements are what a user would see, but the oracle term is cleaner than a user's proof attempt.
- **Core only.** Goals about the algebraic hierarchy, where instance arguments matter most, are under-represented without Mathlib.
- **Bounded failure.** `no_proof_le_Nmax` with oracle H does not mean the goal is outside the class.

## 9. Stages for Claude Code

Stop after each stage and show its output.

| Stage | Work | Acceptance |
| --- | --- | --- |
| 7a | Corpus extraction (section 2) | Deterministic: the same seed gives byte-identical files. The Tier B sanity check passes on every goal. Show counts per tier and per filter, with 10 examples per tier. |
| 7b | Coverage harness and baselines (section 3), pilot first | The named tests L1 to D7, run through the harness, give the same N as the test suite. Zero decoder bugs. Resume works after a forced kill. Stop after the pilot, with a time projection. |
| 7c | Typed scaling, synthetic then real (section 4) | `countOnly`, if added, equals a full encode on all 7.3 instances. Family S follows the structure of 7.3, with any differences from the forest-level benchmark explained. The monotonicity invariant holds. |
| 7d | Report (section 6) | `EVAL.md` regenerates from the JSONL files alone. NOTES.md has the Milestone 7 section and Regression line. |

## 10. Amendments after 7a (18 November 2026)

All of these were made before any coverage run, so they stay within pre-registration. NOTES.md "Milestone 7" has the full record.

### 10.1 Accepted deviations from 7a

- **Memory cap by cgroup** (`systemd-run --user --scope -p MemoryMax=2500M -p MemorySwapMax=0`), replacing `ulimit -v` in section 5. Importing `Init` + `Std` reserves over 4 GB of address space for about 710 MB resident, so `ulimit -v` kills the process at start.
- **Source is `Init` + `Std`** (713 MB peak resident).
- **All Prop-typed constants are proof constants in H**, not only theorems and axioms. This keeps constructors of inductive propositions (`Eq.refl`, `HEq.refl`) and Prop-typed definitions (`rfl`).
- **Oracle H looks through internal auxiliary theorems** (`_proof_N`, `_simp_N`) for both H and elimination detection.
- **Extra Tier A filter:** compiler-generated lemmas (`inj`, `injEq`, `sizeOf_spec`, `induct`, `splitter` and similar).

### 10.2 Data constants in H (changes 2.3)

Under the original rule, every non-Prop constant in the oracle term became a data clause. That includes the statement's own function symbols (`HAdd.hAdd`, `OfNat.ofNat`, `List.length`). Two problems follow:

- **The measurement is distorted.** These constants already appear as ground or template terms. They become data clauses only to build terms that the proof never builds. They inflate H well beyond the lemmas applied: about 14 kept constants per Tier A goal and 9 per Tier B goal, at sizes where 9 lemmas already give millions of clauses.
- **It is not what a user would list.** A user passes the lemmas to apply, and a data constant only when a witness must be built.

**New rule.** The main H (`H_main`) keeps:

- every proof constant; and
- a data constant only if it does **not** occur (`getUsedConstants`) in the goal's closed type, nor in the type of any proof constant kept in that goal's H. Such a constant is one the proof actually builds terms from, such as a witness.

The corpus also keeps the earlier set as `H_full`. Main coverage runs use `H_main`. A side run on a seeded subsample of 300 Tier B goals uses `H_full`, and is reported separately as table R1b: coverage, N and CNF size against `H_main`.

**Also:** the goal's own declaration must never be in its H.

**Result (from the regenerated corpus).**

- Median |H_main| is 6 for Tier A and 2 for Tier B; p90 is 19 and 10.
- No goal has itself or its source theorem in H.
- The goal sets are unchanged.

### 10.3 Harness requirements for 7b

- **Memory-out handling under the cgroup.**
  - Write a "started" marker before each goal. On resume, a goal with a marker and no result is recorded as `memout(shard)` and skipped, so a goal that kills its shard is never retried for ever. (Superseded by 10.4: `crash(shard, cause)`.)
  - A solver killed by a signal is recorded as `memout(N, solver)`.
  - The N loop stops at the first timeout or memout.
- **`solve_by_elim` in two configurations**, both with `maxDepth := 10`:
  - **like-for-like:** `symm := false`, `exfalso := false`, with `intro` and `constructor` on;
  - **default:** everything else at its defaults.

  R4 reports both.
- **Warm-up for `exact?` and `apply?`.** One untimed `librarySearch` call per shard before the first goal, so that building the discrimination tree is not charged to that goal. Record the warm-up time and memory.
- **Fixed budgets.** The baseline heartbeat budget is fixed and recorded before the pilot.
- **Pilot projection.** Break the projection down by outcome. If it exceeds 8 hours, propose the reduction and wait for approval before the full run.

### 10.4 Amendments before 7b

**Combinators are not data constants.**

Under 10.2, H_main still keeps polymorphic combinators whose result type is a type variable: `id`, `Eq.mpr`, `Eq.mp`, `cast`, `False.elim`, `dite`, `ite` and similar. 660 of the 1,615 Tier A goals that keep a data constant, and 392 of 619 in Tier B, keep only such combinators. This causes two problems:

- The compiler cannot use them as data clauses, because the head would be a clause variable.
- Rule 2 of 3.3 runs before rule 3, so it would report failures as "H constant rejected: `id`" or "`Eq.mpr`", which is misleading.

Therefore:

- **`id` is transparent.** It comes from `show` and type ascriptions. It is dropped from H_main and ignored by the classifier.
- **Elimination constants are dropped from H_main.** These are the constants of 2.1. Rule 3 reports them instead, so rule 2 never names them.
- **Four more elimination constants.** `Eq.mp`, `cast`, `dite` and `ite` count as elimination constants (casts along an equality, or case splits on a decidable proposition) **when they survive the 10.2 data rule**: that is, when the proof uses them but neither the goal nor a kept lemma mentions them. They are then dropped from H_main as above. An `ite` that appears in the statement is ordinary data and is unaffected.
- **Verify, don't assume.** Confirm that the compiler rejects every constant dropped by these rules on its own, so the change affects classification only and no tactic result. Report any it accepts.

**`exact?` and `apply?` can find the goal itself.** A Tier A goal's own declaration is in the imported environment, so `exact?` would close it trivially. If `librarySearch` can exclude given constants, exclude:

- the goal's own declaration (Tier A);
- the source theorem (Tier B).

Otherwise, record each closure as `closed_self` (the term mentions the goal's own declaration or source theorem) or `closed_other`. R4 counts only `closed_other`, and says how many Tier A goals were `closed_self`.

**Crashes and the watchdog.**

- Replace `memout(shard)` in 10.3 with `crash(shard, cause)`, where the cause is `oom` (killed by the cgroup) or `watchdog`.
- A per-goal watchdog of 300 s covers everything, the baselines included.
- The 120 s limit of section 5 applies to the `solve_by_sat` N loop alone.

**Baseline budget.** 200,000 heartbeats per baseline call (Lean's default `maxHeartbeats`).

**Pilot.**

- 50 goals per tier with H_main, plus 20 goals of the R1b side run with H_full.
- Break the projection down by tier, by outcome, and by |H_main| bucket (0–5, 6–10, 11–20, over 20).
- After the pilot, only the sample sizes may change, as section 5 allows. Report the pilot's outcome counts, but do not tune anything on them.

### 10.5 Decisions after the pilot (18 November 2026)

**Pilot result.**

- 120 goals: 50 Tier A, 50 Tier B and 20 R1b.
- 0 decoder bugs. All 36 named cases agree with the test suite. The resume and forced-OOM checks pass.
- Proved: Tier A 2 of 50, Tier B 16 of 50, R1b 2 of 20.
- Crashes at the 2.5 GB cap: Tier A 13, Tier B 7, R1b 7.
- Projected full run on the development machine: 30.6 hours.

These numbers are for orientation only, and nothing is tuned on them.

**Changes made during 7b, accepted.**

- Solver timeouts. At its -t limit, CaDiCaL 2.1.2 prints the comment line c UNKNOWN and exits with 0. This counts as a timeout.
- Memory cap. This follows a global out-of-memory incident when two runs overlapped.
  - The 2.5 GB cap applies to the whole per-run slice: shard, solver and helper together.
  - One driver runs at a time, and shards die with their driver.
  - Solver files are written to disk, not to the /tmp tmpfs.
- New outcomes.
  - memout(N, spawn): ENOMEM when starting the solver.
  - Heartbeat and recursion-depth exhaustion in the baselines.
- exact? finding the goal itself. librarySearch cannot exclude constants, so closures are labelled closed_self or closed_other (10.4). In the pilot, 36 of the 37 Tier A closures by exact? were closed_self, so R4 compares against exact? on Tier B only.

**Decisions.**

1. No sample reduction. The full pre-registered run (3,000 Tier A, 3,000 Tier B and 300 R1b goals) goes ahead on a dedicated test machine, so the 8-hour rule of section 5 is waived.
2. Baselines run before the solve_by_sat N loop, so that a memory crash no longer loses them. Each baseline still starts from a fresh state. Record the shard's RSS before and after the baselines. The calibration of item 5 checks that the new order changes no solve_by_sat outcome.
3. Like-for-like solve_by_elim uses no default lemmas. As implemented in 7b, both configurations add rfl, trivial, congrFun and congrArg, which are not in H, and the pilot gave identical results for the two.
   - Like-for-like now uses H_main and the local hypotheses only, with symm and exfalso off and maxDepth := 10.
   - The default configuration is unchanged.

   This corrects the definition of the baseline, as noticed in the 7b notes. It does not affect solve_by_sat.
4. Parallel shards are allowed if the test machine has room, with P ≤ min(physical cores − 1, ⌊(RAM in GB − 2) / 2.6⌋).
   - Each shard runs in its own slice capped at 2.5 GB.
   - If P > 1, the resume and forced-OOM checks are repeated in parallel mode before the full run.
   - P and the machine's specifications go into every output header and into NOTES.md.
   - Only 1 of 120 pilot goals hit a time limit, so contention between shards should change little; report the count.
5. Calibration on the test machine before the full run. Run the full test suite, then the 36 named cases, then the 120 pilot goals again with the new baseline order. Compare each goal with the development machine's pilot:
   - a different proved N, or any decoder bug: stop;
   - any other difference, such as a timeout or memory crash on one machine only: list and explain it, then continue.
6. Results are pushed to the eval-m7 branch after each completed shard. No other machine pushes to that branch during the run.
7. After the full run, stop and report. Stage 7c is planned separately.

### 10.6 After the full 7b run (21 November 2026)

**Run record.**

- All 6,300 goals were run on the test machine, one shard at a time: 37.5 hours of running, 42 hours elapsed.
- Two decoder bugs stopped the run. Both were in the decoder's replay (SPEC 8), not in the encoding.
  - Premise metavariables could be assigned by head unification. They are now synthetic opaque.
  - The decoder used its caller's unifier settings. It now always uses the tactic's (`foApprox`, `ctxApprox`).
- Both bugs were rejected, never accepted as proofs. Both have regression tests (`Test/M7Lean.lean`).
- Every goal that had reached SAT was rerun after each fix. No other result changed.
- The test machine needed `vm.overcommit_memory = 1`: under the kernel's heuristic overcommit, `lake` could not fork. The development machine's intermittent ENOMEM most likely has the same cause.

**Counts before classification.** These are the raw `solve_by_sat` outcomes.

| Run | Goals | Proved | No proof ≤ 10 | Memory crash | Goal rejected | Solver timeout |
| --- | --- | --- | --- | --- | --- | --- |
| Tier A | 3,000 | 140 | 1,711 | 819 | 272 | 58 |
| Tier B | 3,000 | 828 | 1,363 | 496 | 297 | 16 |
| R1b (Tier B, H_full) | 300 | 87 | 121 | 60 | 28 | 4 |

- Of the 1,055 proofs found across all three runs, 598 have N = 1.
- Like-for-like `solve_by_elim` closes 977 Tier A goals and 2,069 Tier B goals.
  - It closes 797 of the 828 Tier B goals that `solve_by_sat` proves.
  - `solve_by_sat` alone proves 58 Tier A goals and 31 Tier B goals.

**Order of the remaining stages.** 7d is split in two. This changes the order of the plan's work, not any filter, sample or limit.

- **7d-1 now:** everything that needs only the 7b data. That is R1, R1b, R2, R3, R4 and R7, the hand reviews of 3.3 and 3.4, and the exploratory analyses below. It needs no new runs.
- **7c next:** typed scaling, as in section 4.
- **7d-2 last:** R5 and R6 from the 7c data, and the reading of section 7.

**Rule 4 of 3.3 (numerals) is made exact before R2 is computed.** The rule was never made exact. Claude Code proposes an exact, mechanical version, records it in NOTES.md, and reports R2 both with and without it.

**Exploratory analyses.** These were not pre-registered, and are labelled as exploratory in EVAL.md.

- **E1, where `solve_by_elim` wins.** For goals closed by like-for-like `solve_by_elim` but not proved by `solve_by_sat`:
  - break them down by `solve_by_sat` outcome;
  - for those with `no_proof_le_Nmax`, review a seeded sample of 50 by hand and record why the search failed. Candidate reasons are defeq or instance unification beyond syntactic matching, a lemma our compiler rejects, and proof size.
- **E2, the data-constant rule.** Compare R1b with the main run on the same 300 goals. Any goal proved only with H_full is a counterexample to the 10.2 rule; list it with its proof.
- **E3, CNF composition on real goals.**
  - For proved and no-proof goals: the per-family clause shares at the final N.
  - For crashed goals: the clauses at the last N reached.

  Both are plotted against |H_main| and N. This tests whether groundness and decomposition dominate on real goals as they do in SPEC 7.3.
- **E4, time.** Compare the wall times of `solve_by_sat` and `solve_by_elim` on the goals both prove.

### 10.7 Type-template bug found in 7d-1 (21 November 2026)

**Finding.** The E1 review found a completeness bug in the compiler.

- Type templates are built from the raw inferred type (`compileType (← inferType e)`).
- Terms are built from preprocessed expressions (SPEC 4.1).
- The typing clause (6.8) therefore compares an unnormalised type with a normalised one, and can exclude a real proof.

There are two minimal reproductions with the tactic:

- `decide (¬ b = true) = decide (b = false)` with `[Decidable.decide.congr_simp, Bool.not_eq_true]`: here `Not` is not unfolded in the template.
- `x = x` for `x : List (α × β)` with `[Eq.refl]`: here the level `succ (max u v)` is compared with `max (succ u) (succ v)`.

Soundness is unaffected, because the typing clause only excludes models and every proof is kernel-checked. A static scan flags at most 1,184 non-proved and 108 proved main-run goals, almost all through universe levels.

**Decisions.**

1. **Fix the compiler.** Build every type template from the preprocessed inferred type. Also audit `Compile.lean` for any other inferred type that is used without preprocessing.
2. **Add an invariant check.** Every template the compiler records must be unchanged by preprocessing. Run the check over every goal and H constant in the corpus. Any failure is a further instance of this bug.
3. **Add regression tests** from both reproductions (`Test/M7Lean.lean`, R3), each with its minimality check. Add a mutation check showing that the tests fail with the fix reverted.
4. **Choose the rerun set by comparing forests.**
   - Compile all 6,300 full-run goals before and after the fix, and compare the compiled forests.
   - If a goal's forest is identical, its CNF is identical at every N, so its result stands.
   - Every goal whose forest changes is rerun.
   - Run the SAT phase only. The baselines do not use the compiler, so they are kept.
5. **Spot-check the unchanged goals.** Also rerun a seeded sample of 100 goals whose forests did not change. Their outcomes must match, except outcomes that hit a resource limit on either run.
6. **Rerun on the test machine** with the same limits and P = 1, writing results to `eval/rerun/`.
7. **Reporting.**
   - In the final results, a rerun goal's `solve_by_sat` outcome replaces the original.
   - Each result records its code version.
   - EVAL.md gives the outcome counts both before and after the fix, so the effect of the bug is visible.
8. **Reviews.**
   - After the merge, redraw the 7d-1 samples with the same seeds from the updated populations.
   - Reuse an existing review if its goal's forest did not change. Otherwise, review the goal again.
   - The `solve_by_sat`-only review starts after the merge.

**Order.** Fix and compare forests (development machine), then rerun (test machine), then merge and finish 7d-1 (development machine), then 7c, then 7d-2.

### 10.8 After the 10.7 rerun (23 November 2026)

**Run record.**

- The 1,128 goals of the rerun set (1,028 whose forest changed, 100 spot-check goals) were run on the test machine, SAT phase only, finishing on 22 November. There were no decoder bugs, solver errors or harness errors.
- A power loss interrupted the run once. No result was lost or duplicated; NOTES.md records the recovery.
- The spot check of decision 5 passed, 100 of 100. The three differences all had a memory crash on the original run.
- The run took about 13.7 hours, against a projection of 3.4 to 6.4 hours. 463 of the 1,128 goals crashed on memory, and each crash also costs a shard restart.

**Effect of the fix.** These counts are from a preview of the pre-registered merge; `eval/merge.py` gives the final ones.

| Run | Proved, before → after | Memory crash, before → after |
| --- | --- | --- |
| Tier A | 140 → 140 | 819 → 807 |
| Tier B | 828 → 836 | 496 → 490 |
| R1b | 87 → 88 | 60 → 59 |

- There are 9 new proofs, all in Tier B: 8 at N = 1 and 1 at N = 2. They include the 4 goals that the 7d-1 reviews attributed to this bug. No proof was lost, and every goal proved before keeps its N.
- 438 of the 1,028 changed goals crashed on memory both before and after the fix, so the fix's effect on them is not measured.

**Decisions.**

1. **Merge** by the rule pre-registered in NOTES.md ("10.7: merge rule").
2. **Redraw the review samples exactly as decision 8 of 10.7 says.** The samples change much more than their populations, because `random.Random(seed).sample` is not stable when a population's membership changes, even at the same size. In the preview, the redrawn samples keep 11 of the 50 unexplained goals, 69 of the 100 R7 goals and 17 of the 50 E1 goals. Reviews of goals that leave a sample are kept, marked as superseded, and not counted in any table.
3. **EVAL.md states the crashed-twice caveat** next to the before and after tables.
4. **Samples not yet drawn** (the 50 goals of 4.2 in 7c, and any later sample) are drawn so that small changes to the population change them little: rank the keys by a hash of the seed and the key, and take the first n. This does not affect the 7d-1 samples, which are already pre-registered.

**Order.** Merge and finish 7d-1 (development machine), then 7c, then 7d-2.

### 10.9 Before 7c (23 November 2026)

**Findings from 7d-1 for the 7d-2 reading.** NOTES.md ("7d-1: merge and reviews") has the evidence.

- **The baseline's step budget.** Like-for-like `solve_by_elim` spends one step on every `apply`, `intro` and `constructor`, and `maxDepth := 10` is one budget for the whole search, so at most 9 steps succeed. The harness introduces a Tier B goal's context first, but a Tier A goal pays a step for every binder of its statement. 11 of the 12 `solve_by_sat`-only goals lost to depth are Tier A. This is a property of the pre-registered baseline, not a change to it.
- **Projections.** 63 of the 89 `solve_by_sat`-only proofs use an `↔` or `∧` projection. These are built-in rules of `solve_by_sat`, and like-for-like `solve_by_elim` cannot build them from H_main. Of the other 26, `solve_by_elim` loses 12 to its step budget, 9 to heartbeats, 3 to backtracking order, 1 to metavariables shared between subgoals and 1 to a built witness.
- **Where `solve_by_elim` wins.** Of the 50 E1 goals, 33 first need definitional unfolding or instance unification (25 of them unfolding a definition), and 17 need a constant the compiler rejects (`propext` 7, `congrArg` 6). None fails on proof size.

**Decisions for 4.1 (synthetic).**

1. **`countOnly`.** It counts variables and clauses per family without storing clauses. It must equal a full encode, in variables and in every family's clause count, on every instance of the SPEC 7.3 table, with all refinements on and with all off. It must also equal a full encode on every synthetic cell where a full encode fits under the 2.5 GB cap.
2. **Distractors** are `axiom` declarations in a test-only Lean file, never in the library. The family shapes are those of the table in 4.1. In T2, each carrier `Tᵢ` is a distinct structure with its own `LE` instance.
3. **The grid** is that of 4.1: 4 families, k ∈ {0, 4, 8, 16, 32}, N ∈ {5, 8, 12} and the five configurations, all counted with `countOnly`. Nothing is solved. Results go to `eval/scaling_synthetic.jsonl`.

**Decisions for 4.2 (real distractors).** These are fixed before any 4.2 run.

1. **Goals.** The population is the main-run goals proved in `eval/final/` (976; R1b is excluded). Split them by their proved N into four buckets: 1, 2, 3–4, and 5 or more (553, 193, 162 and 68 goals). Take 12, 12, 13 and 13 goals, ranking each bucket's keys by a hash of seed 70301 and the key (10.8 decision 4), with the two tiers pooled.
2. **Pool.** The 48,012 Tier A source theorems (the filters of 2.1, before sampling) that the compiler accepts as an H constant. For constants that also appear in `eval/corpus_hcompile.jsonl`, the verdicts must agree.
3. **Exclusions per goal.** Leave out its H_main constants, and its own declaration (Tier A) or its source theorem (Tier B).
4. **Modes.**
   - **random:** the whole pool after the exclusions;
   - **near:** the pool members that have a clause head, on any split path and including opaque heads, whose predicate symbol is in S. S holds the predicate symbols of the goal's root target and of the heads of the clauses compiled from H_main. The eigenvariable symbol `app` does not count.
5. **Nested selection.** For each goal and mode, rank the candidates by a hash of the seed (70302 random, 70303 near), the goal key and the constant name. The k distractors are the first k, so each set contains the smaller ones. If there are fewer than k candidates, use all of them and record the actual k.
6. **Runs.** For each goal: k = 0 once, and k ∈ {2, 4, 8, 16, 32} for each mode, so 11 runs per goal and 550 in all.
   - H is H_main followed by the distractors in rank order.
   - The N loop runs from 1 up to the goal's proved N, with the full run's limits: solver 20 s per call, N loop 120 s, watchdog 300 s, 2.5 GB cap, P = 1.
   - Record the outcome, the N found, whether it is below the original N, whether the proof uses a distractor, and the per-N record the full run keeps.
7. **Sizes.** For every run, also record the `countOnly` counts per family at the goal's original N, so R6 has clause counts even for runs that crash.
8. **Feasible.** A run is feasible if it finds a proof at or below the original N within the limits. For each goal and mode, report the largest k such that every k′ ≤ k is feasible, and also the largest feasible k on its own.
9. **Stop rules.**
   - A run that ends within every limit without a proof at or below the original N violates the monotonicity invariant (4.2). It stops the run as a completeness bug.
   - A k = 0 run builds the same CNFs as the final results. One whose outcome or N differs from them stops the run, unless either run hit a resource limit.
   - A decoder bug stops the run, as always.
10. **Pilot first.** Run the highest-ranked goal of each bucket, with all 11 runs (44 runs in all), and stop with a projection, as in 7b. If the projection for the full 4.2 run exceeds about 24 hours, propose a reduction (fewer goals per bucket, never fewer values of k) and wait for approval.

**Order.** 4.1, then the 4.2 pilot, then the full 4.2 run after approval, then 7d-2.

### 10.10 Before 7d-2 (24 November 2026)

**7c record.** NOTES.md ("7c: synthetic scaling and the 4.2 pilot", "7c: the full 4.2 run") has the details.

- **`countOnly`** equals a full encode on all 22 SPEC 7.3 checks. On the synthetic grid, 290 cells equal a full encode, 10 ran out of memory in the full encode, and none differ.
- **Synthetic scaling (R5).**
  - The growth exponent in k from 8 to 32 is 1.91–1.93 for S, 1.80–1.83 for T1, 1.15–1.35 for T2 and 1.92 for T3.
  - Groundness plus decomposition at k = 32 is 94–97% (S), 90–95% (T1), 31–51% (T2) and 99% (T3).
  - Switching off pair pruning alone, or candidate pruning alone, changes no cell. Typing acts only in T2, and every configuration keeps static typing or candidate pruning on, so the grid cannot separate the two.
- **Real distractors (R6).**
  - 550 runs, and no stop rule fired.
  - The median largest feasible k is 16 (random) and 12 (near). By original N it is 32, 16, 8 and 4 for N = 1, 2, 3–4 and 5 or more.
  - At k = 32, the median CNF is about 500 times its size at k = 0.
  - The 2.5 GB cap falls at about 10 to 12 million clauses.
- **"Near" is close to random for most goals.** 35 of the 50 goals have `c:Eq` in S, and about 74% of the pool has an `Eq` head.
- **Timing.** The full 4.2 run took 7 h 43 min against a projection of about 4 h. Counting the large near cells took most of the extra time.

**Decisions for 7d-2.**

1. **Correct the record.** NOTES.md says 31 goals have `c:Eq` in S. Check the number against `eval/scaling_goals.jsonl` and correct it.
2. **The reading.** EVAL.md gets a section "Reading the results (§7)", generated by `eval/report.py`. For each rule of section 7, it states the rule's condition, the numbers the condition rests on, and whether it holds. It does not choose between scope and scale. The owner decides after 7d-2, and the decision is recorded as section 10.11.
3. **Summary.** EVAL.md opens with answers to Q1–Q4 of section 1, in numbers, each pointing to its table.
4. **R2 names the extension** (section 7). Break reason 2 down, per tier:
   - goals by rejection reason (for example "clause variable applied to arguments" and "clause variable as head symbol");
   - the constants that block the most goals;
   - the goals that a single rejected constant blocks, by constant.
5. **R6 additions.**
   - The median per-goal growth exponent in k from 8 to 32, for each mode.
   - R6's main table, split by whether S contains `c:Eq`.
6. **E5 (exploratory): what milestone 8 would reach.**
   - Take each main-run goal that is accepted but not proved. Its obstacles are its rejected H_main constants and the elimination constants of its oracle term (2.1, 10.4).
   - Map each obstacle to a family of the milestone 8 proposal, using a fixed table that is committed before any count is computed:
     - **3A, rewriting by first-order equality rules:** `congrArg`, `congrFun`, `congrFun'`, `congr`, `propext`, `Eq.mpr`, `Eq.mp`, `Eq.rec`, `Eq.ndrec`, `Eq.subst`, `cast`, `of_eq_true`, `eq_true`, `eq_false`, `eq_self`, and the congruence lemmas of the logical connectives (`forall_congr`, `and_congr` and similar);
     - **1, eliminations whose motive is the goal:** `Or.elim`, `Exists.elim`, `False.elim`, `absurd`, `Decidable.byContradiction`, `Classical.byContradiction`, `Classical.byCases`, `Decidable.byCases`, `dite` and `ite` as elimination constants, and the recursors, `casesOn` and matchers of `Or`, `Exists`, `False`, `And` and `Iff`;
     - **2, cases and induction on data:** the recursors, `casesOn`, matchers and induction principles of every other inductive type;
     - **out of reach:** everything else, for example `funext` and `of_decide_eq_true`.
   - Report per tier:
     - the number of goals for each combination of families among their obstacles;
     - in particular, the goals whose obstacles all fall in a single family;
     - the most common out-of-reach constants.
   - Say plainly that this is an upper bound. Removing every obstacle does not make a goal provable: definitional unfolding, instances and proof size can still block it, and the `congrArg` chains of `simp` proofs may need many nodes.
7. **E6 (exploratory): both typing filters off.** Count the 60 synthetic cells (4 families × k ∈ {0, 4, 8, 16, 32} × N ∈ {5, 8, 12}) with static typing and candidate pruning both off and every other refinement on. Use `countOnly` only. This lets R5 say how much each filter does on its own. The pre-registered grid is unchanged.
8. **Threats to validity.** EVAL.md gets a section that restates section 8 with what the data now shows. At least:
   - like-for-like `solve_by_elim`'s step budget handicaps it on Tier A (10.9);
   - "near" is close to random when S contains `c:Eq`;
   - one machine, one memory cap: 21.5% of the main-run goals crashed and are unmeasured;
   - elaborated `simp` proofs inflate the count of rewriting obstacles;
   - the oracle H is optimistic.
9. **Close the record.** NOTES.md gets a section "Milestone 7: summary", ending with the Regression line (the 7d acceptance criterion). Nothing is rerun except the E6 counts.

**Order.** 7d-2, then the owner's scope-or-scale decision (10.11), then the end of milestone 7: SPEC.md takes in the two decoder fixes, the type-template fix and the evaluation results.

### 10.11 The scope-or-scale decision (24 November 2026)

**7d-2 record.** 7d-2 is done (NOTES.md "7d-2" and "Milestone 7: summary"; EVAL.md "Reading the results"). Its counts were checked independently: EVAL.md regenerates byte-identically, and the R2 breakdown, the R6 exponents and E6 recompute from the data files. The reading of section 7:

- **Rule 1 (scope first)** holds only in part. R2 is dominated by one reason (a rejected H constant, mostly `congrArg`), and E5 bounds a rewriting extension at 946 more Tier B goals. But Tier B's 27.9% is 7.9 points above the indicative 20%.
- **Rule 2 (scale first):** its R6 condition holds. The median largest feasible k with near distractors is 12, and 4 for proofs of 5 or more nodes.
- **Rule 3 (scale less urgent)** does not hold, except in T2.
- **Rule 4 (value against baselines)** holds for Tier B.

**Correction to 10.10.** "Typing acts only in T2" is inexact. Static typing also removes 2–3% of the clauses in S and T3; T2 is the only family where it matters much (E6).

**Decision: scale first, with a cheap rewriting probe.**

- **Why.** The owner leans towards scope, and the two are linked. A rewrite costs about d + 1 nodes and adds clauses mostly to groundness, and feasible k already collapses at N ≥ 5 (R6). So the goals that rewriting would unlock are the ones where memory runs out first.
- **Milestone 8 is scale:** shrinking groundness and decomposition (SPEC 9.4, direction 1). None of its approaches has been tried, so it starts with a design note, before any implementation.
- **The rewriting probe comes first in milestone 8 (8a).** It is cheap, and it tells the scale work what rewriting will need. It measures rewriting by first-order equality rules without changing the tactic:
  - for each goal, generate the congruence and substitution rules for the symbols of its goal and H_main, specialised per symbol and argument position, as ordinary Lean lemmas, and pass them in H;
  - measure how many of the goals whose E5 obstacles are all rewriting constants become provable within N ≤ 10 and the 2.5 GB cap, at what N and CNF size, and what the rules cost on goals already proved;
  - pre-register its sample, rule set and limits before any run.
- **Eliminators and rewriting in the tactic itself**, proposed as "milestone 8" in the claude.ai project's design note, become milestone 9; the note is now `M9_DESIGN.md` there. Their order follows E5 and the probe: rewriting first.

**The end of milestone 7.**

- SPEC.md takes in the two decoder fixes, the type-template fix, `countOnly` and a summary of the evaluation.
- The code and the reports of `eval-m7` are merged into `main` by a true merge, so every commit that EVAL.md and NOTES.md cite stays reachable. The reports are EVAL.md, NOTES.md, EVAL_PLAN.md, CLAUDE.md, `eval/report.py`, `eval/merge.py` and the hand reviews in `eval/reviews/`.
- The bulk data stays only on `eval-m7`, which is kept as an archive and tagged `m7-data`. That covers every run folder, the corpus and annotation files, the specs, the scaling data and the forest dumps.
- EVAL.md regenerates on `m7-data`, not on `main`.

**Order.** The end of milestone 7, then milestone 8: the probe (8a, `M8_PLAN.md`), the scale design, and its implementation.
