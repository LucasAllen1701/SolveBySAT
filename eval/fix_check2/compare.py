#!/usr/bin/env python3
"""Second decoder fix: compare the reruns with the results computed before the fix
(outcome, N, skeleton). Run from the repository root."""
import collections, json

def load(p):
    out = {}
    for l in open(p):
        try:
            r = json.loads(l)
        except json.JSONDecodeError:
            continue
        if "key" in r:
            out[r["key"]] = r

    return out

def sig(r):
    return (r.get("outcome"), r.get("N"), r.get("skeleton"))

D = "eval/fix_check2"
for name, old, new in [("named", load("eval/fix_check/named/results.jsonl"), load(f"{D}/named/results.jsonl")),
                       ("sat", {**load("eval/calib/pilot/results.jsonl"), **load("eval/full/results.jsonl")},
                        load(f"{D}/sat/results.jsonl"))]:
    keys = [json.loads(l)["key"] for l in open("eval/specs_named.jsonl" if name == "named" else f"{D}/specs.jsonl")]
    same, diff = 0, []
    for k in keys:
        a, b = old.get(k), new.get(k)
        if a and b and sig(a) == sig(b):
            same += 1
        else:
            diff.append((k, a and sig(a)[:2], b and sig(b)[:2], a and b and a.get("skeleton") == b.get("skeleton")))
    print(f"{name}: {len(keys)} goals; identical (outcome, N, skeleton): {same}")
    for d in diff:
        print("  DIFF", *d)
    print("  outcomes now:", collections.Counter(new[k]["outcome"] for k in keys if k in new))
