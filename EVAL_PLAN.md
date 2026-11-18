# Solve By SAT: evaluation plan (milestone 7)

Lucas Allen · 18 November 2026

**Status: planned, not started.** This plan covers open directions 1 and 2 of SPEC 9.4 as far as measurement goes: how much real Lean the class covers, and how CNF size behaves on typed problems. It does not change the encoder, except for an optional count-only mode (section 4.1).

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
