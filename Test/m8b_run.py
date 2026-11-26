#!/usr/bin/env python3
"""Milestone 8b (M8_PLAN.md §4.3): run M1-M4 on the measurement points, one capped process at a time.

  python3 Test/m8b_run.py points SPECS OUTDIR N [--publish]
  python3 Test/m8b_run.py publish-loop SPECS OUTDIR SECONDS   publish STATUS.md periodically until the run ends

Runs `eval_run diag SPECS OUTDIR/results.jsonl OUTDIR/sections.jsonl N` under the 2.5 GB cap
(`Test/capped.sh`). The diag process writes each finished section of a point to sections.jsonl and a
final `ok` line to results.jsonl. If the process dies, the point it had started is recorded in
results.jsonl as `memout` (killed by the cap: exit 137, -9 or -15) or `crash`, with the last section
it finished, and the process is restarted on the remaining points. Not a stop (§4.3).
With --publish, OUTDIR/STATUS.md is written, and OUTDIR is committed and pushed to `m8`, every 25
points and at the end. Resumable: run the same command again.
"""
import json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")


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


def status(out, keys, phase):
    res = {r["key"]: r for r in load(os.path.join(out, "results.jsonl"))}
    c = {}
    for r in res.values():
        c[r["status"]] = c.get(r["status"], 0) + 1
    lines = [f"# {os.path.relpath(out, ROOT)}: status", "", f"Updated {time.strftime('%Y-%m-%d %H:%M:%S')}. Phase: {phase}.", "",
             f"- Points done: {len(res)} of {len(keys)}", "- By status: " + ", ".join(f"{k} {v}" for k, v in sorted(c.items()))]
    bad = [r["key"] for r in load(os.path.join(out, "sections.jsonl"))
           if r.get("section") in ("m2", "m3") and r["data"].get("check_total_equal") is False]
    lines.append(f"- Recount checks failed: {len(bad)}" + (": " + ", ".join(bad[:5]) if bad else ""))
    open(os.path.join(out, "STATUS.md"), "w").write("\n".join(lines) + "\n")


def publish(out, msg):
    subprocess.run(["git", "add", "--", out], cwd=ROOT)
    subprocess.run(["git", "commit", "-q", "-m", msg + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>", "--", out], cwd=ROOT)
    if subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip() == "m8":
        for _ in range(3):
            if subprocess.run(["git", "push", "-q", "origin", "m8"], cwd=ROOT).returncode == 0:
                break
            time.sleep(30)


def points(specs, out, n, pub):
    os.makedirs(out, exist_ok=True)
    results, sections = os.path.join(out, "results.jsonl"), os.path.join(out, "sections.jsonl")
    keys = [json.loads(l)["key"] for l in open(specs) if l.strip()]
    t0 = time.time()
    last_pub = len(load(results))
    while True:
        done = {r["key"] for r in load(results)}
        if all(k in done for k in keys):
            break
        p = subprocess.run([os.path.join(ROOT, "Test/capped.sh"), EXE, "diag", specs, results, sections, str(n)],
                           cwd=ROOT, capture_output=True, text=True)
        done = {r["key"] for r in load(results)}
        if p.returncode != 0:
            started = [r for r in load(sections) if r["key"] not in done]
            if not started:
                print(f"diag exited {p.returncode} with no point in progress: {p.stderr[-300:]}", flush=True); return 4
            k = started[-1]["key"]
            secs = [r["section"] for r in started if r["key"] == k and "section" in r]
            st = "memout" if p.returncode in (137, -9, -15) else "crash"
            with open(results, "a") as f:
                f.write(json.dumps({"key": k, "status": st, "exit": p.returncode, "last_section": secs[-1] if secs else None}) + "\n")
            print(f"{k}: {st} (exit {p.returncode}), last section {secs[-1] if secs else None}", flush=True)
        n_done = len(load(results))
        print(f"{n_done} of {len(keys)} points, {time.time() - t0:.0f} s", flush=True)
        if pub and n_done - last_pub >= 25:
            status(out, keys, "running"); publish(out, f"eval/m8b/points: {n_done} of {len(keys)}"); last_pub = n_done
    with open(os.path.join(out, "timing.json"), "w") as f:
        json.dump({"wall_s": round(time.time() - t0, 1), "n": len(keys), "N": n}, f)
    if pub:
        status(out, keys, "finished"); publish(out, "eval/m8b/points: finished")
    return 0


def publish_loop(specs, out, every_s):
    """Publish OUTDIR's status every `every_s` seconds until OUTDIR/timing.json exists (the run has
    ended; the driver then publishes the final status itself)."""
    keys = [json.loads(l)["key"] for l in open(specs) if l.strip()]
    while not os.path.exists(os.path.join(out, "timing.json")):
        time.sleep(every_s)
        if os.path.exists(os.path.join(out, "timing.json")):
            break
        status(out, keys, "running")
        publish(out, f"eval/m8b/points: {len(load(os.path.join(out, 'results.jsonl')))} of {len(keys)}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["points"] and len(a) in (4, 5):
        sys.exit(points(a[1], a[2], int(a[3]), a[4:] == ["--publish"]))
    if a[:1] == ["publish-loop"] and len(a) == 4:
        publish_loop(a[1], a[2], int(a[3])); sys.exit(0)
    print(__doc__); sys.exit(2)
