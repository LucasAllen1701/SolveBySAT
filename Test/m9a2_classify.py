#!/usr/bin/env python3
"""9a-2 (M9_PLAN 3.2, amendment 6.1 clarification 4): classify the differences of the Lean suite with `rewrite`
(and with selection dropped) from the logs `Test/m9a2_lean.sh` keeps (M9A2_KEEP=1).

  python3 Test/m9a2_classify.py LOGDIR [SETTING ...]      (default settings: on liberal)

For each file of the suite and each setting, each `#guard_msgs` that does not match is classified from its diff
(`-` the expected message, `+` the generated one):
  gained   an expected "no proof" error is gone and a proof is reported or nothing fails (an expected failure
           that became a proof: recorded, not a failure of the check);
  lost     a "no proof" (or other) error appears where none was expected (a proof lost: a FAIL);
  message  the outcome is the same and only messages differ (the `verbose` lines that list the rules, CNF sizes);
and every error outside a `#guard_msgs` (a tactic that was expected to succeed) is `unguarded` (a FAIL).
Prints one line per difference and a summary; exit 1 if any `lost` or `unguarded`.
"""
import os, re, sys

FILES = ["M2", "M3", "M4Lean", "M5Lean", "M7Lean", "M8Probe", "M8C1Lean", "M9Lean"]


def parse(path, fname):
    lines = open(path).read().split("\n")
    guards, errors = [], []
    pat = re.compile(r"^Test/" + re.escape(fname) + r"\.lean:(\d+):(\d+): error: (.*)$")
    i = 0
    while i < len(lines):
        m = pat.match(lines[i])
        if m and m.group(3).startswith("❌️ Docstring on `#guard_msgs`"):
            g = int(m.group(1)); i += 1
            block = []
            while i < len(lines) and not pat.match(lines[i]) and not lines[i].startswith("Test/"):
                block.append(lines[i]); i += 1
            guards.append((g, block))
            continue
        if m:
            errors.append((int(m.group(1)), m.group(3)))
        i += 1
    return guards, errors


def classify(block):
    minus = "\n".join(l[2:] for l in block if l.startswith("- "))
    plus = "\n".join(l[2:] for l in block if l.startswith("+ "))
    ctx = "\n".join(l[2:] for l in block if l.startswith("  "))
    exp_err = ("error:" in minus) or ("error:" in ctx)
    got_err = ("error:" in plus) or ("error:" in ctx)
    if "error:" in minus and "error:" not in plus and "error:" not in ctx:
        return "gained"
    if "error:" in plus and "error:" not in minus and "error:" not in ctx:
        return "lost"
    if "no proof" in minus and "proof with" in plus:
        return "gained"
    if "proof with" in minus and "no proof" in plus:
        return "lost"
    return "message" if exp_err == got_err else "lost"


def main(a):
    d = a[0]
    settings = a[1:] or ["on", "liberal"]
    bad = 0
    tally = {}
    for st in settings:
        for f in FILES:
            p = os.path.join(d, f"{st}.{f}.lean.log")
            if not os.path.exists(p):
                print(f"{st} {f}: no log"); continue
            guards, errors = parse(p, f)
            gl = [g for g, _ in guards]
            for g, block in guards:
                c = classify(block)
                tally[(st, c)] = tally.get((st, c), 0) + 1
                first = next((l[2:] for l in block if l.startswith("- ") or l.startswith("+ ")), "")[:150]
                print(f"{st} {f}.lean:{g} {c}: {first}")
                if c == "lost":
                    bad += 1
            # an error not followed (within the command) by a guard mismatch is unguarded
            for (L, msg) in errors:
                if any(g < L <= g + 25 for g in gl):
                    continue
                if msg.startswith("❌️"):
                    continue
                print(f"{st} {f}.lean:{L} unguarded: {msg[:150]}")
                tally[(st, "unguarded")] = tally.get((st, "unguarded"), 0) + 1
                bad += 1
    print("summary: " + ", ".join(f"{s} {c} {n}" for (s, c), n in sorted(tally.items())))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
