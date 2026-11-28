# SolveBySAT: notes for Claude Code

A Lean 4 tactic, `solve_by_sat`, that searches for small backward-chaining proofs by
reduction to SAT. The spec is `SPEC.md`; the Python prototype in `reference/` is the
authority for SPEC §5 and §6.1–6.8 where they disagree. `NOTES.md` records every
deviation from the spec and every decision, milestone by milestone. Read its Milestone 7
and Milestone 8 sections before touching the evaluation; `EVAL_PLAN.md` and `M8_PLAN.md` are
those milestones' plans (both closed). `M9_PLAN.md` is milestone 9's.

## Standing rules (from the project owner)

- Work in the milestones of SPEC §9 and the stages of `EVAL_PLAN.md` §9. For each one:
  state the plan in a few lines, implement it, run its acceptance tests and those of all
  earlier milestones, show the output, then **stop and wait** for the owner.
- Lean core and Std only (no Mathlib). Keep the module layout of SPEC §3.
- Do not widen the scope of SPEC §2. If a test needs something outside it, say so
  instead of adding it.
- Check every Lean API name and signature against the installed toolchain (4.36.0), and
  say where the spec or plan was wrong.
- If the decoder fails on a satisfiable CNF, it is a bug in the compiler or encoder: find
  it, do not work around it.
- Never weaken or delete a test to make it pass.
- Record every deviation in `NOTES.md`; end each milestone's notes with a "Regression"
  line.
- Commit or push only when asked.

### Milestone 7 (evaluation) rules

- The harness must not change what the encoder or decoder accept. The only encoder
  addition allowed is the optional `countOnly` mode of EVAL_PLAN §4.1, with its test.
- Filters, seeds, sample sizes and limits are pre-registered in `NOTES.md` (and
  `EVAL_PLAN.md` §10). Do not change them after seeing results; if one must change,
  record why and rerun everything it affects. After the pilot, only sample sizes may
  change, and only with the owner's approval.
- A decoder failure, or a monotonicity violation in §4.2 that is not a resource limit,
  stops the run: it is a bug to find, not a data point.

## Build and test

```sh
lake build                         # library
Test/run_all.sh                    # milestones 0-8 acceptance (about 80 minutes)
Test/refinements.sh                # each SPEC 6.10 refinement alone (long)
lake build eval_corpus eval_run    # milestone 7 executables
lake build Test.EvalNamed          # loaded at run time by the named harness
lake build eval_numerals           # 7d-1 annotations, forest dumps, invariant check
lake build eval_scaling eval_pool test_countonly SynthLib   # 7c
lake build eval_run Test.M8Probe     # 8a: probe harness and hand examples
lake build test_m8diag m8b_dimacs73  # 8b: diagnostics test and SPEC 7.3 DIMACS writer
Test/m8c1_offswitch.sh              # 8c-1: flags off give 8b's DIMACS (in run_all.sh)
Test/m8c1_lean.sh                   # 8c-1: the Lean suite with the flags off, R1, R1 and R2 (in run_all.sh)
python3 Test/m8d_run.py status eval/m8d/runs full   # 8d: eval/m8d/STATUS.md (needs m8-data's data)
Test/m9a1_lean.sh                   # 9a-1: the Lean suite with iffEq off and on (in run_all.sh)
python3 Test/m9a1_check.py ../m8-data   # 9a-1: the 8a checks → eval/m9a1/CHECKS.md (needs an m8-data worktree)
lake build test_m9diff && .lake/build/bin/test_m9diff 600 4   # 9a-2: differentials with rules (in run_all.sh)
M9A2_KEEP=1 Test/m9a2_lean.sh; python3 Test/m9a2_classify.py LOGDIR   # 9a-2: the Lean suite with rewrite off/on/liberal (in run_all.sh)
python3 Test/m9a2_setup.py ../m8-data   # 9a-2: inputs of the 11 proofs and the 400 points (eval/m9a2/)
.lake/build/bin/eval_run rules9a eval/m9a2/specs_11.jsonl OUT   # 9a-2: the rules made per spec (strict and liberal)
setsid nohup Test/m9a2_full.sh > eval/m9a2/full_driver.log 2>&1 &   # 9a-2: the measurement (about 10 h)
python3 eval/m9a2/report.py              # 9a-2: eval/m9a2/RULES.md
```

## Layout and where the data lives

- `SolveBySat/` the tactic (SPEC §3). `Test/` the acceptance tests (M0–M8), the evaluation harness
  (`EvalCorpus`, `EvalRun`, `EvalNumerals`, `EvalPool`, `EvalScaling`, `M8Facts`, `M8Rules`, `M8Diag`, the
  Python drivers and the `m8*_run.py` / `m8*_full.sh` scripts) and `Test/capped.sh`. `reference/` the Python
  prototype.
- `SPEC.md` (milestones 7 and 8 folded in), `NOTES.md`, `EVAL_PLAN.md` (milestone 7, closed by §10.11),
  `M8_PLAN.md` (milestone 8, closed by 4.7), `EVAL.md` (milestone 7's report).
- `eval/` on `main` holds only (`eval/README.md` has the list and why):
  - milestone 7's `report.py`, `merge.py`, `reviews/` and `README.md`;
  - in each of `eval/m8a/`, `m8b/`, `m8c1/`, `m8c2a/`, `m8d/`, its report (`PROBE.md`, `DIAG.md`, `SCALE.md`,
    `R3SIM.md`, `EVAL8.md`) and the `report.py` that writes it;
  - the test fixtures `eval/m8b/specs_named_dimacs.jsonl` and `eval/m8b/dimacs_md5.txt`, read by
    `Test/m8c1_offswitch.sh` (in `run_all.sh`);
  - `run_all_m8_merge.log`, the regression log of the milestone 8 merge.
- **All milestone 7 data is on the annotated tag `m7-data`** (the head of branch `eval-m7`) and **all
  milestone 8 data on `m8-data`** (the head of branch `m8`). Both branches are archives: never commit to them.
  NOTES.md, "End of milestone 7" and "End of milestone 8", list the removed paths. The reports regenerate
  on their tag only, e.g. `git worktree add ../m8-data m8-data && cd ../m8-data && python3 eval/m8d/report.py`.
  Without the data, each milestone 8 `report.py` prints that the data is on tag m8-data and exits 1, writing
  nothing.

## Setting up a test machine for a capped evaluation run

Requirements:
- Linux with cgroup v2. A systemd user session must have the memory controller delegated:
  `cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers`
  must list `memory`.
- `systemd-run --user` and `systemctl --user`, python3, elan. `lean-toolchain` pins
  4.36.0, and its bundled `cadical` (2.1.2) is used.
- The memory cap is 2.5 GB for the whole run (one slice). Leave at least 1.5 GB more for everything
  else on the machine. Set `vm.overcommit_memory = 1` (NOTES.md, "7b: full run on the test machine"):
  in heuristic mode, forks of `lake` and of the shard are refused with ENOMEM.
- The milestone 7 machine checks (corpus determinism, the 36 named cases, `eval/test_runs/`'s resume and
  OOM scripts) need the archived data: run them in an `m7-data` worktree. The corpus md5 sums (header line
  excluded): `corpus_A.jsonl` `82c42f9261ad…`, `corpus_B.jsonl` `e74e5dd25bd8…`; `corpus_stats.txt`
  `a332af976598…`. The named cases must equal `eval/fix_check3/named` there in outcome, N and skeleton.

Machine differences (CPU speed, RAM) change times and possibly which goals hit the cap. Record the
machine's specs in NOTES.md before a full run.

## Status (27 November 2026)

- **Milestone 7 (evaluation) is done** and merged into `main` (NOTES.md, "Milestone 7: summary" and "End
  of milestone 7: spec, archive tag and merge"; EVAL_PLAN §10.11). Bugs it found and fixed: two decoder bugs
  (R1, R2 in `Test/M7Lean.lean`) and the type-template fix (EVAL_PLAN §10.7). `countOnly`
  (`EncodeOptions.countOnly`, tested by `test_countonly`) was its only encoder addition.
- **Milestone 8 (scale, `M8_PLAN.md`) is done** and merged into `main` (NOTES.md, "Milestone 8" and "End of
  milestone 8: spec, archive tag and merge"; M8_PLAN 4.7). Stages: 8a the rewriting probe (`PROBE.md`), 8b the
  measurements (`DIAG.md`), 8c-1 R1 and R2 (`SCALE.md`), 8c-2a the R3 simulation (`R3SIM.md`), 8d the evaluation
  (`EVAL8.md`). The encoding stays one-shot (4.2); only exact reductions were accepted (4.4).
  - **R1 and R2 are on by default** in the tactic: R1 node bounds (`EncodeOptions.nodeBounds`, option
    `solve_by_sat.nodeBounds`: node–clause bounds with the scope term e(c), and the early exit when s(root) > N),
    R2 exclusive pairs (`exclusivePairs`, `solve_by_sat.exclusivePairs`). `solve_by_sat.refinements := false`
    switches them off too. Dead `cl`/`gp` literals become constant false through `CNF.kill` (unit clause in family
    "11 node bounds"). Mutation-only options `boundsScope`, `boundsTight`, `exclusiveMutant`; testing-only tactic
    option `solve_by_sat.checkBounds` (the model check).
  - Not built: R3 (simulated, projected ratio 0.9925 > 0.8, 4.6), R4 (set aside), R5 (dropped) (4.5).
- **Milestone 9 (`M9_PLAN.md`), on branch `m9`** (made from `main` at `c3086d1`): rewriting first (9a), then cases
  and induction (9b–9d, planned after 9a-3). The design is `M9_DESIGN.md` in the claude.ai project. Every milestone 9
  option is off by default (owner decision 4). At the end, code and reports go to `main` and the data to a tag.
  - **9a-1 is done** (NOTES.md, "9a-1: ↔ as equations"): `CompileOptions.iffEq`, option `solve_by_sat.iffEq` or
    `(iffEq := true)` in the call (after `(nodes := N)`): every `↔` head on any split path also gives the paths
    `L = R` (recipe `propext`, suffix `.propext`) and `R = L` (`Eq.symm`, `.propext_symm`); a path that cannot be
    compiled is dropped with a note. `verbose` prints the paths added when there are any. Testing-only option
    `solve_by_sat.iffEqMutant` (the recipes swapped). Tests: `Test/M9Lean.lean`, `Test/m9a1_lean.sh` (the Lean
    suite with `iffEq` off and on), both in `run_all.sh`. The 8a checks: `Test/m9a1_setup.py`, `eval_run iffeq-count`,
    `Test/m9a1_check.py` → `eval/m9a1/CHECKS.md`.
  - **9a-2 is done** (NOTES.md, "9a-2: equality rules made per use"; `eval/m9a2/RULES.md`): `CompileOptions.rewrite`
    (option `solve_by_sat.rewrite`, or `(rewrite := true)` after `(iffEq := b)`), `eqTrans` (default true;
    `(eqTrans := false)`), `rewriteSymbols` (option, comma list; `(rewriteSymbols := [c, …])`). The pure selection and
    clause shapes are `SolveBySat.Rules` (end of `Forest.lean`), shared with `Test/M9Diff.lean`; the compiler's
    `addRules` builds each rule's statement and proof, runs the static motive check, compiles the statement as a
    clause (global, or local to the root) and checks its shape against `Rules.mkRule`/`mkCore` (an internal error if
    not). Origin `.rule k`, `Compiled.rules`, `Compiled.ruleStats`. Decoder: the stored proof, `synMatch` before
    `isDefEq` for rule nodes, and a check that the proof proves the clause. Testing-only options
    `rewriteIneligibleMutant`, `rewriteContextMutant`, `rewriteLiberal`. With `rewrite` off nothing changes (54/54).
  - **Next: 9a-3** (M9_PLAN 4, pre-registered), only after the owner has checked 9a-2.
- Milestone 9 rules: M9_PLAN section 1 ("Rules carried over from milestone 8") and milestone 8's. SPEC.md is revised
  in the claude.ai project at the end of the milestone, not here.

### Harness notes (milestones 7 to 9)

- **The harness's own default for the flags is off**, unlike the tactic's:
  `SOLVE_BY_SAT_EVAL_FLAGS=nodeBounds,exclusivePairs` sets them for `eval_run run|sizes` (unset: both off, so
  milestone 7 and 8a runs rebuild their CNFs). Since 9a-1 the same variable carries the compiler options:
  `iffEq` in it sets `CompileOptions.iffEq` for `eval_run run|sizes` (absent: off), and a run records
  `iffeq_paths` [from H, local]. The variable is process-wide: every goal of a run, crash records
  included, gets it. Since 9a-2, `rewrite` and `noEqTrans` in it set `CompileOptions.rewrite` and `eqTrans := false`;
  a run with `rewrite` records `rules`, `rules_total`, `liberal_extra`, `rules_dropped`, … and, when proved,
  `rules_used` and `rules_used_by`; constants are accepted with `rewrite` off. `SOLVE_BY_SAT_EVAL_COMPARE=<results.jsonl>` applies 4.4's exactness stop rules (exit 9, in
  the shard and on crash records the driver writes; 6 in 8c-1). `eval_run exactness-selftest` and
  `python3 Test/eval_driver.py exactness-selftest` are in `run_all.sh`.
- The 8b and milestone 7 tools (`dimacs`, `diag-models`, `m8b_dimacs73`, `eval_scaling`, `eval_numerals`, the 8b
  hand count, `test_m4`'s milestone 4 check) pin both flags off. Exact-output Lean guards that differ under R1 are
  pinned to the flags off, each with an R1 twin.
- Tools by stage: 8a `Test/M8Rules.lean`, `Test/M8Probe.lean`, `eval_run`'s `probe` fields and `probe-rules`,
  `Test/m8a_setup.py`, `Test/m8a_run.py`, `Test/m8a_full.sh`, `Test/m8a_publish.sh`; 8b `Test/M8Diag.lean`,
  `eval_run diag | diag-models | dimacs`, `m8b_dimacs73`, `test_m8diag`, `Test/m8b_setup.py`, `Test/m8b_run.py`;
  8c-1 `eval_run sizes8c`, `eval_run diag … SETTING`, `Test/m8c1_run.py`, `Test/m8c1_full.sh`; 8c-2a
  `M8Diag.simEncode`/`r3sim`/`r3ModelCheck`, `eval_run diag … r3`, `eval_run r3-models`, `Test/m8c2a_run.py`,
  `Test/m8c2a_full.sh`; 8d `Test/m8d_run.py`, `Test/m8d_full.sh pilot|full`. Their inputs are on `m8-data`.
  Detached runs: `setsid nohup Test/m8X_full.sh … &`.
- Milestone 8 rules (for reference): as milestone 7's. Only exact reductions (M8_PLAN 3.1, 4.4); SPEC.md is
  revised in the claude.ai project, not here. Filters, seeds, sample sizes and limits were pre-registered in
  `M8_PLAN.md` and NOTES.md; a decoder failure on a satisfiable CNF, or a §2.5 stop rule, stops the run.

## Running the evaluation

- `python3 Test/eval_driver.py specs named|pilot|full OUT.jsonl` writes a spec file. Milestone 7's
  pre-registered `eval/specs_*.jsonl` files are on `m7-data`, milestone 8's (`eval/m8*/specs*.jsonl`) on `m8-data`.
- `python3 Test/eval_driver.py run SPECS OUTDIR` runs it. Only one driver may run at a
  time, enforced by `eval/.driver.lock`. Run it in the background: a full run takes
  hours. Resume by running the same command again.
- Results go to `OUTDIR/results.jsonl`, one line per goal. Crash records are written by
  the driver. Exit code 3 (decoder bug or solver error) or 4 (harness error) means stop
  and investigate.

## Lessons from this machine

- `ulimit -v` cannot cap memory here: the import reserves more than 4 GB of address space
  for about 0.7 GB resident. Use the cgroup (already in the driver).
- Never `pkill -f` with a pattern that appears in your own shell command: it kills the
  shell. Kill by PID, or use patterns anchored at the start of the target's command line.
- An orphaned shard plus a new run once exhausted RAM and forced a reboot. The driver now
  takes a lock and its children die with it (`PR_SET_PDEATHSIG`); keep it that way.
- `/tmp` may be a tmpfs (RAM). Solver inputs go to `OUTDIR/tmp` on disk.
- Bash reads a script while it runs: never edit `Test/run_all.sh` (or rebuild what it runs) while it is running. Do not
  rebuild `eval_run` while a detached run uses it.
- In Lean 4.36 `try … catch` in `MetaM` does not catch heartbeat or recursion-depth
  exceptions; use `tryCatchRuntimeEx`.
- CaDiCaL 2.1.2 at its `-t` limit prints `c UNKNOWN` (a comment line) and exits 0.
- The elaborator runs tactics with `foApprox` and `ctxApprox` on; a bare `MetaM` (the
  harness's `runMeta`, the test executables) has them off. Code that must behave as the
  tactic does sets its configuration itself (as `decode` now does).
