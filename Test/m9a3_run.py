#!/usr/bin/env python3
"""Milestone 9a-3 (M9_PLAN 4.3 to 4.5, amendment 6.2): the evaluation runs.

  python3 Test/m9a3_run.py runs pilot|full [--publish]   the N loop (Test/eval_driver.py) into eval/m9a3/runs/
  python3 Test/m9a3_run.py sizes pilot|full [--publish]  countOnly sizes at N = 5 and at each run's last N
  python3 Test/m9a3_run.py project                       eval/m9a3/pilot/PROJECTION.md from the pilot's times
  python3 Test/m9a3_run.py status                        eval/m9a3/STATUS.md
  python3 Test/m9a3_run.py publish MESSAGE               status, commit eval/m9a3, push m9

Settings (4.3): `SOLVE_BY_SAT_EVAL_FLAGS=nodeBounds,exclusivePairs,iffEq,rewrite` (eqTrans at its default, on), milestone
7's limits (the driver's defaults: solver 20 s, N loop 120 s, watchdog 300 s, 2.5 GB cap, one shard at a time, N
from 1 to 10). The stop rules of 4.4 are the driver's (SOLVE_BY_SAT_EVAL_M9A3=eval/m9a3/expect.jsonl, exit 10; a
decoder failure exits 3). The pilot (4.5) is the first 10 specs of group 1 in 8a's spec order and the 5
highest-ranked goals of each fresh group; its runs are the full run's first records (same output directory, the
full run resumes past them).

The sizes are `eval_run sizes9a` in setting `rw` (iffEq and rewrite, eqTrans on, R1 and R2 on), in their own
capped processes (Test/capped.sh, chunks of 20 runs, one process at a time, after the runs): at N = 5
(eval/m9a3/sizes_N5/) and at each run's last N (eval/m9a3/sizes_last/: the N of a proof, Nmax for no proof, the
last N attempted for a timeout, memout or crash). A killed process is recorded as `memout` or `crash` for its run.
Resumable: run the same command again.
"""
import json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Test"))
from m9a2_run import capped_loop, load  # noqa: E402

EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")
OUT = os.path.join(ROOT, "eval", "m9a3")
RUNS = os.path.join(OUT, "runs")
FLAGS = "nodeBounds,exclusivePairs,iffEq,rewrite"
CHUNK = 20
FRESH = ("rewrite_B", "rewrite_A", "control")


def specs(which):
    sp = load(os.path.join(OUT, "specs.jsonl"))
    if which == "full":
        return sp
    g1 = [s for s in sp if s["group"].startswith("g1_")][:10]
    return g1 + [s for g in FRESH for s in [x for x in sp if x["group"] == g][:5]]


def runs(which, pub):
    sp = specs(which)
    path = os.path.join(OUT, f"specs_run_{which}.jsonl")
    with open(path, "w") as f:
        for s in sp:
            f.write(json.dumps(s, sort_keys=True) + "\n")
    env = dict(os.environ, SOLVE_BY_SAT_EVAL_FLAGS=FLAGS, SOLVE_BY_SAT_EVAL_M9A3=os.path.join(OUT, "expect.jsonl"))
    env.pop("SOLVE_BY_SAT_EVAL_COMPARE", None)
    hook = [] if not pub else ["--after-shard", f"python3 {os.path.join(ROOT, 'Test/m9a3_run.py')} publish 'eval/m9a3: runs'"]
    p = subprocess.run(["python3", os.path.join(ROOT, "Test/eval_driver.py"), "run", path, RUNS] + hook, cwd=ROOT, env=env)
    if pub:
        publish(f"eval/m9a3: runs {which}, {len(load(os.path.join(RUNS, 'results.jsonl')))} results" +
                (f" (exit {p.returncode})" if p.returncode else ""))
    return p.returncode


def last_n(r):
    out = r.get("outcome")
    if out in ("proved", "no_proof_le_Nmax", "limitation") and r.get("N"):
        return r["N"]
    if out == "crash":
        return r.get("last_N") or 1
    rows = r.get("per_N") or []
    return max((x.get("N", 0) for x in rows), default=0) or r.get("N") or 1


def sizes(which, pub):
    keys = [s["key"] for s in specs(which)]
    res = {r["key"]: r for r in load(os.path.join(RUNS, "results.jsonl"))}
    missing = [k for k in keys if k not in res]
    if missing:
        print(f"sizes: {len(missing)} runs have no result yet (first {missing[0]})"); return 4
    sp = {s["key"]: s for s in load(os.path.join(OUT, "specs.jsonl"))}
    rc = 0
    for tag in ("N5", "last"):
        out = os.path.join(OUT, f"sizes_{tag}")
        os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
        results, started = os.path.join(out, "results.jsonl"), os.path.join(out, "started.jsonl")
        byn = {}
        for k in keys:
            byn.setdefault(5 if tag == "N5" else last_n(res[k]), []).append(k)
        t0 = time.time()
        for n in sorted(byn):
            ks = byn[n]
            for i in range(0, len(ks), CHUNK):
                part = ks[i:i + CHUNK]
                want = [f"{k}|rw" for k in part]
                if all(w in {r["key"] for r in load(results)} for w in want):
                    continue
                cs = os.path.join(out, "chunks", f"N{n:02d}_{i // CHUNK:03d}.jsonl")
                with open(cs, "w") as f:
                    for k in part:
                        f.write(json.dumps(sp[k], sort_keys=True) + "\n")
                rc, _ = capped_loop([EXE, "sizes9a", cs, results, started, str(n), "rw"], results, started, want,
                                    f"sizes {tag} N={n}")
                if pub:
                    publish(f"eval/m9a3: sizes {tag}, {len(load(results))} records")
                if rc:
                    return rc
        tp = os.path.join(out, "timing.json")
        old = json.load(open(tp)) if os.path.exists(tp) else {"wall_s": 0.0}
        json.dump({"wall_s": round(old["wall_s"] + time.time() - t0, 1)}, open(tp, "w"))
    return rc


def project():
    pil = specs("pilot")
    res = {r["key"]: r for r in load(os.path.join(RUNS, "results.jsonl"))}
    sz = {}
    for tag in ("N5", "last"):
        for r in load(os.path.join(OUT, f"sizes_{tag}", "results.jsonl")):
            sz.setdefault(r["key"].split("|")[0], 0)
    lines = ["# 9a-3 pilot: projection of the full run (M9_PLAN 4.5)", ""]
    by = {}
    for s in pil:
        g = "group 1" if s["group"].startswith("g1_") else s["group"]
        by.setdefault(g, []).append(res[s["key"]]["total_ms"] / 1000 if "total_ms" in res[s["key"]] else 300.0)
    st = {}
    for tag in ("N5", "last"):
        tp = os.path.join(OUT, f"sizes_{tag}", "timing.json")
        st[tag] = json.load(open(tp))["wall_s"] if os.path.exists(tp) else 0.0
    n_full = {"group 1": 200, "rewrite_B": 100, "rewrite_A": 50, "control": 50}
    lines.append("| group | pilot runs | mean s per run (a crash counted as the 300 s watchdog) | runs in the full run | projected h |")
    lines.append("| --- | --- | --- | --- | --- |")
    tot = 0.0
    for g in ("group 1", "rewrite_B", "rewrite_A", "control"):
        m = sum(by[g]) / len(by[g])
        h = m * n_full[g] / 3600
        tot += h
        lines.append(f"| {g} | {len(by[g])} | {m:.1f} | {n_full[g]} | {h:.2f} |")
    per = (st["N5"] + st["last"]) / len(pil)
    sh = per * 400 / 3600
    lines += ["", f"- Runs: {tot:.2f} h projected (the driver adds a few seconds per shard).",
              f"- Sizes (N = 5 and the last N): {st['N5'] + st['last']:.0f} s for the pilot's {len(pil)} runs, "
              f"{per:.1f} s per run: {sh:.2f} h projected.",
              f"- **Total: {tot + sh:.1f} h** (the bound of 4.5 is about 24 h)."]
    os.makedirs(os.path.join(OUT, "pilot"), exist_ok=True)
    open(os.path.join(OUT, "pilot", "PROJECTION.md"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


def status():
    rs = load(os.path.join(RUNS, "results.jsonl"))
    sp = {s["key"]: s["group"] for s in load(os.path.join(OUT, "specs.jsonl"))}
    c = {}
    for r in rs:
        g = sp.get(r["key"], "?")
        c.setdefault(g, {}).setdefault(r.get("outcome"), 0)
        c[g][r.get("outcome")] += 1
    lines = ["# eval/m9a3: status of the evaluation (M9_PLAN 4)", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}.", "",
             f"- runs: {len(rs)} of 400 results"]
    for g in sorted(c):
        lines.append(f"  - {g}: " + ", ".join(f"{k} {v}" for k, v in sorted(c[g].items())))
    stops = [d for d in load(os.path.join(RUNS, "driver.jsonl")) if "stop" in d]
    if stops:
        lines.append(f"- stops: " + "; ".join(f"{d.get('key')}: {d.get('reason', d['stop'])}" for d in stops))
    for tag in ("N5", "last"):
        ss = load(os.path.join(OUT, f"sizes_{tag}", "results.jsonl"))
        if ss:
            cc = {}
            for r in ss:
                cc[r["status"]] = cc.get(r["status"], 0) + 1
            lines.append(f"- sizes {tag}: {len(ss)} records: " + ", ".join(f"{k} {v}" for k, v in sorted(cc.items())))
    open(os.path.join(OUT, "STATUS.md"), "w").write("\n".join(lines) + "\n")


def publish(msg):
    """Commit eval/m9a3 (only) and push m9; a busy index is retried, and a failure is reported, never fatal."""
    status()
    for _ in range(10):
        a = subprocess.run(["git", "add", "eval/m9a3"], cwd=ROOT, capture_output=True, text=True)
        if a.returncode == 0:
            if subprocess.run(["git", "diff", "--cached", "--quiet", "--", "eval/m9a3"], cwd=ROOT).returncode == 0:
                return
            c = subprocess.run(["git", "commit", "-q", "-m", msg + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
                                "--", "eval/m9a3"], cwd=ROOT, capture_output=True, text=True)
            if c.returncode == 0:
                subprocess.run(["git", "push", "-q", "origin", "m9"], cwd=ROOT, capture_output=True)
                return
        time.sleep(30)
    print(f"publish failed: {msg}", flush=True)


def main(a):
    pub = "--publish" in a
    a = [x for x in a if x != "--publish"]
    if a[:1] == ["runs"]:
        return runs(a[1], pub)
    if a[:1] == ["sizes"]:
        return sizes(a[1], pub)
    if a == ["project"]:
        return project()
    if a == ["status"]:
        status(); return 0
    if a[:1] == ["publish"]:
        publish(a[1]); return 0
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
