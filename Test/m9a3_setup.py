#!/usr/bin/env python3
"""9a-3 (M9_PLAN 4.1, 4.2, 4.4, amendment 6.2): the sample, the specs and the stop-rule expectations, from the
inputs extracted into eval/m9a3/inputs/ (from tags m8-data and m7-data; their md5 sums are in eval/m9a3/inputs.md5).

  python3 Test/m9a3_setup.py

writes
  eval/m9a3/sample.tsv     groups 2 and 3 (4.2): `<group>\\t<key>`, rewrite_B (100), rewrite_A (50), control (50), in
                           rank order (SHA-256 of "90301:<key>", ascending, ties by key); md5 must be
                           b311e0be3034d3e1f139135cebbb9c76
  eval/m9a3/specs.jsonl    one spec per run: group 1 (8a's 200 specs, in 8a's spec order), then the sample's 200;
                           each is milestone 7's spec of the goal (H and tier) with the baselines off, plus `group`
  eval/m9a3/expect.jsonl   per run: the group, the earlier outcome and N (8c-1's rerun for group 1, milestone 7's for
                           groups 2 and 3), whether the lost-proof rule of 4.4 applies (group 1 with an empty
                           `probe_extra_used`, 6.2 decision 6; group 3), and milestone 7's UNSAT N (groups 2 and 3,
                           for the exactness rule), read as `Test/eval_driver.py`'s reference_of reads a record
Any check that fails stops with exit 5, writing nothing further.
"""
import hashlib, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "eval", "m9a3")
INP = os.path.join(OUT, "inputs")
sys.path.insert(0, os.path.join(ROOT, "Test"))
from eval_driver import reference_of  # noqa: E402

PINNED = {"m8-data__m8a__inputs__population.jsonl": "69230cf475e193ded9bc224bba49832f",
          "m7-data__final__results.jsonl": "944cc58e53ee2b4ce17ee1e83d29bab1"}
SAMPLE_MD5 = "b311e0be3034d3e1f139135cebbb9c76"
FIRST = {"rewrite_B": "main:B/Int8.ofNat_bitVecToNat/4", "rewrite_A": "main:A/Array.elem_eq_contains",
         "control": "main:B/Or.resolve_left/2"}
POP = {"rewrite_B": 846, "rewrite_A": 472, "control": 878}
TAKE = {"rewrite_B": 100, "rewrite_A": 50, "control": 50}


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def jl(name):
    return [json.loads(l) for l in open(os.path.join(INP, name)) if l.strip()]


def rank(keys):
    return sorted(keys, key=lambda k: (hashlib.sha256(f"90301:{k}".encode()).hexdigest(), k))


def stop(msg):
    print("STOP: " + msg)
    sys.exit(5)


def main():
    for f, m in PINNED.items():
        if md5(os.path.join(INP, f)) != m:
            stop(f"{f} has md5 {md5(os.path.join(INP, f))}, not {m}")
    pop = jl("m8-data__m8a__inputs__population.jsonl")
    goals8a = jl("m8-data__m8a__goals.jsonl")
    used8a = {g["key"] for g in goals8a}
    m7 = {r["key"]: r for r in jl("m7-data__final__results.jsonl")}
    controls8a = {r["key"] for r in jl("m8-data__m8a__inputs__scaling_goals.jsonl")}
    controls8d = {l.split("\t")[1].strip() for l in open(os.path.join(INP, "m8-data__m8d__sample.tsv"))
                  if l.startswith("control_proved\t")}
    groups = {
        "rewrite_B": [p["key"] for p in pop if p["tier"] == "B" and p["key"] not in used8a],
        "rewrite_A": [p["key"] for p in pop if p["tier"] == "A" and p["key"] not in used8a],
        "control": [k for k, r in m7.items() if r.get("run") == "main" and r["outcome"] == "proved"
                    and k not in controls8a and k not in controls8d]}
    for g, ks in groups.items():
        if len(ks) != POP[g] or len(set(ks)) != len(ks):
            stop(f"group {g} has {len(ks)} goals ({len(set(ks))} distinct), not {POP[g]}")
    sample = [(g, k) for g in ("rewrite_B", "rewrite_A", "control") for k in rank(groups[g])[:TAKE[g]]]
    os.makedirs(OUT, exist_ok=True)
    sp = os.path.join(OUT, "sample.tsv")
    with open(sp, "w") as f:
        for g, k in sample:
            f.write(f"{g}\t{k}\n")
    for g in FIRST:
        first = next(k for gg, k in sample if gg == g)
        if first != FIRST[g]:
            stop(f"the first key of {g} is {first}, not {FIRST[g]}")
    if md5(sp) != SAMPLE_MD5:
        stop(f"sample.tsv has md5 {md5(sp)}, not {SAMPLE_MD5}")
    specs7 = {s["key"]: s for s in jl("m7-data__specs_full.jsonl")}
    rerun = {r["key"]: r for r in jl("m8-data__m8c1__rerun__results.jsonl")}
    specs8a = jl("m8-data__m8a__specs.jsonl")
    if len(specs8a) != 200:
        stop(f"8a's spec file has {len(specs8a)} specs")
    runs = []
    for s in specs8a:
        k = s["key"][len("m8a:"):]
        r = rerun[s["key"]]
        lost = r["outcome"] == "proved" and not r.get("probe_extra_used")
        runs.append(("g1_" + s["probe_group"], k, r, lost, None))
    for g, k in sample:
        r = m7[k]
        unsat, _ = reference_of(r)
        runs.append((g, k, r, g == "control", sorted(unsat)))
    keys = [k for _, k, _, _, _ in runs]
    if len(set(keys)) != 400:
        stop(f"{len(set(keys))} distinct keys in 400 runs")
    with open(os.path.join(OUT, "specs.jsonl"), "w") as f, open(os.path.join(OUT, "expect.jsonl"), "w") as e:
        for g, k, r, lost, unsat in runs:
            s = dict(specs7[k], baselines=False, group=g)
            f.write(json.dumps(s, sort_keys=True) + "\n")
            rec = {"key": k, "group": g, "earlier": "8c-1" if g.startswith("g1_") else "m7",
                   "earlier_outcome": r["outcome"], "earlier_N": r.get("N") if r["outcome"] == "proved" else None,
                   "lost_rule": lost}
            if g.startswith("g1_"):
                rec["probe_extra_used"] = r.get("probe_extra_used", [])
            if unsat is not None:
                rec["m7_unsat"] = unsat
            e.write(json.dumps(rec, sort_keys=True) + "\n")
    n1 = sum(1 for g, _, r, _, _ in runs if g.startswith("g1_") and r["outcome"] == "proved")
    n1l = sum(1 for g, _, _, lost, _ in runs if g.startswith("g1_") and lost)
    with open(os.path.join(OUT, "setup.txt"), "w") as f:
        f.write(f"group populations: " + ", ".join(f"{g} {len(groups[g])}" for g in groups) + "\n")
        f.write(f"sample.tsv md5 {md5(sp)}\n")
        f.write(f"group 1: 8c-1 proved {n1}, of which with an empty probe_extra_used {n1l}\n")
        for p in ("specs.jsonl", "expect.jsonl"):
            f.write(f"{p} md5 {md5(os.path.join(OUT, p))}\n")
    print(open(os.path.join(OUT, "setup.txt")).read(), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
