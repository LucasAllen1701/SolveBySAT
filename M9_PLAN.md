# Solve By SAT: milestone 9 plan (rewriting first, then cases and induction)

Lucas Allen · 27 November 2026

**Status: 9a-1 and 9a-2 are complete (sections 2 and 3, amendments 6.1 and 6.2). 9a-3, the evaluation, has started, as pre-registered (section 4, amendment 6.2). 9b to 9d are planned after 9a-3.** The design is `M9_DESIGN.md` in the claude.ai project, revised on 27 November 2026 after milestone 8; this plan follows it and records the owner's decisions on it.

## 1. Aims, stages and rules

Milestone 9 lets `solve_by_sat` mimic `rw`, `cases` and `induction` where the motive is forced or chosen from finitely many candidates (M9_DESIGN sections 1 to 3). Rewriting comes first, because it reaches the most goals (SPEC 9.5, 9.6).

| Stage | Work |
| --- | --- |
| 9a-1 | `↔` as equations: an option `iffEq` (section 2) |
| 9a-2 | Equality rules in the tactic, made per use and selected on rewriting paths: an option `rewrite` (section 3) |
| 9a-3 | Evaluation of 9a, pre-registered (section 4) |
| 9b, 9c, 9d | Family 1, family 2, and route 3B only if needed; planned after 9a-3 |

**Owner decisions** (27 November 2026, on M9_DESIGN section 10):

1. **Rules are made per use** (M9_DESIGN 6.4). Each rule takes the types, instances and universe levels of an actual occurrence of its symbol, rather than being generic over them.
2. **Strict selection** (M9_DESIGN 6.5). Only the strict variant is built; the liberal variant is counted, not built.
3. **`Eq.trans` is in** the `rewrite` option by default, with a switch `eqTrans` to leave it out.
4. **Every milestone 9 option is off by default.** Defaults are reconsidered after 9a-3.

**Rules carried over from milestone 8.**

- **Off-switch.** With every milestone 9 option off, the DIMACS output is byte-identical to milestone 8's (`main` at `c3086d1`) on the 54 encodings of `eval/m8b/dimacs_md5.txt`. The differential suites and the Lean suite give identical answers.
- **The proof class grows by exactly the generated clauses,** which are a deterministic function of the goal, H and the options. `verbose` lists them.
- **A decoder failure on a satisfiable CNF is a bug.** Every motive is checked statically, at compile time.
- **Node bounds and exclusive pairs stay on.** New clauses must respect them, and the bounds model check (`checkBounds`) runs on every decoded proof in the Lean suite.
- **Pre-registration.** Inputs, seeds, samples and limits are fixed before any run, and changed only by an amendment with its reason.
- **Branch.** The work runs on a branch `m9` made from `main`. At the end of the milestone the code and reports go to `main` and the bulk data stays on a tag, as for milestones 7 and 8.

## 2. 9a-1: `↔` as equations (M9_DESIGN 6.3)

### 2.1 What is built

- **Option.** `solve_by_sat.iffEq` (default false), also `(iffEq := true)` in the tactic call.
- **Compilation.** Every clause with an `↔` head, on any split path, gets two more split paths:
  - head `L = R`, an `Eq` atom at type `Prop`, with recipe `propext` applied to the path's proof;
  - head `R = L`, with recipe `Eq.symm` of that.

  This covers global clauses from H, local hypotheses, and split paths nested in `∧` or `↔` heads. Each new path has fresh binder names and its own copies of the premise goal positions, as SPEC 4.2 requires of every split path.
- **Templates.** `L` and `R` are compiled as term templates (SPEC 4.5). A path whose `L` or `R` cannot be compiled, for example because it contains a proof-dependent binder, is dropped and reported, as other split paths are.
- **Decoder.** The two recipes are built with `propext` and `Eq.symm`, checked against the toolchain's names.

### 2.2 Tests and checks

- **Off-switch** as in section 1.
- **Lean tests**, each with its minimality check:
  - `(¬ a ≤ b) = (b < a)` for `a b : Nat`, from `Nat.not_le`: 1 node;
  - the same with the sides swapped, `(b < a) = (¬ a ≤ b)`: 1 node, through the `R = L` path;
  - a local hypothesis: `(h : A ↔ B) : A = B`, and `B = A`: 1 node each;
  - a nested path: `(h : C ∧ (A ↔ B)) : A = B`: 1 node;
  - a quantified lemma: `(h : ∀ x : Nat, P x ↔ Q x) : P 0 = Q 0`: 1 node;
  - with `iffEq` off, each of these must fail with the no-proof message.
- **Mutation check.** With the decoder's two recipes swapped, the tests must fail with a decoder or kernel error, not with a proof.
- **The 8a count.** For the 200 specs of `eval/m8a/specs.jsonl` (on tag `m8-data`), with milestone 7's H (`specs_full.jsonl`) and `iffEq` on:
  - the `propext` paths generated from H constants must number exactly twice 8a's `probe_propext` for each goal: 158 over the 200 specs;
  - paths from local hypotheses are counted separately.
- **The 8a proofs.** The 8 goals whose 8a proof used only a `propext` equation, run with milestone 7's spec and `iffEq` on, must be proved at these N:

  | goal | N in 8a | N expected |
  | --- | --- | --- |
  | `B/Std.DTreeMap.Raw.mem_of_mem_union_of_not_mem_left/5` | 1 | 1 |
  | `B/BitVec.not_self_ne/2` | 1 | 1 |
  | `B/Std.TreeMap.inter_equiv_empty_comm/14` | 2 | 1 |
  | `B/Std.DHashMap.getKey?_eq_some_getKeyD/3` | 2 | 1 |
  | `B/String.Slice.Pos.next_eq_iff/21` | 3 | 3 |
  | `B/UInt64.lt_add_one/7` | 1 | 1 |
  | `B/UInt64.toUInt8_le/11` | 1 | 1 |
  | `B/Std.TreeMap.inter_equiv_empty_comm/13` | 2 | 1 |

  In 8a, the three proofs at N = 2 used `Eq.symm` on the `L = R` equation; the `R = L` path saves that node. Any other N stops the work until it is explained.

### 2.3 Accepted when

All of 2.2 passes, the full suite passes with `iffEq` off and on, and the counts and N match.

## 3. 9a-2: equality rules made per use (M9_DESIGN 6.4 to 6.6)

### 3.1 What is built

- **Option.** `solve_by_sat.rewrite` (default false), with `solve_by_sat.eqTrans` (default true, meaningful only with `rewrite`) and `rewriteSymbols` (default: automatic).
- **Rules.** Substitution and congruence at eligible positions, and `Eq.refl`, `Eq.symm` and `Eq.trans` as built-in clauses unless H already has them. The proof terms are built by the decoder with `congrArg` and `Eq.mpr`. No declarations are added.
- **Eligible positions** as in M8_PLAN amendment 4.1, decision 3, and M9_DESIGN 6.4.
- **Per use.** A rule is generated per (symbol, position, context), with the context taken from an occurrence in the forest. Its context is ground, over the root's eigenvariables (a clause local to the root), or over an H clause's variables (polymorphic in those alone). Contexts are compared after `Level.normalize`.
- **Selection.** The strict rule of M9_DESIGN 6.5. Sources are the equation heads of H, of local hypotheses and, with `iffEq`, of the `propext` paths. Terms of interest are the targets' argument templates and the sources' sides. Rules go on the spines down to rigid occurrences of source symbols.
- **Static motive check.** Each rule's motive is built with placeholders and type-checked once at compile time. A rule that fails is dropped and reported.

### 3.2 Tests

- **Off-switch** as in section 1.
- **Lean tests,** each with its minimality check:
  - `Q (¬ a ≤ b) → Q (b < a)` for `Q : Prop → Prop`, from `Nat.not_le`, with `iffEq` and `rewrite`: a substitution at a Prop position;
  - a congruence: `Nat.succ (a + 0) = Nat.succ a` from `Nat.add_zero`, with `rewrite`;
  - a two-step chain that needs `Eq.trans`, and the same with `eqTrans := false`, which must fail;
  - a goal over the root's type parameters, `∀ {α} [Add α] (x y : α), x = y → x + x = y + x`, with `rewrite`: a rule local to the root;
  - with `rewrite` off, each must fail with the no-proof message.
- **Differentials.** Forest generators that add rules made by the same generation code, against `Reference`, with 0 mismatches. Rules are ordinary clauses, so the reference prover needs no change.
- **Mutation checks:**
  - a rule at an ineligible position must be caught by the static motive check;
  - a rule whose context is replaced by a different one must be caught, by the kernel or by a differential mismatch;
  - dropping selection, so that every eligible (symbol, position, context) gets a rule, must change no answer in the suite, only sizes.
- **The 8a proofs' rules.** For each of the 11 rewriting proofs of 8a that used a substitution or congruence rule, check whether the strict selection generates a rule with the same symbol and position. Report each that it does not, with the reason.

### 3.3 Measurement, before 9a-3

- **The 400 points** of M8_PLAN 4.3, at N = 5 and N = 10, with node bounds and exclusive pairs on, in four settings:
  - without rules: milestone 8's counts;
  - with 8a's rules given as lemmas: 8c-1's counts;
  - with `iffEq` and `rewrite`;
  - the same with `eqTrans := false`.
- **Recorded per point:**
  - the clause counts per family, recounted with milestone 8's diagnostics, extended to the new clauses;
  - the rules generated, by kind and by context row (ground, root, H variables);
  - the number of rules the liberal variant would generate;
  - the share of level symbols in decomposition.
- **The report** states facts, and reading it is for the claude.ai project. It is not a stop rule.

### 3.4 Accepted when

All of 3.2 passes, every rule of the corpus goals passes the static motive check or is reported, and the measurement of 3.3 is complete.

## 4. 9a-3: evaluation (pre-registered)

### 4.1 Groups

1. **The 8a specs.** The 200 specs of `eval/m8a/specs.jsonl` (on tag `m8-data`), with milestone 7's H in place of the probe's rules, and `iffEq` and `rewrite` on. They are compared with 8c-1's rerun of the same specs (`eval/m8c1/rerun/`, on `m8-data`).
2. **A fresh sample.** The population is the 1,468 E5 rewriting-only goals of `eval/m8a/inputs/population.jsonl` (on `m8-data`, md5 `69230cf475e193ded9bc224bba49832f`), less the 150 that 8a used: 846 in Tier B and 472 in Tier A. Take 100 Tier B and 50 Tier A goals.
3. **Fresh controls.** The main-run goals proved in milestone 7 (`eval/final/results.jsonl` on tag `m7-data`, md5 `944cc58e53ee2b4ce17ee1e83d29bab1`), less 8a's 50 controls (`eval/m8a/inputs/scaling_goals.jsonl`) and 8d's 50 proved controls (`eval/m8d/sample.tsv`): 878 goals. Take 50.

### 4.2 Ranking and sample file

- **Ranking.** Rank each group's keys by the SHA-256 hex digest of `"90301:<key>"`, ascending, ties broken by the key, and take the first ones.
- **The sample file.** `eval/m9a3/sample.tsv` has one line per run of groups 2 and 3, `<group>\t<key>`, with the groups `rewrite_B`, `rewrite_A` and `control` in that order and rank order within each. It ends with a newline.
  - Its md5 must be `b311e0be3034d3e1f139135cebbb9c76`.
  - The first keys are `main:B/Int8.ofNat_bitVecToNat/4`, `main:A/Array.elem_eq_contains` and `main:B/Or.resolve_left/2`.
  - Group 1 is identified by 8a's spec file.

### 4.3 Runs

- **Specs.** Each run uses milestone 7's spec (H and tier) with the baselines off, and `iffEq` and `rewrite` on, with `eqTrans` at its default.
- **Settings.** The N loop from 1 to 10, with milestone 7's limits: solver 20 s per call, N loop 120 s, watchdog 300 s, a 2.5 GB cgroup cap, and P = 1. Node bounds and exclusive pairs are on.
- **Records.** For each run, record:
  - the outcome, the N found, the per-N record and the time;
  - the rules used in the proof;
  - the rules generated, by kind and context row;
  - the `countOnly` counts per family at N = 5 and at the run's last N, each in its own capped process.

### 4.4 Stop rules

- A decoder failure on a satisfiable CNF.
- **A lost proof.** The run ends within every limit without a proof at or below its earlier N, for:
  - a group 1 goal whose 8c-1 proof used none of the probe's rules, against 8c-1's N;
  - a group 3 goal, against milestone 7's N.

  Their earlier proofs are still in the class, and adding clauses cannot remove a proof.
- **Groups 2 and 3: an exactness failure.** A proof that uses no generated rule or `propext` path, at an N where milestone 7's answer was UNSAT.

A goal that 8c-1 proved with one of the probe's rules and that 9a-3 does not prove is not a stop. It is listed and explained: either the selection left a rule out, or the rule's context differs.

### 4.5 Pilot and projection

- **Pilot.** Run the 5 highest-ranked goals of each fresh group, and 10 of group 1 taken in 8a's rank order.
- **Projection.** Project the time of all 400 runs from the pilot.
- **Approval.** If the projection exceeds about 24 hours, propose smaller groups and wait. Otherwise continue.

### 4.6 Report

`eval/m9a3/report.py` writes `eval/m9a3/EVAL9A.md` from the data files alone, and it must regenerate byte-identically. It covers:

- outcomes per group, and the transitions from 8c-1's or milestone 7's outcomes;
- proved at N;
- the rules used, by kind and context row;
- the CNF sizes against 8c-1's for group 1;
- the list and explanations of 4.4.

It states facts.

## 5. Later stages

9b (family 1), 9c (family 2) and 9d (route 3B, only if 9a-3 shows that the node cost of rewriting blocks proofs) are planned after 9a-3, from M9_DESIGN sections 4, 5 and 6.8. Their resume and re-entry edges must keep the node-bounds argument of SPEC 6.10.1 valid, checked on models as in milestone 8.

## 6. Amendments

### 6.1 After 9a-1 (28 November 2026)

**9a-1 record.** NOTES.md ("9a-1: ↔ as equations") and `eval/m9a1/CHECKS.md` have the details. The stage was checked independently: M9_PLAN.md's md5 is as given, the count recomputes from `eval/m9a1/count.jsonl` against 8a's `rules.jsonl`, the 8 runs are proved at the expected N with `iffEq` on, and every milestone 8 `report.py` stops with the guard message on `m9`.

- **The count.** 158 `propext` paths come from constants of H over the 200 specs. That is twice 8a's count for every spec, not only in total. 4 more come from local hypotheses, all in one goal. No path was dropped, and no constant's acceptance changed.
- **The 8 proofs** are at the expected N. The three that 8a proved at N = 2 are proved at N = 1, through the `R = L` path.
- **The off-switch** gives 54 of 54 identical encodings. The Lean suite passes with `iffEq` off and on, with the same decoded proofs per file.

**Decisions.**

1. **M8Probe's guards.** With `iffEq` on, P4's minimal N falls from 4 to 3, because the `R = L` path saves a node. P3's and P4's exact guards are pinned to `iffEq` off, their setting in 8a, and twins check them with `iffEq` on. This is accepted, as 8c-1's pinning was. No expectation was weakened.
2. **Syntax.** The tactic takes `(nodes := N)` and then `(iffEq := b)`, in a fixed order. 9a-2's arguments follow them in the same way.

**Clarifications for 9a-2.** These amend section 3.

1. **The equality core is made per use.** The `rewrite` option's `Eq.refl`, `Eq.symm` and `Eq.trans` are not polymorphic built-ins. They are instantiated, like the other rules, at each type at which an equation occurs in the forest after rule generation:
   - the heads of the sources;
   - the `t = s` premises and congruence heads of the generated rules;
   - the targets.

   The type is fixed as it occurs (ground, the root's eigenvariables, or an H clause's variables). Constants that H already contains, such as a polymorphic `Eq.symm`, are left as they are.
2. **Atoms with an eigenvariable head.** An atom such as `Q x`, whose head is an eigenvariable (symbol `app`, SPEC 4.5), takes substitution rules like any predicate. The head variable is part of the rule's context, so for a root eigenvariable the rule is local to the root.
3. **Positions** are numbered as in 8a: every argument, from 0, as in `_probe.HAdd.hAdd.congr.«4»`. The check of the 11 proofs in 3.2 then compares like with like.
4. **The selection mutation in 3.2.** Dropping selection only adds rules, so it can only add proofs. The check is that no proof found with selection is lost. A test whose expected failure becomes a proof is listed, not counted as a failure of the check. This replaces "must change no answer in the suite, only sizes".
5. **The measurement of 3.3.** The settings with 8a's rules use 8c-1's recorded counts (`eval/m8c1/sizes_N5/` and `sizes_N10/`, on `m8-data`); they are not rerun. The setting without rules is recounted, and it must equal 8c-1's R1-and-R2 counts at every point, as a consistency check.

### 6.2 After 9a-2: 9a-3 runs as pre-registered (28 November 2026)

**9a-2 record.** NOTES.md ("9a-2: equality rules made per use") and `eval/m9a2/RULES.md` have the details. The stage was checked independently: M9_PLAN.md's md5 is as given, RULES.md regenerates byte-identically, and the pooled sizes recompute from `eval/m9a2/sizes_N5/` and `sizes_N10/`.

- **Exactness and the off-switch.**
  - The recount without rules equals 8c-1's at all 400 points, at N = 5 and N = 10.
  - The off-switch gives 54 of 54 identical encodings.
  - The differentials with generated rules have 0 mismatches (3,000 comparisons, 430 proofs that use a rule), and dropping selection loses no proof.
  - The Lean suite with `rewrite` on loses no proof, and 4 expected failures become proofs.
- **Sizes**, pooled over 8a's 200 goals at N = 5:
  - The rules made per use give 0.867 of the clauses of 8a's rules (per goal, a median of 0.43; 151 goals are smaller), and 4.46 times the clauses without rules.
  - With `eqTrans` off, 0.759 of 8a's. N = 10 is similar.
  - Groundness falls from 39% to 23% of the clauses, and decomposition grows from 58% to 74%. Level symbols are 18.6% of decomposition, against 38.3% with 8a's rules and 11.7% without.
- **The rules.** 2,352 in all, a median of 11 per goal:
  - substitution 410, congruence 537, and the equality core 1,405 (refl 553, symm 515, trans 337);
  - by row: ground 1,499, root 344, H 509;
  - 41 dropped because their statement could not be compiled, and none by the static motive check.
- **8a's 11 proofs.** 14 of the 17 substitution and congruence rules they used are generated. The other 3, in 2 proofs, rewrite with an equation whose matching side is a variable, so only the liberal variant has them. 9 of the 11 are proved at 8a's N.

**Decisions.**

1. **The nine deviations of NOTES.md ("Deviations, and points for the owner") are accepted.** They go into SPEC.md at the end of the milestone. They are:
   - the static motive check never fails on a natural rule, and is kept as a safety net;
   - instance positions are sound, but excluded by eligibility;
   - a wrong context is caught by the decoder's new check that a rule's proof proves its clause;
   - eigenvariables count as source symbols;
   - kinds by place, where a substitution rule of `Eq` acts as transitivity;
   - the settings of the measurement, and the liberal count;
   - the decoder's syntactic match for rule heads (`synMatch`);
   - the expected failures that became proofs, with their expectations unchanged.
2. **9a-3 runs exactly as pre-registered in section 4,** with `eqTrans` on and strict selection.
3. **Trimming the rule set is decided after 9a-3,** from its record of the rules each proof uses, by kind and row. Candidates are the `H` row of the equality core, `symm` and `trans`.
4. **A typed middle variant** between strict and liberal selection is left open for after 9a-3. In it, a variable side of a source would match only nodes of its own type.
5. **`M9_DESIGN.md` is kept in the repository.** It sits at the root of `m9`, identical to the claude.ai project's copy, so that Claude Code can read the design the plan follows.
6. **Clarification of 4.4 for group 1.** An 8c-1 proof "used none of the probe's rules" when its record's `probe_extra_used` is empty, so that it used milestone 7's H alone. A proof that used `Eq.refl`, `Eq.symm` or `Eq.trans` as added by the probe counts as using the probe's rules. Such a goal is listed, not a stop, because the equality core of `rewrite` is made per use and may not include that constant at that type.
