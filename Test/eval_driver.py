#!/usr/bin/env python3
"""Milestone 7b driver (EVAL_PLAN §3, §5, §10.3, §10.4).

  eval_driver.py specs named|pilot|full OUT.jsonl     write a spec file
  eval_driver.py run SPECS.jsonl OUTDIR [--shard-size K] [--cap-mb M] [--watchdog S]
                [--after-shard CMD] [--min-free-mb F]

`run` executes the specs in shards of K goals, one shard process at a time, in a per-run
slice whose memory cap (MemoryMax=M, MemorySwapMax=0) covers the shard, the solver and
everything else of the run together. Only one driver may run at a time (eval/.driver.lock);
shards die with the driver (PR_SET_PDEATHSIG); solver inputs go to OUTDIR/tmp on disk. OUTDIR gets results.jsonl (one line per goal), started.jsonl (a marker per
goal, written by the shard before it starts the goal), baselines.jsonl (each goal's baselines,
written before its N loop and merged into its crash record if it crashes), warmup.jsonl and
header.json.

Crashes (§10.4): if a shard dies with a goal started and no result, that goal is recorded
as crash(shard, cause) and the shard is restarted with the remaining goals:
  cause "watchdog"  the driver killed it after the per-goal watchdog (300 s);
  cause "oom"       the slice's memory.events oom_kill counter rose;
  cause "signal N" / "exit N" otherwise (e.g. a manual kill);
  cause "unknown"   found on resume: a marker without a result from an earlier driver.
Resume: rerunning `run` skips every key that has a result line; a trailing partial line
(the shard was killed while writing) is removed first.

Stops (§10.5, full-run instructions), besides exit 3 and 4 from the shard:
  exit 7  the machine's memory outside the run slice fell below --min-free-mb (1024):
          MemAvailable minus what the slice may still take (cap - memory.current). The
          shard is killed and the unfinished goal's markers are removed, so a rerun runs it
          again (this is an external stop, not a property of the goal);
  exit 8  a crash cause other than oom or watchdog occurred a second time in OUTDIR.
--after-shard CMD is run (through the shell, with OUTDIR as $1) after each completed shard
(the final status after a stop is written by the wrapper, Test/eval_full.sh); a failing
hook is logged and does not stop the run.
"""
import ctypes, fcntl, json, os, random, re, shutil, signal, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, ".lake/build/bin/eval_run")
CG = "/sys/fs/cgroup/user.slice/user-%d.slice/user@%d.service" % (os.getuid(), os.getuid())

# pre-registered (NOTES.md, milestone 7)
SEED_R1B, N_R1B = 70005, 300
SEED_PILOT_A, SEED_PILOT_B, PILOT_PER_TIER, PILOT_R1B = 70006, 70007, 50, 20
SHARD_SIZE, CAP_MB, WATCHDOG_S = 50, 2500, 300
PARALLEL_SHARDS = 1          # P of §10.5 decision 4 (owner's choice for the test machine)
MIN_FREE_MB = 1024           # stop condition: memory outside the evaluation slice


def reference_of(r):
    """8c-1/8d (M8_PLAN 4.4, 4.6): one reference record's answers, as `referenceOf` in
    Test/EvalRun.lean: the N where it was UNSAT (per-N rows; for a crash, and for a timeout without
    per-N rows, every N below last_N) and the N of its proof, if any."""
    rows = r.get("per_N") or []
    unsat = set()
    if r.get("outcome") == "crash" or (r.get("outcome") == "timeout" and not rows):
        unsat |= set(range(1, r.get("last_N") or 1))
    unsat |= {x["N"] for x in rows if x.get("result") == "unsat"}
    return unsat, (r.get("N") if r.get("outcome") == "proved" else None)


def load_reference(path):
    return {r["key"]: reference_of(r) for r in load(path)}


def crash_exactness(ref, last_n):
    """8d (M8_PLAN 4.6): the stop rules for a crash record written by the driver. The run passed
    every N below last_N without a proof, so it was UNSAT (or exited early) there."""
    if ref is None:
        return "the goal is not in the reference run"
    _, proved = ref
    if proved is not None and last_n is not None and proved < last_n:
        return f"passed N = {proved} without a proof (crash at N = {last_n}), where the reference run found a proof"
    return None


def exactness_selftest():
    """8d (M8_PLAN 4.6): the driver's crash-record check flags a crash past the reference's proof
    and nothing else; reference_of agrees with the Lean referenceOf on the hand-made records."""
    proved = reference_of({"outcome": "proved", "N": 3, "per_N": [{"N": 1, "result": "unsat"}, {"N": 3, "result": "proved"}]})
    crash = reference_of({"outcome": "crash", "cause": "oom", "last_N": 4})
    tmo = reference_of({"outcome": "timeout", "last_N": 3})
    cases = [("2 a crash at N = 5 past the reference's proof at N = 3", proved, 5, True),
             ("2 a crash at N = 4 past the reference's proof at N = 3", proved, 4, True),
             ("agree: a crash at the reference's proof N", proved, 3, False),
             ("agree: a crash below the reference's proof N", proved, 2, False),
             ("agree: a crash against a reference crash", crash, 9, False),
             ("agree: a crash with no N reached", proved, None, False),
             ("a goal missing from the reference", None, 2, True)]
    fails = 0
    for name, ref, n, want in cases:
        got = crash_exactness(ref, n)
        ok = bool(got) == want
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {name}: {got or 'no stop'}")
    for name, got, want in [("reference of a crash", crash, ({1, 2, 3}, None)),
                            ("reference of a timeout without rows", tmo, ({1, 2}, None)),
                            ("reference of a proof", proved, ({1}, 3))]:
        ok = got == want
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {name}: {got}")
    print(f"driver exactness (M8_PLAN 4.6): {len(cases) + 3 - fails} passed, {fails} failed")
    return 1 if fails else 0


M9A3_GROUPS_FRESH = ("rewrite_B", "rewrite_A", "control")


def m9a3_stop(exp, r):
    """9a-3 (M9_PLAN 4.4, amendment 6.2 decision 6): the stop rules for one result record `r` against its line
    `exp` of eval/m9a3/expect.jsonl (None: the goal is not there).
    - A decoder failure (the shard also exits 3 on it).
    - A lost proof (`exp["lost_rule"]`: a group 1 goal whose 8c-1 proof used none of the probe's rules, or a group
      3 goal): no proof at or below the earlier N `Ne`, certified: UNSAT or the early exit at some N >= Ne, the N
      loop ending with no proof up to Nmax, a proof above Ne, or a crash record whose run passed Ne (last_N > Ne:
      every N below last_N was UNSAT or exited early). A run that hits a limit before Ne is not a stop.
    - Groups 2 and 3 (exactness): a proof that uses no generated rule (`rules_used`) and no `propext` path
      (`propext_used`) at an N where milestone 7's answer was UNSAT (`m7_unsat`)."""
    if exp is None:
        return "the goal is not in the 9a-3 expectations"
    out = r.get("outcome")
    if out in ("decoder_bug", "solver_error"):
        return f"a decoder failure (M9_PLAN 4.4): {out}: {str(r.get('reason', ''))[:200]}"
    if exp.get("lost_rule"):
        ne = exp["earlier_N"]
        why = None
        if out == "no_proof_le_Nmax":
            why = f"no proof up to N = {r.get('N')}"
        elif out == "proved" and r.get("N", 0) > ne:
            why = f"a proof only at N = {r['N']}"
        elif out == "crash" and (r.get("last_N") or 0) > ne:
            why = f"a crash at N = {r['last_N']}, after passing N = {ne}"
        else:
            for x in r.get("per_N") or []:
                if x.get("result") in ("unsat", "early_exit") and x.get("N", 0) >= ne:
                    why = f"{x['result']} at N = {x['N']}"
                    break
        if why:
            return f"a lost proof (M9_PLAN 4.4): {why}; the {exp['earlier']} proof is at N = {ne}"
    if exp.get("group") in M9A3_GROUPS_FRESH and out == "proved":
        n = r.get("N")
        if n in (exp.get("m7_unsat") or []) and not r.get("rules_used") and not r.get("propext_used"):
            return (f"exactness (M9_PLAN 4.4): a proof at N = {n} with no generated rule and no propext path, "
                    f"where milestone 7 was UNSAT")
    return None


def m9a3_selftest():
    """9a-3 (M9_PLAN 4.4): the driver's 9a-3 rule flags a hand-made case of each stop, and nothing else."""
    row = lambda n, res: {"N": n, "result": res}
    g1 = {"key": "k", "group": "g1_control", "earlier": "8c-1", "earlier_N": 3, "lost_rule": True}
    g1p = dict(g1, group="g1_rewrite_B", lost_rule=False)
    g3 = {"key": "k", "group": "control", "earlier": "m7", "earlier_N": 2, "lost_rule": True, "m7_unsat": [1]}
    g2 = {"key": "k", "group": "rewrite_B", "earlier": "m7", "earlier_N": None, "lost_rule": False,
          "m7_unsat": [1, 2, 3, 4]}
    proved = lambda n, **kw: dict({"outcome": "proved", "N": n, "per_N": [row(i, "unsat") for i in range(1, n)] +
                                   [row(n, "proved")], "rules_used": [], "propext_used": 0}, **kw)
    cases = [
        ("a decoder failure", g2, {"outcome": "decoder_bug", "reason": "kernel: type mismatch"}, True),
        ("lost: group 1, no proof up to Nmax", g1, {"outcome": "no_proof_le_Nmax", "N": 10,
                                                     "per_N": [row(i, "unsat") for i in range(1, 11)]}, True),
        ("lost: group 1, a proof above 8c-1's N", g1, proved(4), True),
        ("lost: group 1, UNSAT at 8c-1's N, then a timeout", g1,
         {"outcome": "timeout", "per_N": [row(1, "unsat"), row(2, "unsat"), row(3, "unsat"), row(4, "timeout")]}, True),
        ("lost: group 1, the early exit at 8c-1's N", g1, {"outcome": "timeout",
                                                           "per_N": [row(3, "early_exit"), row(4, "timeout")]}, True),
        ("lost: group 1, a crash after passing 8c-1's N", g1, {"outcome": "crash", "cause": "oom", "last_N": 4}, True),
        ("lost: group 3, no proof up to Nmax", g3, {"outcome": "no_proof_le_Nmax", "N": 10, "per_N": []}, True),
        ("exactness: group 2, a proof without rules where milestone 7 was UNSAT", g2, proved(3), True),
        ("exactness: group 3, a proof without rules where milestone 7 was UNSAT", g3, proved(1), True),
        ("not in the expectations", None, proved(1), True),
        ("agree: group 1, proved at 8c-1's N", g1, proved(3), False),
        ("agree: group 1, proved below 8c-1's N", g1, proved(2), False),
        ("agree: group 1, a timeout before 8c-1's N", g1, {"outcome": "timeout", "per_N": [row(1, "unsat"), row(2, "timeout")]}, False),
        ("agree: group 1, a crash at 8c-1's N", g1, {"outcome": "crash", "cause": "oom", "last_N": 3}, False),
        ("agree: group 1 with the probe's rules, no proof (listed, not a stop)", g1p,
         {"outcome": "no_proof_le_Nmax", "N": 10, "per_N": []}, False),
        ("agree: group 2, a proof with a generated rule where milestone 7 was UNSAT", g2,
         proved(3, rules_used=["rw.Eq.symm@ground#0"]), False),
        ("agree: group 2, a proof with a propext path where milestone 7 was UNSAT", g2, proved(2, propext_used=1), False),
        ("agree: group 2, a proof without rules above milestone 7's UNSAT N", g2, proved(5), False),
        ("agree: group 3, proved at milestone 7's N without rules", g3, proved(2), False)]
    fails = 0
    for name, exp, r, want in cases:
        got = m9a3_stop(exp, r)
        ok = bool(got) == want
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {name}: {got or 'no stop'}")
    print(f"driver 9a-3 stop rules (M9_PLAN 4.4): {len(cases) - fails} passed, {fails} failed")
    return 1 if fails else 0


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


def machine():
    """The machine's specifications, for the output header (§10.5 decision 4)."""
    def sh(*cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
        except OSError:
            return None
    lscpu = dict(l.split(":", 1) for l in sh("lscpu").splitlines() if ":" in l)
    mi = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo") if l.split()[1].isdigit()}
    cores = int(lscpu.get("Core(s) per socket", "0").strip() or 0) * int(lscpu.get("Socket(s)", "1").strip() or 1)
    return {"cpu": lscpu.get("Model name", "").strip(), "physical_cores": cores,
            "threads": os.cpu_count(), "ram_mib": mi.get("MemTotal", 0) // 1024,
            "swap_mib": mi.get("SwapTotal", 0) // 1024, "kernel": os.uname().release,
            "os": sh("sh", "-c", ". /etc/os-release; echo $PRETTY_NAME"),
            "systemd": (sh("systemctl", "--version") or "").splitlines()[0:1],
            "vm_overcommit_memory": open("/proc/sys/vm/overcommit_memory").read().strip()}


def headroom_mb(slice_name, cap_mb):
    """MemAvailable minus what the run slice may still take: memory left for the rest of
    the machine even if the slice grows to its cap."""
    avail = next(int(l.split()[1]) for l in open("/proc/meminfo") if l.startswith("MemAvailable:")) // 1024
    try:
        cur = int(open(os.path.join(CG, slice_name, "memory.current")).read()) // (1024 * 1024)
    except (OSError, ValueError):
        cur = 0
    return avail - max(0, cap_mb - cur)


def drop_markers(path, key):
    if not os.path.exists(path):
        return
    with open(path) as f:
        keep = [l for l in f if l.strip() and json.loads(l).get("key") != key]
    with open(path, "w") as f:
        f.writelines(keep)


def after_shard(cmd, outdir):
    if not cmd:
        return
    r = subprocess.run(["sh", "-c", cmd, "after-shard", outdir], cwd=ROOT)
    if r.returncode != 0:
        print(f"after-shard hook failed with {r.returncode} (run continues)", flush=True)


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


def with_baselines(outdir, rec):
    """A crash record gets the goal's baselines if the shard wrote them before it died
    (baselines run before the N loop, EVAL_PLAN 10.5 decision 2)."""
    for b in load(os.path.join(outdir, "baselines.jsonl")):
        if b.get("key") == rec["key"]:
            rec.update({k: v for k, v in b.items() if k != "key"})
    return rec


def append(path, obj):
    with open(path, "a") as f:
        f.write(json.dumps(obj, sort_keys=True) + "\n")
        f.flush()


def run(specs_path, outdir, shard_size, cap_mb, watchdog, hook=None, min_free=MIN_FREE_MB):
    os.makedirs(outdir, exist_ok=True)
    results, started, warmup = (os.path.join(outdir, f) for f in ("results.jsonl", "started.jsonl", "warmup.jsonl"))
    specs = load(specs_path)
    commit, dirty = git_commit()
    hdr = {"specs": os.path.abspath(specs_path), "n_specs": len(specs), "toolchain": "4.36.0",
           "git_commit": commit, "git_dirty": dirty, "shard_size": shard_size, "cap_mb": cap_mb,
           "watchdog_s": watchdog,
           "nmax": "per spec (field nmax: the goal's N in eval/final/, EVAL_PLAN 10.9 decision 6)" if any("nmax" in s for s in specs) else 10,
           "solver_s": 20, "loop_s": 120,
           "baseline_heartbeats": 200000, "sbe_max_depth": 10,
           "seeds": {"r1b": SEED_R1B, "pilot_A": SEED_PILOT_A, "pilot_B": SEED_PILOT_B},
           "parallel_shards": PARALLEL_SHARDS, "machine": machine(), "min_free_mb": min_free,
           "baseline_order": "before the solve_by_sat N loop (10.5 decision 2)",
           "sbe_like": "H + local hypotheses, no default lemmas, symm/exfalso off (10.5 decision 3)"}
    hpath = os.path.join(outdir, "header.json")
    if not os.path.exists(hpath):
        json.dump(hdr, open(hpath, "w"), indent=1, sort_keys=True)
    fix_trailing(results)
    done = {r["key"] for r in load(results)}
    # resume: a marker without a result from an earlier driver is a crash of unknown cause
    for r in load(started):
        if r["key"] not in done:
            last = max((x.get("N", 0) for x in load(started) if x["key"] == r["key"]), default=0)
            append(results, with_baselines(outdir, {"key": r["key"], "outcome": "crash", "cause": "unknown",
                                                    "found": "on resume", "last_N": last or None}))
            done.add(r["key"])
            print(f"resume: {r['key']} started earlier with no result: crash(shard, unknown)", flush=True)
    pending = [s for s in specs if s["key"] not in done]
    ref_path = os.environ.get("SOLVE_BY_SAT_EVAL_COMPARE") or None
    reference = load_reference(ref_path) if ref_path else None
    # 9a-3 (M9_PLAN 4.4): the stop rules against eval/m9a3/expect.jsonl, checked on every new result (exit 10)
    m9a3_path = os.environ.get("SOLVE_BY_SAT_EVAL_M9A3") or None
    m9a3 = {e["key"]: e for e in load(m9a3_path)} if m9a3_path else None
    m9a3_seen = set()

    def m9a3_check():
        if m9a3 is None:
            return None
        for r in load(results):
            if r["key"] in m9a3_seen:
                continue
            m9a3_seen.add(r["key"])
            m = m9a3_stop(m9a3.get(r["key"]), r)
            if m:
                append(os.path.join(outdir, "driver.jsonl"), {"stop": "m9a3", "key": r["key"], "reason": m,
                                                              "time": time.strftime("%Y-%m-%d %H:%M:%S")})
                return (r["key"], m)
        return None
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
                cur, since, killed, lowmem = None, None, False, None
                m9stop = None
                while p.poll() is None:
                    time.sleep(0.5)
                    if m9stop is None and (m9stop := m9a3_check()):
                        os.killpg(p.pid, signal.SIGKILL)
                        p.wait()
                        break
                    st = load(started)
                    if len(st) > n_started0 and st[-1]["key"] != cur:
                        cur, since = st[-1]["key"], time.monotonic()
                    hr = headroom_mb(slice_name, cap_mb)
                    if hr < min_free and lowmem is None:
                        lowmem = hr
                        print(f"STOP: memory outside the run slice is {hr} MB (< {min_free}); killing the shard", flush=True)
                        os.killpg(p.pid, signal.SIGKILL)
                    if (cur and since and time.monotonic() - since > watchdog and not killed
                            and cur not in {r["key"] for r in load(results)}):
                        print(f"watchdog: {cur} over {watchdog} s, killing the shard", flush=True)
                        os.killpg(p.pid, signal.SIGKILL)
                        killed = True
                rc = p.returncode
                shutil.rmtree(tmpdir, ignore_errors=True)   # inputs left by a killed solver
                os.makedirs(tmpdir, exist_ok=True)
                fix_trailing(results)
                if m9stop or (m9stop := m9a3_check()):
                    for k in sorted({r["key"] for r in load(started)[n_started0:]} - {r["key"] for r in load(results)}):
                        drop_markers(started, k)   # killed by the stop, not crashed: rerun on resume
                    print(f"STOP: {m9stop[1]} on {m9stop[0]} (a 9a-3 stop rule, M9_PLAN 4.4)", flush=True)
                    return 10
                if lowmem is not None:
                    fix_trailing(results)
                    done = {r["key"] for r in load(results)}
                    unfinished = sorted({r["key"] for r in load(started)[n_started0:]} - done)
                    for k in unfinished:
                        drop_markers(started, k)
                    append(os.path.join(outdir, "driver.jsonl"),
                           {"stop": "low_memory", "headroom_mb": lowmem, "unfinished_rerun": unfinished,
                            "time": time.strftime("%Y-%m-%d %H:%M:%S")})
                    return 7
                if rc == 0:
                    continue
                if rc in (3, 4, 6, 9):
                    what = {3: "decoder bug or solver error", 4: "harness error",
                            6: "a 4.2 stop rule, EVAL_PLAN 10.9 decision 9",
                            9: "an exactness stop rule, M8_PLAN 4.4 and 4.6"}[rc]
                    print(f"STOP: shard exited with {rc} ({what}; see results.jsonl)", flush=True)
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
                phases = {}
                for r in load(started)[n_started0:]:
                    if "phase" in r:
                        phases[r["key"]] = r["phase"]
                exact_stop = None
                for k in lost:
                    el = round(time.monotonic() - since, 1) if (k == cur and since) else None
                    rec = {"key": k, "outcome": "crash", "cause": cause, "last_N": last_n.get(k),
                           "phase": phases.get(k), "elapsed_s": el}
                    # 8d (M8_PLAN 4.6): a crash after N passed every N below it; against the reference
                    # run (SOLVE_BY_SAT_EVAL_COMPARE), that is UNSAT at a reference proof's N if below
                    if reference is not None:
                        m = crash_exactness(reference.get(k), rec["last_N"])
                        if m:
                            rec["stop"] = "exactness (M8_PLAN 4.4): " + m
                            exact_stop = exact_stop or (k, rec["stop"])
                    append(results, with_baselines(outdir, rec))
                    print(f"crash(shard, {cause}) on {k}", flush=True)
                if exact_stop:
                    print(f"STOP: {exact_stop[1]} on {exact_stop[0]} (an exactness stop rule, M8_PLAN 4.6)", flush=True)
                    return 9
                if (m9stop := m9a3_check()):
                    print(f"STOP: {m9stop[1]} on {m9stop[0]} (a 9a-3 stop rule, M9_PLAN 4.4)", flush=True)
                    return 10
                if cause not in ("oom", "watchdog"):
                    n_same = sum(1 for r in load(results) if r.get("outcome") == "crash" and r.get("cause") == cause)
                    if n_same >= 2:
                        print(f"STOP: crash cause {cause!r} repeated ({n_same} times)", flush=True)
                        return 8
            n_done = len({r['key'] for r in load(results)})
            print(f"shard {i // shard_size}: done; {n_done} results; {time.monotonic() - t_start:.0f} s", flush=True)
            after_shard(hook, outdir)
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
    if a == ["exactness-selftest"]:
        return exactness_selftest()
    if a == ["m9a3-selftest"]:
        return m9a3_selftest()
    if a[:1] == ["run"]:
        opts = dict(zip(a[3::2], a[4::2]))
        return run(a[1], a[2], int(opts.get("--shard-size", SHARD_SIZE)),
                   int(opts.get("--cap-mb", CAP_MB)), int(opts.get("--watchdog", WATCHDOG_S)),
                   opts.get("--after-shard"), int(opts.get("--min-free-mb", MIN_FREE_MB)))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
