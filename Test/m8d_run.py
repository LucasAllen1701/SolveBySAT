#!/usr/bin/env python3
"""Milestone 8d (M8_PLAN.md 4.6): the evaluation of the tactic as users run it.

  python3 Test/m8d_run.py pilot-specs                  eval/m8d/specs_pilot.jsonl: the 5 highest-ranked goals per group
  python3 Test/m8d_run.py run SPECS OUTDIR [--after-shard CMD]
                                                       the runs and their sizes (Test/m8a_run.py's `run`)
  python3 Test/m8d_run.py projection OUTDIR            the pilot's times and the projection for the 300 runs
  python3 Test/m8d_run.py status OUTDIR PHASE          write eval/m8d/STATUS.md
  python3 Test/m8d_run.py publish OUTDIR PHASE MSG     status, then commit eval/m8d and push m8

`run` sets the milestone 8 flags as the tactic's defaults have them (R1 and R2 on:
SOLVE_BY_SAT_EVAL_FLAGS=nodeBounds,exclusivePairs; the harness's own default is both off) and the
reference run of 4.6's exactness stop rules (SOLVE_BY_SAT_EVAL_COMPARE=eval/m8d/inputs/results.jsonl,
milestone 7's eval/final/results.jsonl). Then it calls Test/m8a_run.py's `run`: Test/eval_driver.py
(the 2.5 GB slice cap, the 300 s watchdog, crash records, exit 3, 4, 6, and 9 for an exactness stop,
in the shard or on a crash record the driver writes), then the countOnly sizes at N = 5 and the run's
last N, each spec in its own capped process. Resumable: run the same command again.
"""
import json, os, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Test"))
import m8a_run  # noqa: E402

D = os.path.join(ROOT, "eval", "m8d")
INP = os.path.join(D, "inputs")
GROUPS = ["crash_B", "crash_A", "control_proved", "control_no_proof"]
FULL = {"crash_B": 100, "crash_A": 100, "control_proved": 50, "control_no_proof": 50}
PILOT = 5
FLAGS = "nodeBounds,exclusivePairs"
load = m8a_run.load


def specs():
    return load(os.path.join(D, "specs.jsonl"))


def pilot_specs():
    out, seen = [], {}
    for s in specs():   # specs.jsonl is in sample order: group order, rank order within each group
        g = s["m8d_group"]
        seen[g] = seen.get(g, 0) + 1
        if seen[g] <= PILOT:
            out.append(s)
    with open(os.path.join(D, "specs_pilot.jsonl"), "w") as f:
        for s in out:
            f.write(json.dumps(s, sort_keys=True) + "\n")
    print(f"wrote {len(out)} pilot specs")


def run(sp, out, hook):
    os.environ["SOLVE_BY_SAT_EVAL_FLAGS"] = FLAGS
    os.environ["SOLVE_BY_SAT_EVAL_COMPARE"] = os.path.join(INP, "results.jsonl")
    return m8a_run.run(sp, out, hook)


def m7_secs(r):
    """Milestone 7's time for the N loop of a goal: loop_ms, or for a crash record its elapsed time
    less its baselines (milestone 7 ran the baselines first; 8d runs none)."""
    if r.get("loop_ms") is not None:
        return r["loop_ms"] / 1000
    bl = sum((b or {}).get("ms", 0) for b in (r.get("baselines") or {}).values()) / 1000
    return max(0.0, (r.get("elapsed_s") or 300.0) - bl)


def secs(r):   # the shard's total time, or for a crash the driver's elapsed time
    return (r["total_ms"] / 1000) if r.get("total_ms") is not None else (r.get("elapsed_s") or 300.0)


def projection(out):
    m7 = {r["key"]: r for r in load(os.path.join(INP, "results.jsonl"))}
    grp = {s["key"]: s["m8d_group"] for s in specs()}
    res = {r["key"]: r for r in load(os.path.join(out, "results.jsonl"))}
    siz = load(os.path.join(out, "sizes.jsonl"))
    tm = json.load(open(os.path.join(out, "timing.json")))
    tot_run = sum(secs(r) for r in res.values())
    over_run = max(0.0, tm["runs_s"] - tot_run) / len(res)
    tot_siz = sum((z.get("ms") or 0) for z in siz) / 1000
    over_siz = max(0.0, tm["sizes_s"] - tot_siz) / max(1, len(siz))
    print("| group | goal | outcome | N | 8d s | sizes s | milestone 7 outcome | milestone 7 loop s |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for k, r in res.items():
        z = sum((x.get("ms") or 0) / 1000 + over_siz for x in siz if x["key"].startswith(k + "@"))
        print(f"| {grp[k]} | `{k}` | {r['outcome']} | {m8a_run.last_n(r)} | {secs(r):.1f} | {z:.1f} | "
              f"{m7[k]['outcome']} | {m7_secs(m7[k]):.1f} |")
    print()
    print("| group | pilot runs | mean s per run (with overhead) | mean s of sizes per run | ratio to milestone 7 | "
          "projected h (mean) | projected h (scaled by milestone 7) | projected h |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- |")
    total = 0.0
    for g in GROUPS:
        ks = [k for k in res if grp[k] == g]
        if not ks:
            continue
        a = statistics.mean(secs(res[k]) + over_run for k in ks)
        b = statistics.mean(sum((x.get("ms") or 0) / 1000 + over_siz for x in siz if x["key"].startswith(k + "@")) for k in ks)
        m7p = sum(m7_secs(m7[k]) for k in ks)
        ratio = sum(secs(res[k]) + over_run for k in ks) / m7p if m7p else float("nan")
        allk = [s["key"] for s in specs() if s["m8d_group"] == g]
        h_mean = FULL[g] * (a + b) / 3600
        h_scaled = (ratio * sum(m7_secs(m7[k]) for k in allk) + FULL[g] * b) / 3600 if m7p else h_mean
        h = max(h_mean, h_scaled)
        total += h
        print(f"| {g} | {len(ks)} | {a:.1f} | {b:.1f} | {ratio:.2f} | {h_mean:.2f} | {h_scaled:.2f} | {h:.2f} |")
    print(f"\nPilot wall time: runs {tm['runs_s'] / 60:.1f} min, sizes {tm['sizes_s'] / 60:.1f} min. "
          f"Projection for the 300 runs (the larger of the two per group): {total:.1f} h, the pilot included.")


def status(out, phase):
    sp = specs()
    grp = {s["key"]: s["m8d_group"] for s in sp}
    res = {r["key"]: r for r in load(os.path.join(out, "results.jsonl"))}
    siz = load(os.path.join(out, "sizes.jsonl"))
    lines = ["# eval/m8d: status", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}. Phase: {phase}.", "",
             f"- Goals done: {len(res)} of {len(sp)}",
             f"- Stops: {sum(1 for r in res.values() if 'stop' in r)}"
             + "".join(f"; `{k}`: {r['stop']}" for k, r in res.items() if "stop" in r),
             f"- Sizes done: {len(siz)}", "",
             "| group | done | proved | no proof ≤ N | memory crash | timeout | other |",
             "| --- | --- | --- | --- | --- | --- | --- |"]
    for g in GROUPS:
        rs = [r for k, r in res.items() if grp.get(k) == g]
        c = {o: sum(1 for r in rs if r["outcome"] == o) for o in ("proved", "no_proof_le_Nmax", "crash", "timeout")}
        crash_oom = sum(1 for r in rs if r["outcome"] == "crash" and r.get("cause") == "oom")
        crash_wd = sum(1 for r in rs if r["outcome"] == "crash" and r.get("cause") == "watchdog")
        lines.append(f"| {g} | {len(rs)} of {FULL[g]} | {c['proved']} | {c['no_proof_le_Nmax']} | {crash_oom} | "
                     f"{c['timeout'] + crash_wd} | {len(rs) - sum(c.values()) + c['crash'] - crash_oom - crash_wd} |")
    lines += ["", "Timeout counts the N-loop limit and the 300 s watchdog; other counts any other outcome or crash cause."]
    open(os.path.join(D, "STATUS.md"), "w").write("\n".join(lines) + "\n")


def publish(out, phase, msg):
    status(out, phase)
    subprocess.run(["git", "add", "--", "eval/m8d"], cwd=ROOT)
    subprocess.run(["git", "commit", "-q", "-m", msg + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
                    "--", "eval/m8d"], cwd=ROOT)
    br = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if br != "m8":
        print("not on m8: not pushing"); return 1
    for _ in range(3):
        if subprocess.run(["git", "push", "-q", "origin", "m8"], cwd=ROOT).returncode == 0:
            return 0
        time.sleep(30)
    print("push failed (will retry at the next publish)")
    return 1


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["pilot-specs"]:
        pilot_specs()
    elif a[:1] == ["run"] and len(a) in (3, 5) and (len(a) == 3 or a[3] == "--after-shard"):
        sys.exit(run(a[1], a[2], a[4] if len(a) == 5 else None))
    elif a[:1] == ["projection"] and len(a) == 2:
        projection(a[1])
    elif a[:1] == ["status"] and len(a) == 3:
        status(a[1], a[2])
    elif a[:1] == ["publish"] and len(a) == 4:
        sys.exit(publish(a[1], a[2], a[3]))
    else:
        print(__doc__); sys.exit(2)
