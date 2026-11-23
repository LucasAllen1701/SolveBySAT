#!/usr/bin/env python3
"""Milestone 7c, EVAL_PLAN §10.9 decision 7: `countOnly` sizes per family of each 4.2 run at its
goal's original N (the spec's `nmax`), so that R6 has clause counts even for runs that crash.

  python3 Test/eval_sizes.py SPECS OUT

Runs `eval_run sizes SPECS OUT STARTED` under the 2.5 GB cap (`Test/capped.sh`). If the process
dies, the spec it had started is recorded with status `memout` (killed by the cap) or
`crash` (any other exit), and the process is restarted on the remaining specs. Nothing is solved.
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []


def main(specs, out):
    started = out.replace(".jsonl", ".started.jsonl")
    keys = [s["key"] for s in load(specs)]
    while True:
        done = {r["key"] for r in load(out)}
        if all(k in done for k in keys):
            break
        n0 = len(load(started))
        p = subprocess.run([os.path.join(ROOT, "Test/capped.sh"), os.path.join(ROOT, ".lake/build/bin/eval_run"),
                            "sizes", specs, out, started], cwd=ROOT, capture_output=True, text=True)
        if p.returncode == 0:
            continue
        done = {r["key"] for r in load(out)}
        lost = [r["key"] for r in load(started)[n0:] if r["key"] not in done]
        if not lost:
            print(f"sizes: process exited {p.returncode} with no spec in progress: {p.stderr[-300:]}"); return 4
        status = "memout" if p.returncode in (137, -9) else "crash"
        with open(out, "a") as f:
            f.write(json.dumps({"key": lost[-1], "status": status, "exit": p.returncode}) + "\n")
        print(f"sizes: {lost[-1]}: {status} (exit {p.returncode})", flush=True)
    print(f"sizes: {len(keys)} specs done")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
