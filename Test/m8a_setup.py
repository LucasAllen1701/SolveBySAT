#!/usr/bin/env python3
"""Milestone 8a (M8_PLAN.md §2.2, §2.8): the probe's inputs, sample and specs.

  python3 Test/m8a_setup.py inputs M7DATA     extract eval/m8a/inputs/ from a checkout of tag m7-data
  python3 Test/m8a_setup.py sample            eval/m8a/goals.jsonl (§2.2), from eval/m8a/inputs/ only
  python3 Test/m8a_setup.py specs             eval/m8a/specs.jsonl (200 runs) and specs_pilot.jsonl (20)

`inputs` computes the E5 population (main-run goals the compiler accepts, not proved in eval/final/,
whose obstacles all fall in family 3A) with m7-data's own eval/report.py, checks it is 522 Tier A and
946 Tier B (EVAL.md E5), and copies the records of those goals and of the 50 scaling goals:
  corpus.jsonl     corpus records (eval/corpus_A.jsonl, corpus_B.jsonl)
  hcompile.jsonl   compiler verdicts (eval/corpus_hcompile.jsonl)
  final.jsonl      final results (eval/final/results.jsonl)
  specs_full.jsonl milestone 7's specs of the same goals (H in run order, thm, pos, nctx)
  population.jsonl the E5 population: key, tier, obstacles and their families
and eval/m8_families.json, eval/m8_obstacles.jsonl, eval/scaling_goals.jsonl as they are.
It writes eval/m8a/inputs/MD5SUMS. Every later step reads only eval/m8a/inputs/.

The hash rule (EVAL_PLAN 10.8 decision 4, as fixed in NOTES.md 7c): an item's rank key is the
SHA-256 hex digest of "<seed>:<item>", ascending, ties broken by the item; the item is the goal key.
"""
import hashlib, json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "eval", "m8a")
INP = os.path.join(OUT, "inputs")
SEED = 80101
N_B, N_A = 100, 50
EXPECT = {"A": 522, "B": 946}
EQ = ["Eq.refl", "Eq.symm", "Eq.trans"]


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def dump(p, rows):
    with open(p, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def rank_key(item):
    return (hashlib.sha256(f"{SEED}:{item}".encode()).hexdigest(), item)


def inputs(m7):
    sys.path.insert(0, os.path.join(m7, "eval"))
    import report as R   # m7-data's own report.py, reading m7-data's eval/
    d = R.Data()
    pop = {}
    for t in "AB":
        ks = [k for k in R.m8_population(d, t)
              if {R.m8_family(d, x) for x in R.m8_obstacles(d, k)} == {"3A"}]
        if len(ks) != EXPECT[t]:
            print(f"STOP: E5 population of Tier {t} is {len(ks)}, EVAL.md E5 says {EXPECT[t]}"); sys.exit(5)
        for k in ks:
            obs = R.m8_obstacles(d, k)
            pop[k] = {"key": k, "tier": t, "id": d.specs[k]["id"], "obstacles": obs,
                      "families": [R.m8_family(d, x) for x in obs]}
    ctrl = load(os.path.join(m7, "eval", "scaling_goals.jsonl"))
    keys = sorted(set(pop) | {g["key"] for g in ctrl})
    ids = {d.specs[k]["id"] for k in keys}
    os.makedirs(INP, exist_ok=True)
    corpus = [r for t in "AB" for r in load(os.path.join(m7, "eval", f"corpus_{t}.jsonl"))
              if "header" not in r and r["id"] in ids]
    dump(os.path.join(INP, "corpus.jsonl"), sorted(corpus, key=lambda r: r["id"]))
    hc = [r for r in load(os.path.join(m7, "eval", "corpus_hcompile.jsonl")) if r["id"] in ids]
    dump(os.path.join(INP, "hcompile.jsonl"), sorted(hc, key=lambda r: r["id"]))
    dump(os.path.join(INP, "final.jsonl"), [d.res[k] for k in keys])
    dump(os.path.join(INP, "specs_full.jsonl"), [d.specs[k] for k in keys])
    dump(os.path.join(INP, "population.jsonl"), [pop[k] for k in sorted(pop)])
    for f in ("m8_families.json", "m8_obstacles.jsonl", "scaling_goals.jsonl"):
        shutil.copyfile(os.path.join(m7, "eval", f), os.path.join(INP, f))
    files = sorted(f for f in os.listdir(INP) if f != "MD5SUMS")
    with open(os.path.join(INP, "MD5SUMS"), "w") as f:
        for x in files:
            f.write(f"{md5(os.path.join(INP, x))}  {x}\n")
    print(f"population: Tier A {sum(1 for p in pop.values() if p['tier'] == 'A')}, "
          f"Tier B {sum(1 for p in pop.values() if p['tier'] == 'B')}; controls {len(ctrl)}; "
          f"records for {len(keys)} goals")
    for x in files:
        print(f"  {md5(os.path.join(INP, x))[:12]}  {x}  {len(open(os.path.join(INP, x), 'rb').read()):,} bytes")


def sample():
    pop = load(os.path.join(INP, "population.jsonl"))
    specs = {s["key"]: s for s in load(os.path.join(INP, "specs_full.jsonl"))}
    hc = {r["id"]: r for r in load(os.path.join(INP, "hcompile.jsonl"))}
    final = {r["key"]: r for r in load(os.path.join(INP, "final.jsonl"))}
    ctrl = load(os.path.join(INP, "scaling_goals.jsonl"))
    rows = []

    def row(k, group, rank, extra):
        s = specs[k]
        acc = set(hc[s["id"]]["main"]["accepted"])
        return dict({"key": k, "id": s["id"], "tier": s["tier"], "group": group, "rank": rank,
                     "hash": rank_key(k)[0][:16], "thm": s["thm"], "pos": s.get("pos", 0), "nctx": s.get("nctx", 0),
                     "H_main": s["H"], "H_main_accepted": [c for c in s["H"] if c in acc],
                     "m7_outcome": final[k]["outcome"], "m7_N": final[k].get("N")}, **extra)
    for t, n in (("B", N_B), ("A", N_A)):
        ks = sorted((p["key"] for p in pop if p["tier"] == t), key=rank_key)[:n]
        rows += [row(k, f"rewrite_{t}", i, {}) for i, k in enumerate(ks)]
    cks = sorted((g["key"] for g in ctrl), key=rank_key)
    cg = {g["key"]: g for g in ctrl}
    rows += [row(k, "control", i, {"orig_N": cg[k]["N"], "bucket": cg[k]["bucket"]}) for i, k in enumerate(cks)]
    # the controls' accepted H_main must agree with milestone 7's record of them
    for r in rows:
        if r["group"] == "control" and sorted(r["H_main_accepted"]) != sorted(cg[r["key"]]["H_main_accepted"]):
            print(f"STOP: accepted H_main of {r['key']} differs from scaling_goals.jsonl"); sys.exit(5)
    dump(os.path.join(OUT, "goals.jsonl"), rows)
    import statistics
    for g in ("rewrite_B", "rewrite_A", "control"):
        rs = [r for r in rows if r["group"] == g]
        print(f"{g}: {len(rs)} goals; |H_main| median {statistics.median(len(r['H_main']) for r in rs)}, "
              f"accepted median {statistics.median(len(r['H_main_accepted']) for r in rs)}")


def specs():
    rows = load(os.path.join(OUT, "goals.jsonl"))
    out = []
    for r in rows:
        s = {"key": "m8a:" + r["key"], "id": r["id"], "run": "m8a", "tier": r["tier"], "thm": r["thm"],
             "pos": r["pos"], "nctx": r["nctx"], "H": r["H_main_accepted"], "probe": True,
             "probe_group": r["group"], "rank": r["rank"], "baselines": False,
             # the rule set the shard generates (Test/M8Rules.lean); recorded, not read by the shard
             "probe_rules": "amendment 4.1"}
        if r["group"] == "control":
            s.update({"nmax": r["orig_N"], "orig_N": r["orig_N"], "orig_outcome": "proved"})
        out.append(s)
    dump(os.path.join(OUT, "specs.jsonl"), out)
    pilot = ([s for s in out if s["probe_group"] == "rewrite_B" and s["rank"] < 10]
             + [s for s in out if s["probe_group"] == "rewrite_A" and s["rank"] < 5]
             + [s for s in out if s["probe_group"] == "control" and s["rank"] < 5])
    # the pilot's specs are its record (pilot rule set): written once, never rewritten
    if not os.path.exists(os.path.join(OUT, "specs_pilot.jsonl")):
        dump(os.path.join(OUT, "specs_pilot.jsonl"), pilot)
    print(f"specs: {len(out)}; pilot: {len(pilot)}")
    for p in ("specs.jsonl", "specs_pilot.jsonl", "goals.jsonl"):
        print(f"  {md5(os.path.join(OUT, p))[:12]}  eval/m8a/{p}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["inputs"] and len(a) == 2:
        inputs(a[1])
    elif a == ["sample"]:
        sample()
    elif a == ["specs"]:
        specs()
    else:
        print(__doc__); sys.exit(2)
