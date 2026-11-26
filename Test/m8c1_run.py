#!/usr/bin/env python3
"""Milestone 8c-1 (M8_PLAN.md 4.4): sizes in three settings, M6 to M8, and the status of the 8a rerun.

  python3 Test/m8c1_run.py sizes SPECS OUTDIR N [--publish]         countOnly sizes, settings off, r1, r1r2
  python3 Test/m8c1_run.py diag SPECS OUTDIR N SETTING [--publish]  M1 to M7 (eval_run diag) in one setting
  python3 Test/m8c1_run.py check-sizes OUTDIR          the checks of 4.4 on finished N = 5 sizes
  python3 Test/m8c1_run.py status                      write eval/m8c1/STATUS.md
  python3 Test/m8c1_run.py publish MESSAGE             status, commit eval/m8c1, push m8

The points go in chunks of 20 (OUTDIR/chunks/); the checks run, and with --publish eval/m8c1 is committed
and pushed, after each chunk. Each phase runs one `eval_run` process at a time under the 2.5 GB cap (Test/capped.sh). If the process
dies, the (point, setting) it had started is recorded in OUTDIR/results.jsonl as `memout` (exit 137, -9
or -15) or `crash`, with what it had finished, and the process is restarted on the rest (4.4: a point
that runs out of memory is recorded as such). Resumable: run the same command again.

`sizes` at N = 5 checks every finished point as it goes (4.4) and stops with exit 7 if
- the flags-off count differs from 8b's `total_clauses` (eval/m8b/points/sections.jsonl), or
- with R1 on, the clause count less R1's unit clauses exceeds 8b's total less `groundness_dead` and
  `decomposition_dead` (the bound check), or R1's excluded gp or cl pairs are fewer than 8b's.
"""
import json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")
OUT = os.path.join(ROOT, "eval", "m8c1")
SETTINGS = ["off", "r1", "r1r2"]
UNITS = "11 node bounds"


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


def m8b_m4():
    return {j["key"]: j["data"] for j in load(os.path.join(ROOT, "eval/m8b/points/sections.jsonl")) if j.get("section") == "m4"}


def check_sizes(out):
    """The 4.4 checks on the N = 5 sizes finished so far. Returns a list of violations."""
    m4 = m8b_m4()
    bad = []
    for r in load(os.path.join(out, "results.jsonl")):
        if r.get("status") != "ok" or r.get("N") != 5:
            continue
        m = m4.get(r["point"])
        if m is None:
            bad.append(f"{r['key']}: no 8b record"); continue
        if r["setting"] == "off":
            if r["clauses"] != m["total_clauses"]:
                bad.append(f"{r['key']}: flags-off count {r['clauses']} != 8b's {m['total_clauses']}")
        else:
            units = r["families"].get(UNITS, 0)
            bound = m["total_clauses"] - m["groundness_dead"] - m["decomposition_dead"]
            if r["clauses"] - units > bound:
                bad.append(f"{r['key']}: {r['clauses']} - {units} units > bound {bound}")
            if r["gp_excluded"] < m["gp_excluded"] or r["cl_excluded"] < m["cl_excluded"]:
                bad.append(f"{r['key']}: excluded gp/cl {r['gp_excluded']}/{r['cl_excluded']} < 8b's "
                           f"{m['gp_excluded']}/{m['cl_excluded']}")
    return bad


def capped_loop(cmd, results, started, keys, label, on_progress=None):
    """Run `cmd` until every key has a result line; record a killed process's key."""
    t0 = time.time()
    while True:
        done = {r["key"] for r in load(results)}
        if all(k in done for k in keys):
            return 0, time.time() - t0
        p = subprocess.run([os.path.join(ROOT, "Test/capped.sh")] + cmd, cwd=ROOT, capture_output=True, text=True)
        done = {r["key"] for r in load(results)}
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
                rec.update(point=k.split("|")[0], setting=k.split("|")[1], phase=st[-1].get("phase", "encode"))
            if secs:
                rec["last_section"] = secs[-1]
            with open(results, "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(f"{label}: {k}: {status} (exit {p.returncode})", flush=True)
        print(f"{label}: {len(load(results))} of {len(keys)}, {time.time() - t0:.0f} s", flush=True)
        if on_progress and (rc := on_progress()):
            return rc, time.time() - t0


CHUNK = 20


def chunks(specs, out):
    """The specs in chunks of CHUNK points, each written to OUTDIR/chunks/ (checks and publishing
    happen between chunks)."""
    lines = [l for l in open(specs) if l.strip()]
    os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
    for i in range(0, len(lines), CHUNK):
        p = os.path.join(out, "chunks", f"{i // CHUNK:03d}.jsonl")
        open(p, "w").write("".join(lines[i:i + CHUNK]))
        yield p, [json.loads(l)["key"] for l in lines[i:i + CHUNK]]


def sizes(specs, out, n, pub=False):
    os.makedirs(out, exist_ok=True)
    results, started = os.path.join(out, "results.jsonl"), os.path.join(out, "started.jsonl")

    def progress():
        if n == 5 and (bad := check_sizes(out)):
            print("STOP (M8_PLAN 4.4):\n  " + "\n  ".join(bad[:10]), flush=True)
            open(os.path.join(out, "STOP.txt"), "w").write("\n".join(bad) + "\n")
            return 7
        return 0

    rc, wall = 0, 0.0
    for cs, pts in chunks(specs, out):
        keys = [f"{p}|{s}" for p in pts for s in SETTINGS]
        if all(k in {r["key"] for r in load(results)} for k in keys):
            continue
        rc, w = capped_loop([EXE, "sizes8c", cs, results, started, str(n), ",".join(SETTINGS)],
                            results, started, keys, f"sizes N={n}")
        wall += w
        rc = rc or progress()
        if pub:
            publish(f"eval/m8c1: sizes N = {n}, {len(load(results))} records" + (" (STOPPED)" if rc else ""))
        if rc:
            break
    tp = os.path.join(out, "timing.json")
    old = json.load(open(tp)) if os.path.exists(tp) else {"wall_s": 0.0}
    json.dump({"wall_s": round(old["wall_s"] + wall, 1), "N": n, "n": len(keys), "finished": rc == 0}, open(tp, "w"))
    return rc


def diag(specs, out, n, setting, pub=False):
    os.makedirs(out, exist_ok=True)
    results, sections = os.path.join(out, "results.jsonl"), os.path.join(out, "sections.jsonl")

    def progress():
        bad = [r["key"] for r in load(sections) if r.get("section") in ("m2", "m3", "r1") and
               any(v is False for k, v in r["data"].items() if k.startswith("check_"))]
        if bad:
            print(f"STOP: recount check failed: {bad[:5]}", flush=True)
            open(os.path.join(out, "STOP.txt"), "w").write("recount check failed:\n" + "\n".join(bad) + "\n")
            return 7
        return 0

    rc, wall = 0, 0.0
    for cs, keys in chunks(specs, out):
        if all(k in {r["key"] for r in load(results)} for k in keys):
            continue
        rc, w = capped_loop([EXE, "diag", cs, results, sections, str(n), setting], results, sections, keys,
                            f"diag {setting} N={n}")
        wall += w
        rc = rc or progress()
        if pub:
            publish(f"eval/m8c1: diag {setting} N = {n}, {len(load(results))} points" + (" (STOPPED)" if rc else ""))
        if rc:
            break
    tp = os.path.join(out, "timing.json")
    old = json.load(open(tp)) if os.path.exists(tp) else {"wall_s": 0.0}
    json.dump({"wall_s": round(old["wall_s"] + wall, 1), "N": n, "setting": setting, "n": len(keys),
               "finished": rc == 0}, open(tp, "w"))
    return rc


def status():
    lines = ["# eval/m8c1: status", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}.", ""]
    for name, n_exp in [("sizes_N5", 1200), ("sizes_N10", 1200)]:
        rs = load(os.path.join(OUT, name, "results.jsonl"))
        c = {}
        for r in rs:
            c[r["status"]] = c.get(r["status"], 0) + 1
        lines.append(f"- {name}: {len(rs)} of {n_exp} (point, setting) records" +
                     (": " + ", ".join(f"{k} {v}" for k, v in sorted(c.items())) if c else ""))
        if name == "sizes_N5" and rs:
            bad = check_sizes(os.path.join(OUT, name))
            lines.append(f"  - checks of 4.4 (flags-off equal to 8b, bound check, excluded pairs): "
                         f"{'all pass' if not bad else str(len(bad)) + ' FAIL'}")
    rs = load(os.path.join(OUT, "diag_N5", "results.jsonl"))
    lines.append(f"- diag_N5 (M6 to M8, R1 and R2 on): {len(rs)} of 400 points")
    rr = load(os.path.join(OUT, "rerun", "results.jsonl"))
    c = {}
    for r in rr:
        c[r.get("outcome")] = c.get(r.get("outcome"), 0) + 1
    stops = [r for r in rr if r.get("stop")]
    lines.append(f"- rerun of 8a: {len(rr)} of 200 runs" + (": " + ", ".join(f"{k} {v}" for k, v in sorted(c.items())) if c else ""))
    lines.append(f"  - stops: {len(stops)}" + ("".join(f"\n    - {r['key']}: {r['stop']}" for r in stops)))
    rs = load(os.path.join(OUT, "rerun", "sizes.jsonl"))
    if rs:
        lines.append(f"  - rerun sizes: {len(rs)} records")
    for p in ["sizes_N5", "sizes_N10", "diag_N5"]:
        if os.path.exists(os.path.join(OUT, p, "STOP.txt")):
            lines.append(f"- **{p} STOPPED**: see {p}/STOP.txt")
    open(os.path.join(OUT, "STATUS.md"), "w").write("\n".join(lines) + "\n")


def publish(msg):
    status()
    subprocess.run(["git", "add", "--", OUT], cwd=ROOT)
    subprocess.run(["git", "commit", "-q", "-m", msg + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
                    "--", OUT], cwd=ROOT)
    if subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, capture_output=True,
                      text=True).stdout.strip() == "m8":
        for _ in range(3):
            if subprocess.run(["git", "push", "-q", "origin", "m8"], cwd=ROOT).returncode == 0:
                break
            time.sleep(30)


if __name__ == "__main__":
    a = sys.argv[1:]
    pub = "--publish" in a
    a = [x for x in a if x != "--publish"]
    if a[:1] == ["sizes"] and len(a) == 4:
        sys.exit(sizes(a[1], a[2], int(a[3]), pub))
    if a[:1] == ["diag"] and len(a) == 5:
        sys.exit(diag(a[1], a[2], int(a[3]), a[4], pub))
    if a[:1] == ["check-sizes"] and len(a) == 2:
        b = check_sizes(a[1]); print("\n".join(b) or "all pass"); sys.exit(1 if b else 0)
    if a[:1] == ["status"]:
        status(); sys.exit(0)
    if a[:1] == ["publish"] and len(a) == 2:
        publish(a[1]); sys.exit(0)
    print(__doc__); sys.exit(2)
