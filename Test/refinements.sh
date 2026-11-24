#!/usr/bin/env bash
# Milestone 6, requirement 1 (and 8c-1: R1 `bounds`, R2 `exclusive`): each refinement switched on alone (the others off), through
# the forest tests and all three differential tests (plain, binders, data) at full size.
set -uo pipefail
cd "$(dirname "$0")/.."
lake build test_m1 test_m5 >/dev/null || exit 1
status=0
for cfg in symmetry pair candidate frame ladder bounds exclusive; do
  echo "== refinement alone: $cfg"
  .lake/build/bin/test_m1 1500 4 "$cfg" | grep -E "^(FAIL|MISMATCH)|differential|mutation|^M1:" || status=1
  .lake/build/bin/test_m5 3000 4 "$cfg" | grep -E "^(FAIL|MISMATCH)|differential|mutation|^M5:" || status=1
done
exit $status
