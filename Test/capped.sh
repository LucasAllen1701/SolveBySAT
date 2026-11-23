#!/bin/sh
# Run a command under the milestone 7 memory cap (NOTES.md: cgroup, 2.5 GB, no swap),
# reporting peak RSS and wall time. Usage: Test/capped.sh cmd args…
exec systemd-run --user --scope -q -p MemoryMax=${CAP_MB:-2500}M -p MemorySwapMax=0 \
  python3 "$(dirname "$0")/memrun.py" "$@"
