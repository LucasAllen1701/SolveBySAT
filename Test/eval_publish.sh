#!/bin/bash
# After-shard hook of the 7b full run (EVAL_PLAN 10.5 decision 6): update OUTDIR/STATUS.md,
# commit OUTDIR (and NOTES.md when asked) and push to eval-m7.
#   eval_publish.sh OUTDIR [MESSAGE] [--rc RC] [--with-notes]
set -u
cd "$(dirname "$0")/.."
OUT=$1; MSG=${2:-"eval: $(basename "$OUT") progress"}; shift; shift || true
RC=""; NOTES=""
while [ $# -gt 0 ]; do case $1 in --rc) RC=$2; shift;; --with-notes) NOTES=NOTES.md;; esac; shift; done
python3 Test/eval_status.py "$OUT" ${RC:+--rc $RC} || echo "status script failed"
git add -- "$OUT" $NOTES
git commit -q -m "$MSG

$(grep -E '^- (Shards|Goals done|Crashes)' "$OUT/STATUS.md")

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "$OUT" $NOTES || echo "nothing to commit"
for i in 1 2 3; do git push -q origin eval-m7 && exit 0; sleep 30; done
echo "push failed (will retry after the next shard)"; exit 1
