# eval/

Milestone 7's evaluation (EVAL_PLAN.md) produced about 71 MB of data: run folders, the corpus and
annotation files, the specs, the scaling data and the forest dumps. On `main` this folder keeps only:

- `report.py`, which generates `EVAL.md`;
- `merge.py`, the merge rule of the 10.7 rerun (NOTES.md, "10.7: merge rule");
- `reviews/`, the hand reviews (7d-1 and 7d-2).

**The data is on the annotated tag `m7-data`** (the head of branch `eval-m7`, kept as an archive).
NOTES.md, "End of milestone 7: spec, archive tag and merge", lists every path removed here, with its size.

`EVAL.md` regenerates on `m7-data`, not on `main`, because `report.py` reads the data files. To regenerate
it, or to look at the data:

```sh
git fetch origin --tags
git worktree add ../m7-data m7-data       # a separate checkout of the archive
cd ../m7-data
python3 eval/report.py                    # writes EVAL.md; it must equal the committed one
git diff --exit-code EVAL.md
```

The run folders' commands (`Test/eval_driver.py`, `Test/capped.sh`, and the executables in `lakefile.toml`)
are on `main` too, but their inputs (`eval/specs_*.jsonl`, the corpus) are only on `m7-data`. Remove the
worktree with `git worktree remove ../m7-data` when you are done.
