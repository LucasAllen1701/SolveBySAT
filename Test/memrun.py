#!/usr/bin/env python3
"""Run a command and report its peak RSS (MB) and wall time, via os.wait4.
Usage: memrun.py [--vlimit-mb M] cmd args...   (exit code passed through)"""
import os, sys, time, resource
args = sys.argv[1:]
vlimit = None
if args and args[0] == "--vlimit-mb":
    vlimit = int(args[1]); args = args[2:]
t0 = time.monotonic()
pid = os.fork()
if pid == 0:
    if vlimit:
        resource.setrlimit(resource.RLIMIT_AS, (vlimit << 20, vlimit << 20))
    os.execvp(args[0], args)
_, status, ru = os.wait4(pid, 0)
print(f"[memrun] peak {ru.ru_maxrss / 1024:.0f} MB, wall {time.monotonic() - t0:.1f} s, status {os.waitstatus_to_exitcode(status)}", file=sys.stderr)
sys.exit(max(0, os.waitstatus_to_exitcode(status)))
