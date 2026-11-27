# eval/

The evaluations of milestones 7 and 8 produced about 71 MB and 33 MB of data: run folders, corpus and
annotation files, specs, sizes, models, scaling data and forest dumps. On `main` this folder keeps only the
reports, the scripts that write them, and the fixtures that the acceptance tests read.

| on `main` | what it is |
| --- | --- |
| `report.py` | writes `EVAL.md` (milestone 7) |
| `merge.py` | the merge rule of the 10.7 rerun (NOTES.md, "10.7: merge rule") |
| `reviews/` | the hand reviews of milestone 7 (7d-1 and 7d-2) |
| `m8a/PROBE.md`, `m8a/report.py` | 8a, the rewriting probe |
| `m8b/DIAG.md`, `m8b/report.py` | 8b, the measurements |
| `m8c1/SCALE.md`, `m8c1/report.py` | 8c-1, node bounds (R1) and exclusive pairs (R2) |
| `m8c2a/R3SIM.md`, `m8c2a/report.py` | 8c-2a, the R3 simulation |
| `m8d/EVAL8.md`, `m8d/report.py` | 8d, the evaluation of the tactic as users run it |
| `m8b/specs_named_dimacs.jsonl`, `m8b/dimacs_md5.txt` | **test fixtures** (below) |
| `run_all_m8_merge.log` | the log of `Test/run_all.sh` on the merged tree (NOTES.md, "End of milestone 8") |

**Fixtures.** `Test/m8c1_offswitch.sh`, which `Test/run_all.sh` runs, writes the 54 DIMACS encodings of
`m8b/specs_named_dimacs.jsonl` (the 36 named cases at their milestone 7 N) and of the SPEC 7.3 examples with
both milestone 8 flags off, and checks them against the md5 sums in `m8b/dimacs_md5.txt` (8b's encodings,
which equal those of `SolveBySat` at `5820197`). Without these two files the off-switch test cannot run, so
they stay on `main`. No other test reads a file under `eval/`.

## Where the data is

- **Milestone 7:** annotated tag `m7-data` (the head of branch `eval-m7`, an archive). NOTES.md, "End of
  milestone 7: spec, archive tag and merge", lists every path removed from `main`, with its size.
- **Milestone 8:** annotated tag `m8-data` (the head of branch `m8`, an archive). NOTES.md, "End of
  milestone 8: spec, archive tag and merge", lists the paths removed from `main`, with their sizes.

The reports regenerate on their tag, not on `main`, because each `report.py` reads the data files.

```sh
git fetch origin --tags
git worktree add ../m7-data m7-data       # milestone 7
(cd ../m7-data && python3 eval/report.py && git diff --exit-code EVAL.md)

git worktree add ../m8-data m8-data       # milestone 8
cd ../m8-data
python3 eval/m8a/report.py                # PROBE.md
python3 eval/m8b/report.py                # DIAG.md
python3 eval/m8c1/report.py               # SCALE.md
python3 eval/m8c2a/report.py              # R3SIM.md
python3 eval/m8d/report.py                # EVAL8.md
git diff --exit-code eval/                # each must equal the committed one
```

Remove a worktree with `git worktree remove ../m8-data` (or `../m7-data`) when you are done.

On `main`, where the data is absent, each milestone 8 `report.py` checks first that the data files it reads
are present, and otherwise prints "the data for this report is on tag m8-data; see eval/README.md" and exits
with code 1, writing nothing. (Before milestone 9, `m8c1/report.py` and `m8c2a/report.py` overwrote their
reports with a "No data" stub; NOTES.md, "End of milestone 8".)

The commands that made the data (`Test/eval_driver.py`, `Test/m8*_run.py`, `Test/m8*_full.sh`, and the
executables in `lakefile.toml`) are on `main` too, but their inputs (the specs, the corpus, `inputs/`) are
only on the tags.
