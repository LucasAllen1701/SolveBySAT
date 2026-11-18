#!/usr/bin/env python3
"""Status of a running (or finished) 7b evaluation, written to OUTDIR/STATUS.md.

  eval_status.py OUTDIR [--specs SPECS] [--pilot PILOT_DIR] [--rc RC] [--notes]

Holds: shards done, goals done, outcome counts so far (run / tier), crashes by cause, the
number of goals that hit a time limit, and a projected finish time.

Projection: for each remaining spec, the mean goal time of its stratum (run, tier,
|H_main| bucket) among the goals finished so far in OUTDIR (or, with fewer than 5 there,
in the pilot), plus the per-goal overhead measured in the pilot. The observed throughput
is shown too.

--rc RC records how the driver ended (0 finished, 3-8 a stop; see eval_driver.py).
--notes prints the final tables as Markdown for NOTES.md instead of writing STATUS.md.
"""
import collections, datetime, json, os, statistics, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_pilot import bucket, load, outcome, secs  # noqa: E402

STOPS = {0: "finished", 3: "STOPPED: decoder bug or solver error (see results.jsonl)",
         4: "STOPPED: harness error", 5: "STOPPED: shard died with no unfinished goal",
         6: "STOPPED: another driver holds the lock",
         7: "STOPPED: memory outside the evaluation slice fell below 1 GB",
         8: "STOPPED: a crash cause other than oom or watchdog repeated"}
PILOT_OVERHEAD_S = 0.8


def stratum(s):
    return (s["run"], s["tier"], bucket(s.get("H_main_size", len(s["H"]))))


def hit_time_limit(r):
    return r["outcome"] == "timeout" or (r["outcome"] == "crash" and r.get("cause") == "watchdog")


def tables(specs, res):
    out = []
    by = collections.defaultdict(collections.Counter)
    for k, r in res.items():
        s = specs[k]
        by[(s["run"], s["tier"])][outcome(r)] += 1
    cols = sorted({o for c in by.values() for o in c})
    out.append("| run | tier | goals | " + " | ".join(cols) + " |")
    out.append("| --- | --- | --- | " + " | ".join("---" for _ in cols) + " |")
    for g in sorted(by):
        out.append(f"| {g[0]} | {g[1]} | {sum(by[g].values())} | " + " | ".join(str(by[g].get(o, 0)) for o in cols) + " |")
    proved = [r for r in res.values() if r["outcome"] == "proved"]
    if proved:
        out.append("")
        out.append("Proved at N: " + ", ".join(f"{n}: {c}" for n, c in sorted(collections.Counter(r["N"] for r in proved).items())))
    return out


def baselines(specs, res):
    out = []
    for tier in ("A", "B"):
        rs = [r for k, r in res.items() if specs[k]["run"] == "main" and specs[k]["tier"] == tier
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
        out.append(f"- Tier {tier} ({len(rs)} goals with baselines):")
        for b, cc in c.items():
            out.append(f"  - {b}: " + ", ".join(f"{o} {n}" for o, n in cc.most_common()))
    return out


def main():
    a = sys.argv[1:]
    d = a[0]
    opts = dict(zip(a[1::2], a[2::2])) if "--notes" not in a else dict(zip(a[1:-1:2], a[2:-1:2]))
    specs_l = load(opts.get("--specs", "eval/specs_full.jsonl"))
    specs = {s["key"]: s for s in specs_l}
    rc = int(opts["--rc"]) if "--rc" in opts else None
    res = {r["key"]: r for r in load(os.path.join(d, "results.jsonl"))}
    hdr = json.load(open(os.path.join(d, "header.json"))) if os.path.exists(os.path.join(d, "header.json")) else {}
    shard = hdr.get("shard_size", 50)

    if "--notes" in a:
        print("\n".join(tables(specs, res)))
        print()
        print("\n".join(baselines(specs, res)))
        return 0

    # shards: the full spec order, in blocks of shard_size, as on a fresh start
    n_shards = (len(specs_l) + shard - 1) // shard
    shards_done = sum(1 for i in range(n_shards) if all(s["key"] in res for s in specs_l[i * shard:(i + 1) * shard]))

    # projection
    pilot = opts.get("--pilot", "eval/pilot")
    pspecs = {s["key"]: s for s in load("eval/specs_pilot.jsonl")}
    pres = [r for r in load(os.path.join(pilot, "results.jsonl")) if r["key"] in pspecs]
    t_full, t_pilot = collections.defaultdict(list), collections.defaultdict(list)
    for k, r in res.items():
        t_full[stratum(specs[k])].append(secs(r))
    for r in pres:
        t_pilot[stratum(pspecs[r["key"]])].append(secs(r))
    tier_pilot = collections.defaultdict(list)
    for st, xs in t_pilot.items():
        tier_pilot[st[:2]] += xs
    remaining = [s for s in specs_l if s["key"] not in res]
    rem_s = 0.0
    for s in remaining:
        st = stratum(s)
        xs = t_full[st] if len(t_full[st]) >= 5 else t_pilot.get(st) or tier_pilot.get(st[:2]) or [0]
        rem_s += statistics.mean(xs) + PILOT_OVERHEAD_S

    prog_p = os.path.join(d, "progress.jsonl")
    now = time.time()
    with open(prog_p, "a") as f:
        f.write(json.dumps({"t": round(now), "done": len(res)}) + "\n")
    prog = load(prog_p)
    thr = None
    if len(prog) >= 2 and prog[-1]["done"] > prog[0]["done"]:
        thr = (prog[-1]["t"] - prog[0]["t"]) / (prog[-1]["done"] - prog[0]["done"])
    walls = load(os.path.join(d, "driver.jsonl"))

    crashes = collections.Counter(r.get("cause") for r in res.values() if r["outcome"] == "crash")
    bad = [r for r in res.values() if r["outcome"] in ("decoder_bug", "harness_error", "solver_error")]
    fmt = lambda t: datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M")
    L = ["# 7b full run: status", "",
         f"Updated {fmt(now)} (machine time). Specs: `{hdr.get('specs', '?')}`; P = {hdr.get('parallel_shards', '?')}; "
         f"commit at start `{str(hdr.get('git_commit', '?'))[:10]}`.", ""]
    if rc is not None:
        L += [f"**Driver ended: {STOPS.get(rc, f'exit {rc}')}.**", ""]
        for w in walls:
            if "stop" in w:
                L += [f"- driver stop record: `{json.dumps(w)}`"]
        L += [""]
    L += [f"- Shards done: {shards_done} of {n_shards} (shard size {shard})",
          f"- Goals done: {len(res)} of {len(specs_l)}",
          f"- decoder_bug / solver_error / harness_error: {len(bad)}",
          f"- Goals that hit a time limit (solver or loop timeout, watchdog): {sum(1 for r in res.values() if hit_time_limit(r))}",
          "- Crashes by cause: " + (", ".join(f"{c} {n}" for c, n in crashes.most_common()) or "none"),
          f"- Driver wall time of finished driver runs: {sum(w.get('wall_s', 0) for w in walls) / 3600:.2f} h"]
    if remaining:
        L += [f"- Remaining: {len(remaining)} goals, projected {rem_s / 3600:.1f} h → finish about {fmt(now + rem_s)}"
              + (f"; observed throughput {thr:.1f} s per goal → about {fmt(now + thr * len(remaining))}" if thr else "")]
    L += ["", "## Outcomes so far", ""] + tables(specs, res) + ["", "## Baselines so far", ""] + baselines(specs, res)
    for r in bad:
        L += ["", f"**{r['outcome']}** on `{r['key']}`: {str(r.get('reason'))[:400]}"]
    open(os.path.join(d, "STATUS.md"), "w").write("\n".join(L) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
