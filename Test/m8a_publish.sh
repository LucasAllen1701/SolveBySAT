#!/bin/bash
# 8a full run (M8_PLAN 2.6): after-shard hook. Update OUTDIR/STATUS.md, commit OUTDIR only, push m8.
#   m8a_publish.sh OUTDIR SPECS PHASE [MESSAGE]
set -u
cd "$(dirname "$0")/.."
OUT=$1; SPECS=$2; PHASE=$3; MSG=${4:-"8a full run: $PHASE"}
python3 Test/m8a_run.py status "$OUT" "$SPECS" "$PHASE" || echo "status failed"
git add -- "$OUT"
git commit -q -m "$MSG

$(grep -E '^- (Goals done|Stops|Sizes done)' "$OUT/STATUS.md")

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "$OUT" || echo "nothing to commit"
[ "$(git rev-parse --abbrev-ref HEAD)" = m8 ] || { echo "not on m8: not pushing"; exit 1; }
for i in 1 2 3; do git push -q origin m8 && exit 0; sleep 30; done
echo "push failed (will retry after the next shard)"; exit 1
