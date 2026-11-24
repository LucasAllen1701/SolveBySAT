#!/usr/bin/env python3
"""Milestone 8a (M8_PLAN.md §2.4–2.6): run probe specs, their countOnly sizes, and the pilot summary.

  python3 Test/m8a_run.py run SPECS OUTDIR     the runs (Test/eval_driver.py), then the sizes
  python3 Test/m8a_run.py summary OUTDIR       the pilot tables and the projection for the 200 runs
  python3 Test/m8a_run.py status OUTDIR SPECS PHASE   write OUTDIR/STATUS.md

`run` calls `Test/eval_driver.py run SPECS OUTDIR` (the cgroup cap, the watchdog, crash records and
the shard's stop rules: exit 3 decoder bug or solver error, 4 harness error, 6 a stop rule of §2.5).
On any of those it stops without computing sizes. Then, for every run, it writes OUTDIR/sizes_specs.jsonl
with one spec per N in {5, the run's last N} (key `<run key>@N<n>`, `nmax` = n), and runs
`Test/eval_sizes.py` on it (each `eval_run sizes` process under the cap; a killed process is recorded
as memout or crash and the rest go on). Resumable: run the same command again.
"""
import json, os, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INP = os.path.join(ROOT, "eval", "m8a", "inputs")
GROUPS = ["rewrite_B", "rewrite_A", "control"]
FULL = {"rewrite_B": 100, "rewrite_A": 50, "control": 50}


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []


def last_n(r):
    return r.get("N") if r.get("outcome") != "crash" else r.get("last_N")


def run(specs, out, hook=None):
    t0 = time.time()
    p = subprocess.run([sys.executable, os.path.join(ROOT, "Test/eval_driver.py"), "run", specs, out]
                       + (["--after-shard", hook] if hook else []), cwd=ROOT)
    t1 = time.time()
    if p.returncode != 0:
        print(f"STOP: driver exit {p.returncode}; sizes not computed"); return p.returncode
    sp = {s["key"]: s for s in load(specs)}
    res = {r["key"]: r for r in load(os.path.join(out, "results.jsonl"))}
    rows = []
    for k, s in sp.items():
        n = last_n(res[k]) or 1
        # §2.4: N = 5 and the run's last N; for a control also its original N, for §2.7's comparison
        # with milestone 7 at the original N (a crashed control may stop below it)
        for m in sorted({5, n} | ({s["orig_N"]} if s.get("probe_group") == "control" else set())):
            rows.append(dict(s, key=f"{k}@N{m}", nmax=m, size_of=k, size_N=m))
    sizes_specs = os.path.join(out, "sizes_specs.jsonl")
    with open(sizes_specs, "w") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
    q = subprocess.run([sys.executable, os.path.join(ROOT, "Test/eval_sizes.py"), sizes_specs,
                        os.path.join(out, "sizes.jsonl")], cwd=ROOT)
    t2 = time.time()
    # accumulated over passes, so a resumed pass adds its time instead of replacing the first pass's
    tp = os.path.join(out, "timing.json")
    old = json.load(open(tp)) if os.path.exists(tp) else {"runs_s": 0.0, "sizes_s": 0.0}
    with open(tp, "w") as f:
        json.dump({"runs_s": round(old["runs_s"] + t1 - t0, 1), "sizes_s": round(old["sizes_s"] + t2 - t1, 1),
                   "n_runs": len(sp), "n_sizes": len(rows)}, f)
    return q.returncode


def status(out, specs, phase):
    """OUTDIR/STATUS.md: progress of a run (the after-shard hook of Test/m8a_full.sh)."""
    sp = [s["key"] for s in load(specs)]
    res = {r["key"]: r for r in load(os.path.join(out, "results.jsonl"))}
    siz = load(os.path.join(out, "sizes.jsonl"))
    grp = {s["key"]: s.get("probe_group") for s in load(specs)}
    lines = [f"# {os.path.relpath(out, ROOT)}: status", "",
             f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}. Phase: {phase}.", "",
             f"- Goals done: {len(res)} of {len(sp)}",
             f"- Stops: {sum(1 for r in res.values() if 'stop' in r)}"
             + "".join(f"; `{k}`: {r['stop']}" for k, r in res.items() if "stop" in r),
             f"- Sizes done: {len(siz)}", "",
             "| group | done | proved | no proof ≤ N | memory crash | timeout | other |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for g in GROUPS:
        rs = [r for k, r in res.items() if grp.get(k) == g]
        c = {o: sum(1 for r in rs if r["outcome"] == o) for o in ("proved", "no_proof_le_Nmax", "crash", "timeout", "memout")}
        lines.append(f"| {g} | {len(rs)} of {sum(1 for k in sp if grp[k] == g)} | {c['proved']} | {c['no_proof_le_Nmax']} | "
                     f"{c['crash'] + c['memout']} | {c['timeout']} | {len(rs) - sum(c.values())} |")
    open(os.path.join(out, "STATUS.md"), "w").write("\n".join(lines) + "\n")


def summary(out):
    goals = {g["key"]: g for g in load(os.path.join(ROOT, "eval", "m8a", "goals.jsonl"))}
    k0 = {r["key"]: r for r in load(os.path.join(INP, "scaling_k0.jsonl"))}
    final = {r["key"]: r for r in load(os.path.join(INP, "final.jsonl"))}
    res = {r["key"]: r for r in load(os.path.join(out, "results.jsonl"))}
    siz = {r["key"]: r for r in load(os.path.join(out, "sizes.jsonl"))}
    tm = json.load(open(os.path.join(out, "timing.json")))
    rules = {r["key"]: r for r in load(os.path.join(ROOT, "eval", "m8a", "rules.jsonl"))}

    def secs(r):   # the shard's total time, or for a crash the driver's elapsed time
        return (r["total_ms"] / 1000) if r.get("total_ms") is not None else r.get("elapsed_s", 300.0)
    print("| group | goal | outcome | N (crash: last N reached) | rules | accepted rules | time s | clauses at last N | clauses at N = 5 | uses rule |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for k, r in res.items():
        g = goals[k[4:]]
        n = last_n(r)
        ru = rules[k]   # rule counts from eval/m8a/rules.jsonl (the same generator; a crash record has none)
        nr = ru["probe_rules"]
        rej = sum(1 for c, _ in ru["H_rejected"] if c.startswith("_probe."))
        z5, zl = siz.get(f"{k}@N5", {}), siz.get(f"{k}@N{n}", {})
        cl = r.get("clauses") or zl.get("clauses")
        print(f"| {g['group']} | `{g['id']}` | {r['outcome']} | {n} | {nr} | {nr - rej} | {secs(r):.1f} | "
              f"{cl if cl is not None else zl.get('status', '–')} | {z5.get('clauses', z5.get('status', '–'))} | {r.get('uses_rule', '–')} |")
    print()
    for k, r in res.items():
        if r["outcome"] == "proved":
            print(f"- `{goals[k[4:]]['id']}` N = {r['N']}: `{r.get('skeleton')}`")
    print()
    print("| control goal | original N | outcome | N | clauses at original N, 8a | milestone 7 | ratio |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for k, r in res.items():
        g = goals[k[4:]]
        if g["group"] != "control":
            continue
        n0 = g["orig_N"]
        z = siz.get(f"{k}@N{n0}", {})
        m7 = k0[g["key"]]["sizes"]["clauses"]
        c8 = z.get("clauses")
        print(f"| `{g['id']}` | {n0} | {r['outcome']} | {r.get('N', r.get('last_N'))} | {c8 if c8 else z.get('status')} | {m7:,} | "
              f"{c8 / m7:.1f}× |" if c8 else f"| `{g['id']}` | {n0} | {r['outcome']} | – | {z.get('status')} | {m7:,} | – |")
    # projection: per group, the mean pilot wall time per run (the shard's total_ms, or the driver's
    # elapsed_s for a crash) and per sizes record, plus the driver's and the sizes pass's overhead spread over the runs
    print()
    tot_run = sum(secs(r) for r in res.values())
    tot_siz = sum((z.get("ms") or 0) for z in siz.values()) / 1000
    over_run = max(0.0, tm["runs_s"] - tot_run) / len(res)
    over_siz = max(0.0, tm["sizes_s"] - tot_siz) / max(1, len(siz))
    proj = 0.0
    print("| group | pilot runs | mean s per run (with overhead) | mean s of sizes per run | projected runs | projected h |")
    print("| --- | --- | --- | --- | --- | --- |")
    for grp in GROUPS:
        ks = [k for k in res if goals[k[4:]]["group"] == grp]
        if not ks:
            continue
        a = statistics.mean(secs(res[k]) + over_run for k in ks)
        b = statistics.mean(sum(((siz[x].get("ms") or 0) / 1000 + over_siz) for x in siz if x.startswith(k + "@")) for k in ks)
        h = FULL[grp] * (a + b) / 3600
        proj += h
        print(f"| {grp} | {len(ks)} | {a:.1f} | {b:.1f} | {FULL[grp]} | {h:.2f} |")
    print(f"\nPilot wall time: runs {tm['runs_s'] / 60:.1f} min, sizes {tm['sizes_s'] / 60:.1f} min. "
          f"Projection for the 200 runs: {proj:.1f} h (the 20 pilot runs included).")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["run"] and len(a) in (3, 5) and (len(a) == 3 or a[3] == "--after-shard"):
        sys.exit(run(a[1], a[2], a[4] if len(a) == 5 else None))
    elif a[:1] == ["status"] and len(a) == 4:
        status(a[1], a[2], a[3])
    elif a[:1] == ["summary"] and len(a) == 2:
        summary(a[1])
    else:
        print(__doc__); sys.exit(2)
