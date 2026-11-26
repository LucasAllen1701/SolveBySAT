#!/usr/bin/env bash
# 8c-1 (M8_PLAN 3.1, 3.4.5): the off-switch. With both milestone 8 flags off and every other option
# at its default, the 54 encodings of eval/m8b/dimacs_md5.txt (the 36 named cases at their
# milestone 7 N, and the 18 SPEC 7.3 encodings) must be byte-identical to 8b's, which equal those of
# SolveBySat at 5820197. The files (about 1.3 GB) go to a scratch directory on disk, deleted after.
set -uo pipefail
cd "$(dirname "$0")/.."
lake build eval_run m8b_dimacs73 Test.EvalNamed >/dev/null || exit 1
dir=$(mktemp -d "$PWD/eval/.offswitch.XXXXXX")
trap 'rm -rf "$dir"' EXIT
.lake/build/bin/eval_run dimacs eval/m8b/specs_named_dimacs.jsonl "$dir" off || exit 1
.lake/build/bin/m8b_dimacs73 "$dir" off || exit 1
want=$(grep -v '^#' eval/m8b/dimacs_md5.txt | sort -k2)
got=$(cd "$dir" && md5sum *.cnf | sort -k2)
n=$(echo "$want" | wc -l)
if [ "$want" == "$got" ]; then
  echo "PASS off-switch: $n of $n DIMACS files byte-identical to eval/m8b/dimacs_md5.txt"
else
  diff <(echo "$want") <(echo "$got") | head -20
  echo "FAIL off-switch: DIMACS differs from eval/m8b/dimacs_md5.txt"; exit 1
fi
