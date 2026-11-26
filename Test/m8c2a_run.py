#!/usr/bin/env python3
"""Milestone 8c-2a (M8_PLAN.md 4.5): R3 simulated with shared residual objects.

  python3 Test/m8c2a_run.py models [--publish]          the model check on 8c-1's 90 models (a stop rule)
  python3 Test/m8c2a_run.py sim SPECS OUTDIR N [--publish]   the projection, R3 off and on (eval_run diag … r3)
  python3 Test/m8c2a_run.py check OUTDIR N              the consistency checks on finished points
  python3 Test/m8c2a_run.py status                      write eval/m8c2a/STATUS.md
  python3 Test/m8c2a_run.py publish MESSAGE             status, commit eval/m8c2a, push m8

One `eval_run` process at a time under the 2.5 GB cap (Test/capped.sh), points in chunks of 20, as 8c-1's
`Test/m8c1_run.py` (whose `capped_loop` and `chunks` this reuses). A point that runs out of memory is
recorded as `memout` with the last section it finished.

Stop rules (exit codes):
- 8: the model check fails (a binding that does not hold, a chosen candidate whose templates do not unify,
  a binding that cannot be read, a proof that is not kernel-checked, or a skeleton that differs from 8c-1's);
- 7: a consistency check fails: with R3 off, the clauses, variables or a family's count differ from 8c-1's
  R1-and-R2 sizes at that N; at N = 5, the typing clauses differ from M6's; an anomaly (a right side not
  located) in either setting.
"""
import json, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from m8c1_run import load, capped_loop, chunks  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")
OUT = os.path.join(ROOT, "eval", "m8c2a")
M8C1 = os.path.join(ROOT, "eval", "m8c1")
MODEL_SETS = [("m8a", "eval/m8b/specs_models.jsonl"), ("named", "eval/m8b/specs_named.jsonl")]


def sections(out):
    s = {}
    for r in load(os.path.join(out, "sections.jsonl")):
        if "section" in r:
            s.setdefault(r["key"], {})[r["section"]] = r["data"]
    return s


def check_models():
    bad = []
    for name, spec in MODEL_SETS:
        ref = {r["key"]: r for r in load(os.path.join(M8C1, "models", f"{name}.jsonl"))}
        for r in load(os.path.join(OUT, "models", f"{name}.jsonl")):
            k = r["key"]
            if r.get("result") != "sat" or r.get("proof") != "ok":
                bad.append(f"{k}: result {r.get('result')}, proof {r.get('proof')} {r.get('error', '')}")
                continue
            if ref.get(k, {}).get("skeleton") != r.get("skeleton"):
                bad.append(f"{k}: skeleton differs from 8c-1's")
            if r["failures"] or r["unreadable"] or r["readback_conflicts"] or r["checked"].get("missing"):
                bad.append(f"{k}: failures {r['failures'][:3]}, unreadable {r['unreadable']}, "
                           f"conflicts {r['readback_conflicts']}")
    return bad


def models(pub=False):
    os.makedirs(os.path.join(OUT, "models"), exist_ok=True)
    t0 = time.time()
    for name, spec in MODEL_SETS:
        res = os.path.join(OUT, "models", f"{name}.jsonl")
        p = subprocess.run([os.path.join(ROOT, "Test/capped.sh"), EXE, "r3-models", spec, res], cwd=ROOT,
                           capture_output=True, text=True)
        with open(os.path.join(OUT, "models", "run.log"), "a") as f:
            f.write(p.stderr[-2000:] + f"EXIT {p.returncode}\n")
        if p.returncode != 0:
            print(f"models {name}: exit {p.returncode}", flush=True)
            return 4
    json.dump({"wall_s": round(time.time() - t0, 1)}, open(os.path.join(OUT, "models", "timing.json"), "w"))
    bad = check_models()
    n = sum(len(load(os.path.join(OUT, "models", f"{nm}.jsonl"))) for nm, _ in MODEL_SETS)
    if n != 90:
        bad.append(f"{n} model records, not 90")
    if bad:
        open(os.path.join(OUT, "models", "STOP.txt"), "w").write("\n".join(bad) + "\n")
        print("STOP (model check):\n  " + "\n  ".join(bad[:10]), flush=True)
    if pub:
        publish("eval/m8c2a: model check" + (" FAILED (stop)" if bad else ", all bindings hold"))
    return 8 if bad else 0


def ref_sizes(n):
    return {r["point"]: r for r in load(os.path.join(M8C1, f"sizes_N{n}", "results.jsonl"))
            if r.get("setting") == "r1r2" and r.get("status") == "ok"}


def ref_m6():
    out = {}
    for r in load(os.path.join(M8C1, "diag_N5", "sections.jsonl")):
        if r.get("section") == "m6_r3":
            b = r["data"]["by"]
            out[r["key"]] = (b.get("typing clauses", {}).get("clauses", 0),
                             b.get("typing clauses, templates do not unify", {}).get("clauses", 0))
    return out


def check(out, n):
    """The consistency checks of 4.5 on the points finished so far."""
    ref = ref_sizes(n)
    m6 = ref_m6() if n == 5 else {}
    bad = []
    for k, s in sections(out).items():
        off, on = s.get("r3_off"), s.get("r3_on")
        if off is None:
            continue
        r = ref.get(k)
        if r is None:
            bad.append(f"{k}: no 8c-1 R1-and-R2 record at N = {n}"); continue
        if off["clauses"] != r["clauses"] or off["vars"] != r["vars"] or off["families"] != r["families"]:
            bad.append(f"{k}: R3 off {off['clauses']} clauses, {off['vars']} vars; 8c-1 {r['clauses']}, {r['vars']}")
        if off["early_exit"]:
            continue
        if n == 5:
            want = m6.get(k)
            got = (off["typing_unify"], off["typing_no_unify"])
            if want != got:
                bad.append(f"{k}: typing clauses {got}, M6 {want}")
        for x in (off, on):
            if x is not None and x["anomalies"]:
                bad.append(f"{k}: {x['anomalies']} anomalies (r3 {x['r3']})")
    return bad


def sim(specs, out, n, pub=False):
    os.makedirs(out, exist_ok=True)
    results, secs = os.path.join(out, "results.jsonl"), os.path.join(out, "sections.jsonl")

    def progress():
        if bad := check(out, n):
            print("STOP (M8_PLAN 4.5, consistency):\n  " + "\n  ".join(bad[:10]), flush=True)
            open(os.path.join(out, "STOP.txt"), "w").write("\n".join(bad) + "\n")
            return 7
        return 0

    rc, wall = 0, 0.0
    for cs, keys in chunks(specs, out):
        if all(k in {r["key"] for r in load(results)} for k in keys):
            continue
        rc, w = capped_loop([EXE, "diag", cs, results, secs, str(n), "r3"], results, secs, keys, f"sim N={n}")
        wall += w
        rc = rc or progress()
        if pub:
            publish(f"eval/m8c2a: R3 simulation N = {n}, {len(load(results))} points" + (" (STOPPED)" if rc else ""))
        if rc:
            break
    tp = os.path.join(out, "timing.json")
    old = json.load(open(tp)) if os.path.exists(tp) else {"wall_s": 0.0}
    json.dump({"wall_s": round(old["wall_s"] + wall, 1), "N": n, "finished": rc == 0}, open(tp, "w"))
    return rc


def status():
    lines = ["# eval/m8c2a: status", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}.", ""]
    ms = [r for nm, _ in MODEL_SETS for r in load(os.path.join(OUT, "models", f"{nm}.jsonl"))]
    lines.append(f"- model check: {len(ms)} of 90 models" +
                 (f", {'all bindings hold' if not check_models() else 'FAILED'}" if ms else ""))
    for n in (5, 10):
        d = os.path.join(OUT, f"sim_N{n}")
        rs = load(os.path.join(d, "results.jsonl"))
        c = {}
        for r in rs:
            c[r["status"]] = c.get(r["status"], 0) + 1
        lines.append(f"- sim_N{n}: {len(rs)} of 400 points" +
                     (": " + ", ".join(f"{k} {v}" for k, v in sorted(c.items())) if c else ""))
        if rs:
            bad = check(d, n)
            lines.append(f"  - consistency checks (R3 off equal to 8c-1{', typing equal to M6' if n == 5 else ''}): "
                         f"{'all pass' if not bad else str(len(bad)) + ' FAIL'}")
        if os.path.exists(os.path.join(d, "STOP.txt")):
            lines.append(f"- **sim_N{n} STOPPED**: see sim_N{n}/STOP.txt")
    if os.path.exists(os.path.join(OUT, "models", "STOP.txt")):
        lines.append("- **model check STOPPED**: see models/STOP.txt")
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
    if a[:1] == ["models"]:
        sys.exit(models(pub))
    if a[:1] == ["sim"] and len(a) == 4:
        sys.exit(sim(a[1], a[2], int(a[3]), pub))
    if a[:1] == ["check"] and len(a) == 3:
        b = check(a[1], int(a[2])); print("\n".join(b) or "all pass"); sys.exit(1 if b else 0)
    if a[:1] == ["status"]:
        status(); sys.exit(0)
    if a[:1] == ["publish"] and len(a) == 2:
        publish(a[1]); sys.exit(0)
    print(__doc__); sys.exit(2)
