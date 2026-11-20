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
- 7b is done. The full run (`eval/full/`, 6,300 goals) ran on the test machine under the
  decisions of EVAL_PLAN §10.5:
  - no sample reduction;
  - baselines before the N loop;
  - `sbe_like` without default lemmas;
  - P = 1.

  It finished on 21 November after 37.5 h of driver time. The final record is in
  NOTES.md, "7b: full run, final record", and the per-shard status is in
  `eval/full/STATUS.md`.
- Two decoder bugs stopped the run and were fixed, with regression tests R1 and R2 in
  `Test/M7Lean.lean` and reruns in `eval/fix_check/` and `eval/fix_check2/`:
  1. premises as synthetic-opaque metavariables;
  2. `decode` sets the tactic's unifier configuration itself.

  Earlier results were shown unaffected, except the two bug goals, which were recomputed.
- 7c (typed scaling) and 7d (report, `EVAL.md`) have not started. **Wait for the owner**
  before starting either.

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
