#!/usr/bin/env python3
"""Milestone 9a-2 (M9_PLAN 3.3, amendment 6.1 clarification 5): the measurement.

  python3 Test/m9a2_run.py inputs M8DATA                     copy 8c-1's r1r2 size records (eval/m9a2/inputs/)
  python3 Test/m9a2_run.py sizes N [--publish] [--limit K]   countOnly sizes, settings none, rw, rwnt
  python3 Test/m9a2_run.py diag N SETTING [--publish] [--limit K]   eval_run diag (M3 split by rule) in rw or rwnt
  python3 Test/m9a2_run.py check N                           the consistency check on finished N sizes
  python3 Test/m9a2_run.py status                            write eval/m9a2/STATUS.md
  python3 Test/m9a2_run.py publish MESSAGE                   status, commit eval/m9a2, push m9

The 400 points of eval/m9a2/specs_points.jsonl (a copy of m8-data's eval/m8b/specs_points.jsonl) at N = 5 and
N = 10, R1 and R2 on:
- `none`: every point as 8c-1 built it (no equality rules; a probe point has 8a's rules as lemmas), recounted;
  it must equal 8c-1's `r1r2` counts at every point (6.1 clarification 5): a difference stops the run (exit 7);
- `rw` (iffEq and rewrite) and `rwnt` (the same with eqTrans off), on the 200 points without rules
  (milestone 7's H).
Points go in chunks of 20 (eval/m9a2/sizes_N<N>/chunks/), one eval_run process at a time under the 2.5 GB cap
(Test/capped.sh). A process that dies is recorded as `memout` or `crash` for the (point, setting) it had started,
with the last record it wrote, and restarted on the rest (8c-1's rule). Resumable: run the same command again.
`--limit K` runs only the first K points (the pilot).
"""
import json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")
OUT = os.path.join(ROOT, "eval", "m9a2")
SPECS = os.path.join(OUT, "specs_points.jsonl")
SETTINGS = ["none", "rw", "rwnt"]
CHUNK = 20


def load(p):
    out = []
    if os.path.exists(p):
        for l in open(p):
            l = l.strip()
            if l:
                try:
                    out.append(json.loads(l))
                except json.JSONDecodeError:
                    pass   # a line cut by a kill
    return out


def inputs(m8data):
    """8c-1's r1r2 records (the reference of the consistency check and the `8a rules` setting)."""
    os.makedirs(os.path.join(OUT, "inputs"), exist_ok=True)
    for n in (5, 10):
        rs = [r for r in load(os.path.join(m8data, f"eval/m8c1/sizes_N{n}/results.jsonl")) if r.get("setting") == "r1r2"]
        with open(os.path.join(OUT, "inputs", f"m8c1_r1r2_N{n}.jsonl"), "w") as f:
            for r in rs:
                f.write(json.dumps(r, sort_keys=True) + "\n")
        print(f"N = {n}: {len(rs)} r1r2 records")
    # 8c-1's M3 at N = 5 (R1 and R2 on): the level-symbol share of decomposition without rules and with 8a's
    ms = [r for r in load(os.path.join(m8data, "eval/m8c1/diag_N5/sections.jsonl")) if r.get("section") == "m3"]
    with open(os.path.join(OUT, "inputs", "m8c1_diag_N5_m3.jsonl"), "w") as f:
        for r in ms:
            f.write(json.dumps(r, sort_keys=True) + "\n")
    print(f"diag N = 5: {len(ms)} m3 sections")


def ref(n):
    return {r["point"]: r for r in load(os.path.join(OUT, "inputs", f"m8c1_r1r2_N{n}.jsonl"))}


def check(n):
    """The consistency check (6.1, clarification 5): `none` equals 8c-1's r1r2 counts (clauses, variables,
    every family) at every finished point. Returns the violations."""
    R = ref(n)
    bad = []
    for r in load(os.path.join(OUT, f"sizes_N{n}", "results.jsonl")):
        if r.get("setting") != "none":
            continue
        m = R.get(r["point"])
        if m is None:
            bad.append(f"{r['key']}: no 8c-1 record"); continue
        if r.get("status") != m.get("status"):
            bad.append(f"{r['key']}: status {r.get('status')} != 8c-1's {m.get('status')}"); continue
        if r.get("status") != "ok":
            continue
        for k in ("clauses", "vars", "families", "early_exit"):
            if r[k] != m[k]:
                bad.append(f"{r['key']}: {k} {r[k]} != 8c-1's {m[k]}")
    return bad


def capped_loop(cmd, results, started, keys, label):
    """Run `cmd` until every key has a result line; record a killed process's key."""
    t0 = time.time()
    while True:
        done = {r["key"] for r in load(results)}
        if all(k in done for k in keys):
            return 0, time.time() - t0
        p = subprocess.run([os.path.join(ROOT, "Test/capped.sh")] + cmd, cwd=ROOT, capture_output=True, text=True)
        done = {r["key"] for r in load(results)}
        if p.returncode == 3:
            print(f"{label}: STOP (internal error): {p.stderr[-500:]}", flush=True)
            return 3, time.time() - t0
        if p.returncode != 0:
            st = [r for r in load(started) if r["key"] not in done]
            if not st:
                print(f"{label}: exited {p.returncode} with nothing in progress: {p.stderr[-300:]}", flush=True)
                return 4, time.time() - t0
            k = st[-1]["key"]
            secs = [r["section"] for r in st if r["key"] == k and "section" in r]
            status = "memout" if p.returncode in (137, -9, -15) else "crash"
            rec = {"key": k, "status": status, "exit": p.returncode}
            if "|" in k:
                rec.update(point=k.split("|")[0], setting=k.split("|")[1])
            if secs:
                rec["last_section"] = secs[-1]
            with open(results, "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(f"{label}: {k}: {status} (exit {p.returncode})", flush=True)
        print(f"{label}: {len(load(results))} records, {time.time() - t0:.0f} s", flush=True)


def chunks(out, limit=None):
    lines = [l for l in open(SPECS) if l.strip()]
    if limit:
        lines = lines[:limit]
    os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
    for i in range(0, len(lines), CHUNK):
        p = os.path.join(out, "chunks", f"{i // CHUNK:03d}.jsonl")
        open(p, "w").write("".join(lines[i:i + CHUNK]))
        yield p, [json.loads(l) for l in lines[i:i + CHUNK]]


def timing(out, wall, extra):
    tp = os.path.join(out, "timing.json")
    old = json.load(open(tp)) if os.path.exists(tp) else {"wall_s": 0.0}
    json.dump(dict(wall_s=round(old["wall_s"] + wall, 1), **extra), open(tp, "w"))


def sizes(n, pub=False, limit=None):
    out = os.path.join(OUT, f"sizes_N{n}")
    os.makedirs(out, exist_ok=True)
    results, started = os.path.join(out, "results.jsonl"), os.path.join(out, "started.jsonl")
    rc, wall = 0, 0.0
    for cs, sp in chunks(out, limit):
        keys = [f"{s['key']}|{st}" for s in sp for st in (["none"] if s.get("probe") else SETTINGS)]
        if all(k in {r["key"] for r in load(results)} for k in keys):
            continue
        rc, w = capped_loop([EXE, "sizes9a", cs, results, started, str(n), ",".join(SETTINGS)],
                            results, started, keys, f"sizes N={n}")
        wall += w
        if not rc and (bad := check(n)):
            print("STOP (6.1 clarification 5):\n  " + "\n  ".join(bad[:10]), flush=True)
            open(os.path.join(out, "STOP.txt"), "w").write("\n".join(bad) + "\n")
            rc = 7
        if pub:
            publish(f"eval/m9a2: sizes N = {n}, {len(load(results))} records" + (" (STOPPED)" if rc else ""))
        if rc:
            break
    timing(out, wall, {"N": n, "finished": rc == 0 and not limit})
    return rc


def diag(n, setting, pub=False, limit=None):
    out = os.path.join(OUT, f"diag_{setting}_N{n}")
    os.makedirs(out, exist_ok=True)
    results, sections = os.path.join(out, "results.jsonl"), os.path.join(out, "sections.jsonl")
    rc, wall = 0, 0.0
    for cs, sp in chunks(out, limit):
        keys = [s["key"] for s in sp if not s.get("probe")]
        if all(k in {r["key"] for r in load(results)} for k in keys):
            continue
        rc, w = capped_loop([EXE, "diag", cs, results, sections, str(n), setting], results, sections, keys,
                            f"diag {setting} N={n}")
        wall += w
        bad = [r["key"] for r in load(sections) if r.get("section") in ("m2", "m3", "r1") and
               any(v is False for k, v in r["data"].items() if k.startswith("check_"))]
        if not rc and bad:
            print(f"STOP: recount check failed: {bad[:5]}", flush=True)
            open(os.path.join(out, "STOP.txt"), "w").write("recount check failed:\n" + "\n".join(bad) + "\n")
            rc = 7
        if pub:
            publish(f"eval/m9a2: diag {setting} N = {n}, {len(load(results))} points" + (" (STOPPED)" if rc else ""))
        if rc:
            break
    timing(out, wall, {"N": n, "setting": setting, "finished": rc == 0 and not limit})
    return rc


def status():
    lines = ["# eval/m9a2: status of the measurement (M9_PLAN 3.3)", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}.", ""]
    for n in (5, 10):
        rs = load(os.path.join(OUT, f"sizes_N{n}", "results.jsonl"))
        c = {}
        for r in rs:
            c[(r.get("setting"), r["status"])] = c.get((r.get("setting"), r["status"]), 0) + 1
        lines.append(f"- sizes N = {n}: {len(rs)} of 800 (point, setting) records" +
                     (": " + ", ".join(f"{s} {st} {v}" for (s, st), v in sorted(c.items())) if c else ""))
        if rs:
            bad = check(n)
            lines.append(f"  - consistency (none = 8c-1's r1r2 at every point): "
                         f"{'all pass' if not bad else str(len(bad)) + ' FAIL'}")
        tp = os.path.join(OUT, f"sizes_N{n}", "timing.json")
        if os.path.exists(tp):
            lines.append(f"  - wall time so far: {json.load(open(tp))['wall_s'] / 3600:.2f} h")
    for st in ("rw", "rwnt"):
        rs = load(os.path.join(OUT, f"diag_{st}_N5", "results.jsonl"))
        if rs:
            c = {}
            for r in rs:
                c[r["status"]] = c.get(r["status"], 0) + 1
            lines.append(f"- diag {st} N = 5: {len(rs)} of 200 points: " + ", ".join(f"{k} {v}" for k, v in sorted(c.items())))
    open(os.path.join(OUT, "STATUS.md"), "w").write("\n".join(lines) + "\n")


def publish(msg):
    status()
    subprocess.run(["git", "add", "eval/m9a2"], cwd=ROOT, check=True)
    if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=ROOT).returncode != 0:
        subprocess.run(["git", "commit", "-q", "-m", msg + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"],
                       cwd=ROOT, check=True)
        subprocess.run(["git", "push", "-q", "origin", "m9"], cwd=ROOT)


def main(a):
    pub = "--publish" in a
    limit = None
    if "--limit" in a:
        limit = int(a[a.index("--limit") + 1])
        a = a[:a.index("--limit")] + a[a.index("--limit") + 2:]
    a = [x for x in a if x != "--publish"]
    if a[0] == "inputs":
        inputs(a[1]); return 0
    if a[0] == "sizes":
        return sizes(int(a[1]), pub, limit)
    if a[0] == "diag":
        return diag(int(a[1]), a[2], pub, limit)
    if a[0] == "check":
        bad = check(int(a[1]))
        print("\n".join(bad) if bad else "consistency: all pass")
        return 1 if bad else 0
    if a[0] == "status":
        status(); return 0
    if a[0] == "publish":
        publish(a[1]); return 0
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
