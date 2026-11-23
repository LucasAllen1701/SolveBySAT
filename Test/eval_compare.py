#!/usr/bin/env python3
"""Calibration (EVAL_PLAN §10.5 decision 5): compare a rerun of the pilot with the
development machine's pilot, goal by goal.

  eval_compare.py DEV_DIR NEW_DIR [SPECS]

Stop (exit 1) on any decoder bug in NEW_DIR, or a different proved N: both runs proved the
goal at different N, or one proved it and the other gave a deterministic outcome
(no_proof_le_Nmax, goal_rejected, limitation, compile_error). Every other difference is
listed, to be explained:
  - resource: a timeout, memout or crash on one side only, or at a different N;
  - baseline: sbe_default or library_search differs (sbe_like changed by design, decision 3,
    and is listed separately).
"""
import collections, json, sys

DET = {"no_proof_le_Nmax", "goal_rejected", "limitation", "compile_error"}
RES = {"timeout", "memout", "crash"}


def load(p):
    out = {}
    for l in open(p):
        try:
            r = json.loads(l)
        except json.JSONDecodeError:
            continue
        out[r["key"]] = r
    return out


def sat(r):
    o = r["outcome"]
    if o == "proved":
        return f"proved({r['N']})"
    if o == "crash":
        return f"crash({r.get('cause')}, last_N {r.get('last_N')})"
    if o in ("timeout", "memout"):
        return f"{o}({r.get('N')}, {r.get('timeout_kind') or r.get('memout_kind')})"
    return o


def bl(r, name):
    b = r.get("baselines")
    if not isinstance(b, dict):
        return None
    x = b.get(name) or {}
    if name == "library_search":
        return (x.get("exact"), x.get("apply")) if "exact" in x else x.get("outcome")
    return x.get("outcome")


def main():
    dev, new = load(sys.argv[1] + "/results.jsonl"), load(sys.argv[2] + "/results.jsonl")
    specs = [json.loads(l)["key"] for l in open(sys.argv[3] if len(sys.argv) > 3 else "eval/specs_pilot.jsonl")]
    stop, resource, other, base, like = [], [], [], [], []
    same = 0
    for k in specs:
        a, b = dev.get(k), new.get(k)
        if a is None or b is None:
            stop.append((k, "missing result", a and sat(a), b and sat(b)))
            continue
        if b["outcome"] in ("decoder_bug", "solver_error", "harness_error"):
            stop.append((k, b["outcome"], sat(a), str(b.get("reason"))[:200]))
            continue
        sa, sb = sat(a), sat(b)
        pa, pb = a["outcome"] == "proved", b["outcome"] == "proved"
        if sa == sb:
            same += 1
        elif (pa and pb) or (pa and b["outcome"] in DET) or (pb and a["outcome"] in DET):
            stop.append((k, "different proved N", sa, sb))
        elif a["outcome"] in RES or b["outcome"] in RES:
            resource.append((k, sa, sb, a.get("H_size") or b.get("H_size")))
        else:
            other.append((k, sa, sb))
        for name in ("sbe_default", "library_search"):
            x, y = bl(a, name), bl(b, name)
            if x is not None and y is not None and x != y:
                base.append((k, name, x, y))
        x, y = bl(a, "sbe_like"), bl(b, "sbe_like")
        if x is not None and y is not None and x != y:
            like.append((k, x, y))
    n_bl_dev = sum(1 for k in specs if k in dev and isinstance(dev[k].get("baselines"), dict))
    n_bl_new = sum(1 for k in specs if k in new and isinstance(new[k].get("baselines"), dict))
    print(f"{len(specs)} goals; solve_by_sat outcome identical: {same}")
    print(f"goals with baselines: development {n_bl_dev}, this machine {n_bl_new}")
    print(f"\nSTOP conditions (decoder bug, different proved N): {len(stop)}")
    for x in stop:
        print("  ", *x)
    print(f"\nresource differences (timeout / memout / crash on one side or at another N): {len(resource)}")
    for k, sa, sb, h in resource:
        print(f"   {k}  |H| {h}: dev {sa}  →  here {sb}")
    print(f"\nother solve_by_sat differences: {len(other)}")
    for x in other:
        print("  ", *x)
    print(f"\nbaseline differences (sbe_default, library_search; both sides present): {len(base)}")
    for x in base:
        print("  ", *x)
    c = collections.Counter((x, y) for _, x, y in like)
    print(f"\nsbe_like changes (decision 3, expected): {len(like)}  " + ", ".join(f"{x}→{y} {n}" for (x, y), n in c.most_common()))
    for x in like:
        print("  ", *x)
    return 1 if stop else 0


if __name__ == "__main__":
    sys.exit(main())
