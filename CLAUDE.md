# SolveBySAT: notes for Claude Code

A Lean 4 tactic, `solve_by_sat`, that searches for small backward-chaining proofs by
reduction to SAT. The spec is `SPEC.md`; the Python prototype in `reference/` is the
authority for SPEC §5 and §6.1–6.8 where they disagree. `NOTES.md` records every
deviation from the spec and every decision, milestone by milestone. Read its Milestone 7
section before touching the evaluation.

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
Test/run_all.sh                    # milestones 0-6 acceptance (several minutes)
Test/refinements.sh                # each SPEC 6.10 refinement alone (long)
lake build eval_corpus eval_run    # milestone 7 executables
lake build Test.EvalNamed          # loaded at run time by the named harness
lake build eval_numerals           # 7d-1 annotations, forest dumps, invariant check
```

## Setting up a test machine for milestone 7

Requirements:
- Linux with cgroup v2. A systemd user session must have the memory controller delegated:
  `cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers`
  must list `memory`.
- `systemd-run --user` and `systemctl --user`, python3, elan. `lean-toolchain` pins
  4.36.0, and its bundled `cadical` (2.1.2) is used.
- The memory cap is pre-registered at 2.5 GB for the whole run (one slice). Leave at least
  1.5 GB more for everything else on the machine.

Check the machine before any run:
1. `lake build eval_corpus eval_run Test.EvalNamed`. Set `vm.overcommit_memory = 1`
   (NOTES.md, "7b: full run on the test machine"): in heuristic mode, forks of `lake` and of
   the shard are refused with ENOMEM.
2. **Corpus determinism.** Run `Test/capped.sh .lake/build/bin/eval_corpus extract eval/corpus_check`
   and compare `eval/corpus_check/` with the committed corpus. Ignore the first line of each file, the header,
   which records the git commit. The rest must be byte-identical:
   `tail -n +2 eval/corpus_A.jsonl | md5sum` gives `82c42f9261ad…` and
   `tail -n +2 eval/corpus_B.jsonl | md5sum` gives `e74e5dd25bd8…`;
   `eval/corpus_stats.txt` has md5 `a332af976598…`.
3. **Named tests.** `python3 Test/eval_driver.py run eval/specs_named.jsonl eval/named_check`
   must agree with the test suite on all 36 cases, as in NOTES.md "7b: the coverage
   harness".
4. Optionally rerun the acceptance scripts `eval/test_runs/resume_test.sh` and
   `eval/test_runs/oom_test.sh`.

Machine differences (CPU speed, RAM) change times and possibly which goals hit the cap.
The pilot's projection was made on the original machine, so record the new machine's
specs in NOTES.md before a full run.

## Where milestone 7 stands (21 November 2026)

- 7a (corpus) is accepted, including the H_main amendments (EVAL_PLAN §10.2, §10.4).
- 7b is done. The full run is in `eval/full/` (6,300 goals; NOTES.md, "7b: full run, final
  record"). Two decoder bugs stopped it and were fixed (R1, R2 in `Test/M7Lean.lean`).
- 7d-1 (analysis) **stopped on a compiler bug** (EVAL_PLAN §10.7; NOTES.md, "7d-1 STOPPED" and
  the "10.7" sections after it). Type templates were built from the raw inferred type, without
  the preprocessing of SPEC 4.1, so the typing clause excluded real proofs.
  - The fix is in `SolveBySat/Compile.lean` (`recordNode`). It comes with an invariant check
    (`solve_by_sat.checkTemplates`, 0 failures over the corpus) and regression tests R3a and R3b
    in `Test/M7Lean.lean`.
  - Comparing the compiled forests before and after the fix gives the rerun set: 1,028 goals
    whose forest changed, plus 100 seeded spot-check goals whose forest did not change.

## The current task on the test machine: the 10.7 rerun

Run `eval/specs_rerun.jsonl` (1,128 specs, SAT phase only: each has `baselines: false`) into
`eval/rerun/`, with the same limits and P = 1 as the full run. Projected 3.4–6.4 h.

1. `git pull` on `eval-m7`. Then `lake build`, and
   `lake build eval_corpus eval_run eval_numerals Test.EvalNamed`. `vm.overcommit_memory` must
   still be 1.
2. **Checks before the rerun** (stop and report if any fails):
   - `Test/run_all.sh` exits 0 (it includes `Test/M7Lean.lean` with R3).
   - The 36 named cases: `python3 Test/eval_driver.py run eval/specs_named.jsonl eval/rerun_check/named`
     must equal `eval/fix_check3/named/results.jsonl` in outcome, N and skeleton for every key.
   - Forests on this machine:
     `Test/capped.sh .lake/build/bin/eval_numerals forests eval/specs_full.jsonl eval/rerun_check/after.jsonl`
     must have md5 `13ae01664c0a…`, the development machine's after-fix dump. This shows that
     this machine compiles every goal identically, so the rerun set is right here too.
3. **Run it detached:** `setsid nohup Test/eval_rerun.sh > /dev/null 2>&1 &`.
   - It pushes `eval/rerun/` after each shard. A stop is appended to NOTES.md and pushed.
   - Exit 3 (decoder bug or solver error) or 4 (harness error): stop and investigate, as in the
     full run.
   - Resume by starting it again.
4. **After it finishes:**
   - check `eval/rerun/results.jsonl` against `eval/specs_rerun.jsonl` (no key missing,
     duplicated or extra);
   - run `python3 eval/merge.py`. The spot check of decision 5 must pass: same outcome, and when
     proved the same N, unless either run hit a resource limit. It exits 1 on a failure;
   - record the run in NOTES.md (machine, wall time, outcome counts, the merge report), commit,
     push and **stop**.

   The merge rule is pre-registered in NOTES.md ("10.7: merge rule"); do not change it.
- **Do not** continue the 7d-1 reviews, regenerate `EVAL.md` or start 7c. They come after the
  merge, on the development machine (EVAL_PLAN §10.7 decision 8).

## Running the evaluation

- `python3 Test/eval_driver.py specs named|pilot|full OUT.jsonl` writes a spec file. The
  committed `eval/specs_*.jsonl` files are the pre-registered ones.
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
- In Lean 4.36 `try … catch` in `MetaM` does not catch heartbeat or recursion-depth
  exceptions; use `tryCatchRuntimeEx`.
- CaDiCaL 2.1.2 at its `-t` limit prints `c UNKNOWN` (a comment line) and exits 0.
- The elaborator runs tactics with `foApprox` and `ctxApprox` on; a bare `MetaM` (the
  harness's `runMeta`, the test executables) has them off. Code that must behave as the
  tactic does sets its configuration itself (as `decode` now does).
