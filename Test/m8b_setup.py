#!/usr/bin/env python3
"""Milestone 8b (M8_PLAN.md §4.3): the measurement points and their specs.

  python3 Test/m8b_setup.py inputs M7DATA   copy the 36 named specs and their milestone 7 results
                                            (eval/fix_check3/named) from a checkout of tag m7-data
  python3 Test/m8b_setup.py specs           write the spec files below, from eval/m8a/ and eval/m8b/inputs/

Spec files (eval/m8b/):
  specs_points.jsonl   M1-M4: the 200 goals of 8a, each with the 8a rules (amendment 4.1; `probe`) and
                       with milestone 7's H (the accepted H_main, no rules): 400 points, all at N = 5
                       (the N is given on the command line, not in the spec)
  specs_models.jsonl   M5: the 64 proved runs of eval/m8a/full/, at the N where each was proved, with the rules
  specs_named.jsonl    the M4 check on the 36 named cases: those with a proof in eval/fix_check3/named, at its N
"""
import hashlib, json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M8A = os.path.join(ROOT, "eval", "m8a")
OUT = os.path.join(ROOT, "eval", "m8b")
INP = os.path.join(OUT, "inputs")


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def dump(p, rows):
    with open(p, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def inputs(m7):
    os.makedirs(INP, exist_ok=True)
    shutil.copyfile(os.path.join(m7, "eval", "specs_named.jsonl"), os.path.join(INP, "specs_named_m7.jsonl"))
    shutil.copyfile(os.path.join(m7, "eval", "fix_check3", "named", "results.jsonl"), os.path.join(INP, "named_results_m7.jsonl"))
    with open(os.path.join(INP, "MD5SUMS"), "w") as f:
        for x in sorted(os.listdir(INP)):
            if x != "MD5SUMS":
                f.write(f"{md5(os.path.join(INP, x))}  {x}\n")
    print(open(os.path.join(INP, "MD5SUMS")).read())


def specs():
    sp = load(os.path.join(M8A, "specs.jsonl"))
    pts = []
    for s in sp:
        for v in ("rules", "norules"):
            pts.append(dict(s, key=f"m8b:{v}:{s['key'][4:]}", probe=(v == "rules"), m8b_variant=v))
    dump(os.path.join(OUT, "specs_points.jsonl"), pts)
    res = {r["key"]: r for r in load(os.path.join(M8A, "full", "results.jsonl"))}
    mods = [dict(s, key=f"m8b:model:{s['key'][4:]}", nmax=res[s["key"]]["N"], m8a_N=res[s["key"]]["N"])
            for s in sp if res[s["key"]]["outcome"] == "proved"]
    dump(os.path.join(OUT, "specs_models.jsonl"), mods)
    nres = {r["key"]: r for r in load(os.path.join(INP, "named_results_m7.jsonl"))}
    named = [dict(s, nmax=nres[s["key"]]["N"], m7_N=nres[s["key"]]["N"], baselines=False)
             for s in load(os.path.join(INP, "specs_named_m7.jsonl")) if nres[s["key"]]["outcome"] == "proved"]
    dump(os.path.join(OUT, "specs_named.jsonl"), named)
    for p in ("specs_points.jsonl", "specs_models.jsonl", "specs_named.jsonl"):
        print(f"{md5(os.path.join(OUT, p))[:12]}  eval/m8b/{p}  {len(load(os.path.join(OUT, p)))} specs")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["inputs"] and len(a) == 2:
        inputs(a[1])
    elif a == ["specs"]:
        specs()
    else:
        print(__doc__); sys.exit(2)
