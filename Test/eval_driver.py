#!/usr/bin/env python3
"""Milestone 7b driver (EVAL_PLAN §3, §5, §10.3, §10.4).

  eval_driver.py specs named|pilot|full OUT.jsonl     write a spec file
  eval_driver.py run SPECS.jsonl OUTDIR [--shard-size K] [--cap-mb M] [--watchdog S]

`run` executes the specs in shards of K goals, one shard process at a time, in a per-run
slice whose memory cap (MemoryMax=M, MemorySwapMax=0) covers the shard, the solver and
everything else of the run together. Only one driver may run at a time (eval/.driver.lock);
shards die with the driver (PR_SET_PDEATHSIG); solver inputs go to OUTDIR/tmp on disk. OUTDIR gets results.jsonl (one line per goal), started.jsonl (a marker per
goal, written by the shard before it starts the goal), warmup.jsonl and header.json.

Crashes (§10.4): if a shard dies with a goal started and no result, that goal is recorded
as crash(shard, cause) and the shard is restarted with the remaining goals:
  cause "watchdog"  the driver killed it after the per-goal watchdog (300 s);
  cause "oom"       the slice's memory.events oom_kill counter rose;
  cause "signal N" / "exit N" otherwise (e.g. a manual kill);
  cause "unknown"   found on resume: a marker without a result from an earlier driver.
Resume: rerunning `run` skips every key that has a result line; a trailing partial line
(the shard was killed while writing) is removed first.
"""
import ctypes, fcntl, json, os, random, re, shutil, signal, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")
CG = "/sys/fs/cgroup/user.slice/user-%d.slice/user@%d.service" % (os.getuid(), os.getuid())

# pre-registered (NOTES.md, milestone 7)
SEED_R1B, N_R1B = 70005, 300
SEED_PILOT_A, SEED_PILOT_B, PILOT_PER_TIER, PILOT_R1B = 70006, 70007, 50, 20
SHARD_SIZE, CAP_MB, WATCHDOG_S = 50, 2500, 300


def die_with_parent():
    """preexec_fn: the child gets SIGKILL when the driver dies, so no shard is orphaned
    (an orphaned shard plus a new run caused a global OOM on 18 November)."""
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG


def load(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as f:
        for l in f:
            try:
                out.append(json.loads(l))
            except json.JSONDecodeError:
                pass
    return out


def corpus(tier):
    return [r for r in load(os.path.join(ROOT, "eval", f"corpus_{tier}.jsonl")) if "header" not in r]


def spec(r, run):
    s = {"key": f"{run}:{r['id']}", "id": r["id"], "run": run, "tier": r["tier"], "thm": r["thm"],
         "H": r["H_main"] if run == "main" else r["H_full"], "baselines": run == "main",
         "H_main_size": len(r["H_main"])}
    if r["tier"] == "B":
        s["pos"], s["nctx"] = r["pos"], r["nctx"]
    return s


def r1b_sample():
    ids = [r["id"] for r in corpus("B")]
    return random.Random(SEED_R1B).sample(ids, N_R1B)


def named_specs():
    src = open(os.path.join(ROOT, "Test/EvalNamed.lean")).read()
    out = []
    for m in re.finditer(r'\("([\w-]+)", ``(\w+), \[([^\]]*)\], \[([^\]]*)\], "([^"]*)"\)', src):
        name, goal, hs, opts, expect = m.groups()
        H = [h.strip().lstrip("`") for h in hs.split(",") if h.strip()]
        H = [h if "." in h or h in ("maxL",) else h for h in H]
        H = ["EvalNamed.maxL" if h == "maxL" else h for h in H]
        out.append({"key": f"named:{name}", "id": name, "run": "named", "tier": "named",
                    "thm": f"EvalNamed.{goal}", "H": H, "baselines": False,
                    "opts": [o.strip().strip('"') for o in opts.split(",") if o.strip()],
                    "expect": expect})
    return out


def make_specs(kind):
    if kind == "named":
        return named_specs()
    A, B = corpus("A"), corpus("B")
    byid = {r["id"]: r for r in B}
    r1b = r1b_sample()
    if kind == "pilot":
        a = random.Random(SEED_PILOT_A).sample([r["id"] for r in A], PILOT_PER_TIER)
        b = random.Random(SEED_PILOT_B).sample([r["id"] for r in B], PILOT_PER_TIER)
        ida = {r["id"]: r for r in A}
        return ([spec(ida[i], "main") for i in a] + [spec(byid[i], "main") for i in b]
                + [spec(byid[i], "r1b") for i in r1b[:PILOT_R1B]])
    if kind == "full":
        return [spec(r, "main") for r in A] + [spec(r, "main") for r in B] + [spec(byid[i], "r1b") for i in r1b]
    raise SystemExit(f"unknown spec kind {kind}")


def git_commit():
    h = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    d = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT,
                       capture_output=True, text=True).stdout.strip() != ""
    return h, d


def fix_trailing(path):
    """Drop a trailing partial line (a shard killed while writing)."""
    if not os.path.exists(path):
        return
    with open(path, "rb+") as f:
        data = f.read()
        if data and not data.endswith(b"\n"):
            f.truncate(data.rfind(b"\n") + 1)


def oom_kills(slice_name):
    try:
        for l in open(os.path.join(CG, slice_name, "memory.events")):
            k, v = l.split()
            if k == "oom_kill":
                return int(v)
    except OSError:
        return None
    return 0


def append(path, obj):
    with open(path, "a") as f:
        f.write(json.dumps(obj, sort_keys=True) + "\n")
        f.flush()


def run(specs_path, outdir, shard_size, cap_mb, watchdog):
    os.makedirs(outdir, exist_ok=True)
    results, started, warmup = (os.path.join(outdir, f) for f in ("results.jsonl", "started.jsonl", "warmup.jsonl"))
    specs = load(specs_path)
    commit, dirty = git_commit()
    hdr = {"specs": os.path.abspath(specs_path), "n_specs": len(specs), "toolchain": "4.36.0",
           "git_commit": commit, "git_dirty": dirty, "shard_size": shard_size, "cap_mb": cap_mb,
           "watchdog_s": watchdog, "nmax": 10, "solver_s": 20, "loop_s": 120,
           "baseline_heartbeats": 200000, "sbe_max_depth": 10,
           "seeds": {"r1b": SEED_R1B, "pilot_A": SEED_PILOT_A, "pilot_B": SEED_PILOT_B}}
    hpath = os.path.join(outdir, "header.json")
    if not os.path.exists(hpath):
        json.dump(hdr, open(hpath, "w"), indent=1, sort_keys=True)
    fix_trailing(results)
    done = {r["key"] for r in load(results)}
    # resume: a marker without a result from an earlier driver is a crash of unknown cause
    for r in load(started):
        if r["key"] not in done:
            last = max((x.get("N", 0) for x in load(started) if x["key"] == r["key"]), default=0)
            append(results, {"key": r["key"], "outcome": "crash", "cause": "unknown", "found": "on resume",
                             "last_N": last or None})
            done.add(r["key"])
            print(f"resume: {r['key']} started earlier with no result: crash(shard, unknown)", flush=True)
    pending = [s for s in specs if s["key"] not in done]
    print(f"{len(specs)} specs, {len(specs) - len(pending)} done, {len(pending)} to run", flush=True)
    # one driver at a time, machine-wide
    lock = open(os.path.join(ROOT, "eval", ".driver.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("STOP: another eval driver is running", flush=True)
        return 6
    # solver inputs on disk, not in the tmpfs /tmp (which is RAM)
    tmpdir = os.path.join(os.path.abspath(outdir), "tmp")
    os.makedirs(tmpdir, exist_ok=True)
    env = dict(os.environ, TMPDIR=tmpdir)
    slice_name = f"evalrun{os.getpid()}.slice"
    keeper = subprocess.Popen(["systemd-run", "--user", "--scope", "-q", f"--slice={slice_name}",
                               "sleep", "infinity"], start_new_session=True, preexec_fn=die_with_parent)
    time.sleep(0.5)
    # the cap applies to the whole slice: shard, solver and keeper together
    subprocess.run(["systemctl", "--user", "set-property", "--runtime", slice_name,
                    f"MemoryMax={cap_mb}M", "MemorySwapMax=0"], check=True)
    t_start = time.monotonic()
    rc_all = 0
    try:
        for i in range(0, len(pending), shard_size):
            shard = pending[i:i + shard_size]
            shard_file = os.path.join(outdir, f"shard_{i // shard_size:04d}.jsonl")
            with open(shard_file, "w") as f:
                for s in shard:
                    f.write(json.dumps(s) + "\n")
            while True:
                fix_trailing(results)
                done = {r["key"] for r in load(results)}
                left = [s for s in shard if s["key"] not in done]
                if not left:
                    break
                n_started0 = len(load(started))
                oom0 = oom_kills(slice_name)
                p = subprocess.Popen(["systemd-run", "--user", "--scope", "-q", f"--slice={slice_name}",
                                      "-p", f"MemoryMax={cap_mb}M", "-p", "MemorySwapMax=0",
                                      EXE, "run", shard_file, results, started, warmup],
                                     cwd=ROOT, env=env, start_new_session=True,
                                     preexec_fn=die_with_parent)
                cur, since, killed = None, None, False
                while p.poll() is None:
                    time.sleep(0.5)
                    st = load(started)
                    if len(st) > n_started0 and st[-1]["key"] != cur:
                        cur, since = st[-1]["key"], time.monotonic()
                    if (cur and since and time.monotonic() - since > watchdog and not killed
                            and cur not in {r["key"] for r in load(results)}):
                        print(f"watchdog: {cur} over {watchdog} s, killing the shard", flush=True)
                        os.killpg(p.pid, signal.SIGKILL)
                        killed = True
                rc = p.returncode
                shutil.rmtree(tmpdir, ignore_errors=True)   # inputs left by a killed solver
                os.makedirs(tmpdir, exist_ok=True)
                if rc == 0:
                    continue
                if rc in (3, 4):
                    print(f"STOP: shard exited with {rc} ({'decoder bug or solver error' if rc == 3 else 'harness error'}; see results.jsonl)", flush=True)
                    return rc
                fix_trailing(results)
                done = {r["key"] for r in load(results)}
                lost, last_n = [], {}
                for r in load(started)[n_started0:]:
                    if r["key"] not in done:
                        if r["key"] not in lost:
                            lost.append(r["key"])
                        if "N" in r:
                            last_n[r["key"]] = r["N"]
                oom1 = oom_kills(slice_name)
                if killed:
                    cause = "watchdog"
                elif oom0 is not None and oom1 is not None and oom1 > oom0:
                    cause = "oom"
                elif rc < 0:
                    cause = f"signal {-rc}"
                else:
                    cause = f"exit {rc}"
                if not lost:
                    print(f"STOP: shard died ({cause}) with no started goal unfinished", flush=True)
                    return 5
                for k in lost:
                    el = round(time.monotonic() - since, 1) if (k == cur and since) else None
                    append(results, {"key": k, "outcome": "crash", "cause": cause, "last_N": last_n.get(k),
                                     "elapsed_s": el})
                    print(f"crash(shard, {cause}) on {k}", flush=True)
            n_done = len({r['key'] for r in load(results)})
            print(f"shard {i // shard_size}: done; {n_done} results; {time.monotonic() - t_start:.0f} s", flush=True)
    finally:
        os.killpg(keeper.pid, signal.SIGKILL)
        append(os.path.join(outdir, "driver.jsonl"),
               {"wall_s": round(time.monotonic() - t_start, 1), "pending_at_start": len(pending),
                "results_at_end": len({r["key"] for r in load(results)})})
    return rc_all


def main():
    a = sys.argv[1:]
    if a[:1] == ["specs"]:
        with open(a[2], "w") as f:
            for s in make_specs(a[1]):
                f.write(json.dumps(s, sort_keys=True) + "\n")
        print(f"wrote {sum(1 for _ in open(a[2]))} specs to {a[2]}")
        return 0
    if a[:1] == ["run"]:
        opts = dict(zip(a[3::2], a[4::2]))
        return run(a[1], a[2], int(opts.get("--shard-size", SHARD_SIZE)),
                   int(opts.get("--cap-mb", CAP_MB)), int(opts.get("--watchdog", WATCHDOG_S)))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
