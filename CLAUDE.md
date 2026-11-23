# SolveBySAT: notes for Claude Code

A Lean 4 tactic, `solve_by_sat`, that searches for small backward-chaining proofs by
reduction to SAT. The spec is `SPEC.md`; the Python prototype in `reference/` is the
authority for SPEC §5 and §6.1–6.8 where they disagree. `NOTES.md` records every
deviation from the spec and every decision, milestone by milestone. Read its Milestone 7
section before touching the evaluation, and `M8_PLAN.md` for milestone 8.

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
lake build eval_scaling eval_pool test_countonly SynthLib   # 7c
```

## Layout and where the data lives

- `SolveBySat/` the tactic (SPEC §3). `Test/` the acceptance tests (M0–M7), the milestone 7 harness
  (`EvalCorpus`, `EvalRun`, `EvalNumerals`, `EvalPool`, `EvalScaling`, `M8Facts`, the Python drivers) and
  `Test/capped.sh`. `reference/` the Python prototype.
- `SPEC.md` (milestone 7 folded in), `NOTES.md`, `EVAL_PLAN.md` (milestone 7, closed by §10.11),
  `EVAL.md` (milestone 7's report).
- `eval/` on `main` holds only `report.py`, `merge.py`, `reviews/` and `README.md`. **All milestone 7 data
  (run folders, corpus, annotations, specs, scaling data, forest dumps) is on the annotated tag `m7-data`**
  (the head of branch `eval-m7`, an archive: never commit to it). NOTES.md, "End of milestone 7", lists the
  removed paths. EVAL.md regenerates on `m7-data` only:
  `git worktree add ../m7-data m7-data && cd ../m7-data && python3 eval/report.py`.

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

## Status (24 November 2026)

- **Milestone 7 (evaluation) is done** and merged into `main` (NOTES.md, "Milestone 7: summary" and "End
  of milestone 7: spec, archive tag and merge"; EVAL_PLAN §10.11). The owner decided: scale first, with a
  cheap rewriting probe first.
- Bugs found by milestone 7 and fixed: two decoder bugs (R1, R2 in `Test/M7Lean.lean`) and the
  type-template fix (EVAL_PLAN §10.7). `countOnly` (`EncodeOptions.countOnly`, tested by `test_countonly`)
  is the only encoder addition of milestone 7.
- **Next: milestone 8 (`M8_PLAN.md`), on branch `m8`.** 8a is the rewriting probe; 8b the scale design.

## Running the evaluation

- `python3 Test/eval_driver.py specs named|pilot|full OUT.jsonl` writes a spec file. Milestone 7's
  pre-registered `eval/specs_*.jsonl` files are on `m7-data`.
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
