#!/usr/bin/env python3
"""Milestone 7b pilot report (EVAL_PLAN §5, §10.3, §10.4): outcome counts, baselines,
warm-up cost, decoder bugs, and the projected time of the full run.

  eval_pilot.py PILOT_DIR [PILOT_SPECS] [FULL_SPECS]

Projection: each goal's time is its `total_ms` (or, for a crash, the time from its start
marker to the kill). Mean time per stratum (run, tier, |H_main| bucket) in the pilot, times
the stratum's size in the full spec file, plus the measured per-goal overhead (shard
start-up, import and warm-up: the driver's wall time minus the goals' times). A stratum
with no pilot goal uses its tier's mean (marked).
"""
import collections, json, os, statistics, sys

BUCKETS = [(0, 5, "0-5"), (6, 10, "6-10"), (11, 20, "11-20"), (21, 10**9, ">20")]


def bucket(n):
    return next(b for lo, hi, b in BUCKETS if lo <= n <= hi)


def load(p):
    out = []
    if os.path.exists(p):
        for l in open(p):
            try:
                out.append(json.loads(l))
            except json.JSONDecodeError:
                pass
    return out


def secs(r):
    if r["outcome"] == "crash":
        return r.get("elapsed_s") or 300.0
    return r.get("total_ms", 0) / 1000


def outcome(r):
    o = r["outcome"]
    if o == "crash":
        return f"crash({r.get('cause')})"
    if o in ("timeout", "memout"):
        return f"{o}({r.get('timeout_kind') or r.get('memout_kind')})"
    return o


def main():
    d = sys.argv[1]
    pspecs = {s["key"]: s for s in load(sys.argv[2] if len(sys.argv) > 2 else "eval/specs_pilot.jsonl")}
    full = load(sys.argv[3] if len(sys.argv) > 3 else "eval/specs_full.jsonl")
    res = {r["key"]: r for r in load(os.path.join(d, "results.jsonl"))}
    missing = [k for k in pspecs if k not in res]
    print(f"pilot: {len(pspecs)} specs, {len(res)} results, missing {len(missing)}")

    def stratum(s):
        return (s["run"], s["tier"], bucket(s.get("H_main_size", len(s["H"]))))

    # 1. outcome counts per run and tier
    print("\n## Outcomes (run / tier)")
    by = collections.defaultdict(collections.Counter)
    for k, r in res.items():
        s = pspecs[k]
        by[(s["run"], s["tier"])][outcome(r)] += 1
    for g in sorted(by):
        print(f"  {g[0]:5} {g[1]}: " + ", ".join(f"{o} {n}" for o, n in by[g].most_common()))
    proved = [r for r in res.values() if r["outcome"] == "proved"]
    if proved:
        print("  proved at N: " + str(sorted(collections.Counter(r["N"] for r in proved).items())))

    # 2. decoder bugs and harness errors
    bad = [r for r in res.values() if r["outcome"] in ("decoder_bug", "harness_error", "solver_error")]
    print(f"\n## decoder_bug / harness_error / solver_error: {len(bad)}")
    for r in bad:
        print(f"  {r['key']}: {r['outcome']}: {str(r.get('reason'))[:300]}")

    # 3. baselines (main run)
    print("\n## Baselines (main run)")
    for tier in ("A", "B"):
        rs = [r for k, r in res.items() if pspecs[k]["run"] == "main" and pspecs[k]["tier"] == tier
              and isinstance(r.get("baselines"), dict)]
        if not rs:
            continue
        c = {b: collections.Counter() for b in ("sbe_like", "sbe_default", "exact", "apply")}
        for r in rs:
            b = r["baselines"]
            c["sbe_like"][b["sbe_like"]["outcome"]] += 1
            c["sbe_default"][b["sbe_default"]["outcome"]] += 1
            ls = b["library_search"]
            c["exact"][ls.get("exact", ls.get("outcome"))] += 1
            c["apply"][ls.get("apply", ls.get("outcome"))] += 1
        ms = {b: statistics.median([r["baselines"][b]["ms"] for r in rs]) for b in ("sbe_like", "sbe_default", "library_search")}
        print(f"  Tier {tier} ({len(rs)} goals with baselines; median ms {ms})")
        for b, cc in c.items():
            print(f"    {b:12} " + ", ".join(f"{o} {n}" for o, n in cc.most_common()))

    # 4. warm-up
    w = load(os.path.join(d, "warmup.jsonl"))
    if w:
        print(f"\n## Warm-up (librarySearch, untimed): {len(w)} shard starts; ms mean {statistics.mean(x['ms'] for x in w):.0f} "
              f"(max {max(x['ms'] for x in w)}); RSS {statistics.mean(x['rss_before_mb'] for x in w):.0f} → "
              f"{statistics.mean(x['rss_after_mb'] for x in w):.0f} MB")

    # 5. projection
    goal_s = sum(secs(r) for r in res.values())
    wall = sum(x["wall_s"] for x in load(os.path.join(d, "driver.jsonl")))
    over = max(0.0, (wall - goal_s) / max(1, len(res)))
    print(f"\n## Time: pilot wall {wall / 60:.1f} min, goals {goal_s / 60:.1f} min, overhead {over:.1f} s per goal")
    t_str = collections.defaultdict(list)
    t_tier = collections.defaultdict(list)
    t_out = collections.defaultdict(list)
    for k, r in res.items():
        s = pspecs[k]
        t_str[stratum(s)].append(secs(r))
        t_tier[(s["run"], s["tier"])].append(secs(r))
        t_out[(s["run"], s["tier"], outcome(r))].append(secs(r))
    n_full = collections.Counter(stratum(s) for s in full)
    print("\n  by stratum: run tier |H_main| | pilot n, mean s | full n | projected h")
    proj = 0.0
    proj_tier = collections.Counter()
    for st in sorted(n_full):
        xs = t_str.get(st)
        mean = statistics.mean(xs) if xs else statistics.mean(t_tier[st[:2]]) if t_tier.get(st[:2]) else 0
        h = n_full[st] * (mean + over) / 3600
        proj += h
        proj_tier[st[:2]] += h
        print(f"    {st[0]:5} {st[1]} {st[2]:>5} | {len(xs or []):3}, {mean:7.1f}{'' if xs else ' (tier mean)'} | {n_full[st]:5} | {h:6.1f}")
    print("\n  by run and tier: " + ", ".join(f"{a} {b}: {h:.1f} h" for (a, b), h in sorted(proj_tier.items())))
    print("\n  by outcome (share of the tier's pilot time, applied to its projection):")
    for (run, tier, o), xs in sorted(t_out.items()):
        share = sum(xs) / max(1e-9, sum(t_tier[(run, tier)]))
        print(f"    {run:5} {tier} {o:22} pilot n {len(xs):3}, mean {statistics.mean(xs):6.1f} s → {share * proj_tier[(run, tier)]:5.1f} h")
    print(f"\n  PROJECTED FULL RUN: {proj:.1f} h ({len(full)} goals)")


if __name__ == "__main__":
    main()
