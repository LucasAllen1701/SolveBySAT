#!/usr/bin/env python3
"""9a-2 (M9_PLAN 3.2, "The 8a proofs' rules"; 3.3): the inputs of the 9a-2 checks, from a worktree of tag m8-data.

  python3 Test/m9a2_setup.py M8DATA_WORKTREE

writes
  eval/m9a2/specs_11.jsonl     milestone 7's spec of each of the 11 rewriting proofs of 8a that used a substitution
                               or congruence rule (eval/m8a/PROBE.md, "Rewriting goals proved"), in that table's
                               order, with the baselines off and `nmax` = 8a's N (for `eval_run rules9a` and
                               `Test/eval_driver.py run`)
  eval/m9a2/rules8a_11.json    for each, 8a's N and the substitution and congruence rules its proof used, as
                               (kind, symbol, 8a position)
  eval/m9a2/specs_points.jsonl a copy of m8-data's eval/m8b/specs_points.jsonl (the 400 points of 3.3)
  eval/m9a2/inputs.md5         the md5 sums of the inputs read

Milestone 7's specs are `eval/m8a/inputs/specs_full.jsonl` on m8-data (its md5 is checked against
`eval/m8a/inputs/MD5SUMS`). The rules are read from 8a's results (eval/m8a/full/results.jsonl, field
`probe_extra_used`) and must match the table below, copied from PROBE.md.
"""
import hashlib, json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "eval", "m9a2")

# eval/m8a/PROBE.md, "Rewriting goals proved": the proofs that used a `_probe.<sym>.subst|congr.«i»` rule, with 8a's N
ELEVEN = [
    ("A/Int.le_of_add_le_add_left", 8, ["LE.le.subst.2", "LE.le.subst.3"]),
    ("A/Int32.toInt_inj", 5, ["Int32.toInt.congr.0"]),
    ("A/Std.Tactic.BVDecide.Normalize.BitVec.signExtend_elim'", 5, ["Eq.subst.1"]),
    ("A/String.Slice.Pattern.Model.isLongestRevMatchAtChain_skipSuffixWhile", 4,
     ["String.Slice.Pattern.Model.IsLongestRevMatchAtChain.subst.4"]),
    ("A/String.back?_eq", 8, ["Eq.subst.1", "List.getLast?.congr.1", "String.toList.congr.0"]),
    ("B/Int.ediv_gcd_ne_zero_of_ne_zero_right/5", 2, ["Nat.cast.congr.2"]),
    ("B/Int32.toInt_div_of_ne_left/24", 5, ["Eq.subst.1", "Int.tdiv.congr.0", "Int.tdiv.congr.1"]),
    ("B/Nat.gcd_def/2", 4, ["Eq.subst.2"]),
    ("B/Nat.le.intro/0", 4, ["LE.le.subst.3"]),
    ("B/Nat.toList_repr/0", 4, ["Eq.subst.1", "String.toList.congr.0"]),
    ("B/Option.choice_eq_some/9", 3, ["Option.some.congr.1"]),
]


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def main():
    w = sys.argv[1]
    sfull = os.path.join(w, "eval/m8a/inputs/specs_full.jsonl")
    sums = dict(reversed(l.split()) for l in open(os.path.join(w, "eval/m8a/inputs/MD5SUMS")) if l.strip())
    if sums.get("specs_full.jsonl") != md5(sfull):
        print("STOP: specs_full.jsonl does not match eval/m8a/inputs/MD5SUMS"); return 5
    m7 = {j["key"]: j for j in map(json.loads, open(sfull))}
    res8a = os.path.join(w, "eval/m8a/full/results.jsonl")
    a8 = {}
    for l in open(res8a):
        if l.strip():
            j = json.loads(l)
            a8[j["key"]] = j
    os.makedirs(OUT, exist_ok=True)
    rules = {}
    with open(os.path.join(OUT, "specs_11.jsonl"), "w") as f:
        for gid, n, used in ELEVEN:
            r = a8["m8a:main:" + gid]
            if r.get("outcome") != "proved" or r.get("N") != n:
                print(f"STOP: 8a's record of {gid} is {r.get('outcome')} at {r.get('N')}, not proved at {n}"); return 5
            got = sorted(re.sub(r"«(\d+)»", r"\1", u[len("_probe."):]) for u in r.get("probe_extra_used", [])
                         if u.startswith("_probe.") and (".subst." in u or ".congr." in u))
            if got != sorted(used):
                print(f"STOP: 8a's rules of {gid} are {got}, PROBE.md says {sorted(used)}"); return 5
            f.write(json.dumps(dict(m7["main:" + gid], baselines=False, nmax=n), sort_keys=True) + "\n")
            rules[gid] = {"N": n, "rules": [[u.rsplit(".", 2)[1], u.rsplit(".", 2)[0], int(u.rsplit(".", 2)[2])]
                                             for u in used]}
    json.dump(rules, open(os.path.join(OUT, "rules8a_11.json"), "w"), indent=1, sort_keys=True)
    pts = os.path.join(w, "eval/m8b/specs_points.jsonl")
    shutil.copyfile(pts, os.path.join(OUT, "specs_points.jsonl"))
    with open(os.path.join(OUT, "inputs.md5"), "w") as f:
        for p, name in [(sfull, "eval/m8a/inputs/specs_full.jsonl"), (res8a, "eval/m8a/full/results.jsonl"),
                        (pts, "eval/m8b/specs_points.jsonl")]:
            f.write(f"{md5(p)}  m8-data:{name}\n")
        for n in (5, 10):
            p = os.path.join(w, f"eval/m8c1/sizes_N{n}/results.jsonl")
            f.write(f"{md5(p)}  m8-data:eval/m8c1/sizes_N{n}/results.jsonl\n")
    print(f"wrote {len(ELEVEN)} specs, their 8a rules, and the 400 points to eval/m9a2/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
