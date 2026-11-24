#!/usr/bin/env bash
# Build and run the acceptance tests of every milestone implemented so far.
set -euo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp)
if ! lake build SolveBySat test_m0 test_m1 test_m4 test_m5 bench test_countonly test_m8diag >"$log" 2>if ! lake build SolveBySat test_m0 test_m1 test_m4 test_m5 bench test_countonly >"$log" 2>&1; then1; then
  grep -v '^trace' "$log"; rm -f "$log"; exit 1
fi
grep -v '^trace' "$log" | tail -1; rm -f "$log"
status=0
for t in test_m0 test_m1 test_m4 test_m5 test_countonly test_m8diag; do
  echo "== $t"
  ".lake/build/bin/$t" || status=1
done
for f in Test/M2.lean Test/M3.lean Test/M4Lean.lean Test/M5Lean.lean Test/M7Lean.lean Test/M8Probe.lean; do
  echo "== $f"
  lake env lean "$f" || status=1
done
exit $status
