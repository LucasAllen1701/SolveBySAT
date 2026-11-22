#!/usr/bin/env python3
"""Milestone 7c, EVAL_PLAN §4.2 and §10.9 (4.2 decisions 1-7): set-up of the real-distractor runs.

  python3 Test/eval_scaling_real.py setup     write eval/scaling_goals.jsonl, eval/scaling_pool.jsonl,
                                               eval/specs_scaling.jsonl (550) and eval/specs_scaling_pilot.jsonl (44)

Inputs: eval/final/results.jsonl, eval/specs_full.jsonl, eval/corpus_hcompile.jsonl,
eval/scaling_pool_all.jsonl (`eval_pool pool`), and `eval_pool syms` (run here on the 50 goals).

Hash ranking (10.8 decision 4, 10.9 decisions 1 and 5): an item's rank key is the SHA-256 hex
digest of the UTF-8 string "<seed>:<item>" (goals: item = key; distractors: item =
"<goal key>:<constant name>"); items are sorted by that digest, ties (none expected) by item.
"""
import hashlib, json, os, subprocess, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
E = os.path.join(ROOT, "eval")
SEED_GOALS, SEED_RANDOM, SEED_NEAR = 70301, 70302, 70303
BUCKETS = [("1", lambda n: n == 1, 12), ("2", lambda n: n == 2, 12), ("3-4", lambda n: 3 <= n <= 4, 13),
           ("5+", lambda n: n >= 5, 13)]
KS = [2, 4, 8, 16, 32]
MODES = ["random", "near"]


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def hkey(seed, item):
    return hashlib.sha256(f"{seed}:{item}".encode()).hexdigest()


def ranked(seed, items, prefix=""):
    return sorted(items, key=lambda x: (hkey(seed, prefix + x), x))


def write(path, rows):
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")


def setup():
    fin = {r["key"]: r for r in load(os.path.join(E, "final", "results.jsonl"))}
    specs = {s["key"]: s for s in load(os.path.join(E, "specs_full.jsonl"))}
    # 1. goals
    pop = [k for k, s in specs.items() if s["run"] == "main" and fin[k]["outcome"] == "proved"]
    goals = []
    sizes = {}
    for name, pred, take in BUCKETS:
        ks = [k for k in pop if pred(fin[k]["N"])]
        sizes[name] = len(ks)
        for rank, k in enumerate(ranked(SEED_GOALS, ks)[:take]):
            s = specs[k]
            goals.append({"key": k, "id": s["id"], "tier": s["tier"], "thm": s["thm"], "bucket": name, "rank": rank,
                          "N": fin[k]["N"], "H_main": s["H"], "hash": hkey(SEED_GOALS, k)[:16],
                          **({"pos": s["pos"], "nctx": s["nctx"]} if "pos" in s else {})})
    print("population", len(pop), "buckets", sizes, "goals", len(goals))
    # 2. pool
    allp = load(os.path.join(E, "scaling_pool_all.jsonl"))
    hdr, allp = allp[0], allp[1:]
    assert hdr["kept_after_filters"] == len(allp) == 48012, (hdr, len(allp))
    pool = [r for r in allp if r["accepted"]]
    # acceptance check against corpus_hcompile
    verdict = {r["name"]: r["accepted"] for r in allp}
    agree = disagree = 0
    bad = []
    for r in load(os.path.join(E, "corpus_hcompile.jsonl")):
        for run in ("main", "r1b"):
            h = r.get(run)
            if not h or "goal_rejected" in h:
                continue
            for c in h.get("accepted", []):
                if c in verdict:
                    if verdict[c]: agree += 1
                    else: disagree += 1; bad.append((r["id"], c, "accepted in hcompile"))
            for c, m in h.get("rejected", []):
                if c in verdict:
                    if not verdict[c]: agree += 1
                    else: disagree += 1; bad.append((r["id"], c, m[:80]))
    print(f"pool: {len(allp)} theorems, {len(pool)} accepted; check against corpus_hcompile: {agree} agree, {disagree} disagree {bad[:5]}")
    # 3. near symbols S per goal
    tmp = os.path.join(E, "scaling_goal_specs.tmp.jsonl")
    write(tmp, [{"key": g["key"], "tier": g["tier"], "thm": g["thm"], "H": g["H_main"],
                 **({"pos": g["pos"]} if "pos" in g else {})} for g in goals])
    symout = os.path.join(E, "scaling_syms.tmp.jsonl")
    subprocess.run([os.path.join(ROOT, "Test/capped.sh"), os.path.join(ROOT, ".lake/build/bin/eval_pool"), "syms", tmp, symout],
                   cwd=ROOT, check=True)
    syms = {r["key"]: r for r in load(symout)}
    os.remove(tmp); os.remove(symout)
    # 4. candidates and specs
    run_specs = []
    nearsz = []
    for g in goals:
        sy = syms[g["key"]]
        S = sorted((set(sy["root"]) | set(sy["H_heads"])) - {"app"})
        excl = set(g["H_main"]) | {g["thm"]}
        cands = [r["name"] for r in pool if r["name"] not in excl]
        near = [r["name"] for r in pool if r["name"] not in excl and set(r["heads"]) - {"app"} & set(S)]
        rr = ranked(SEED_RANDOM, cands, g["key"] + ":")
        rn = ranked(SEED_NEAR, near, g["key"] + ":")
        g.update({"S": S, "n_random": len(cands), "n_near": len(near), "random_top32": rr[:32], "near_top32": rn[:32],
                  "H_main_accepted": sy["H_accepted"]})
        nearsz.append(len(near))
        base = {"id": g["id"], "tier": g["tier"], "thm": g["thm"], "run": "scale", "baselines": False,
                "nmax": g["N"], "orig_N": g["N"], "orig_outcome": "proved", "goal": g["key"], "bucket": g["bucket"],
                "rank": g["rank"], **({"pos": g["pos"], "nctx": g["nctx"]} if "pos" in g else {})}
        run_specs.append({**base, "key": f"scale:none:0:{g['key']}", "mode": "none", "k": 0, "k_actual": 0,
                          "H": g["H_main"], "distractors": []})
        for mode, lst in (("random", rr), ("near", rn)):
            for k in KS:
                d = lst[:k]
                run_specs.append({**base, "key": f"scale:{mode}:{k}:{g['key']}", "mode": mode, "k": k, "k_actual": len(d),
                                  "H": g["H_main"] + d, "distractors": d})
    write(os.path.join(E, "scaling_goals.jsonl"), goals)
    write(os.path.join(E, "scaling_pool.jsonl"), [{"name": r["name"], "heads": r["heads"]} for r in pool])
    write(os.path.join(E, "specs_scaling.jsonl"), run_specs)
    pilot_goals = {g["key"] for g in goals if g["rank"] == 0}
    write(os.path.join(E, "specs_scaling_pilot.jsonl"), [s for s in run_specs if s["goal"] in pilot_goals])
    nearsz.sort()
    print("near pool per goal: median", nearsz[len(nearsz) // 2], "min", nearsz[0], "max", nearsz[-1],
          "goals with < 32 near:", sum(1 for x in nearsz if x < 32))
    print("by bucket and tier:", sorted(collections.Counter((g["bucket"], g["tier"]) for g in goals).items()))
    print("specs", len(run_specs), "pilot", sum(1 for s in run_specs if s["goal"] in pilot_goals))


if __name__ == "__main__":
    {"setup": setup}[sys.argv[1]]()
