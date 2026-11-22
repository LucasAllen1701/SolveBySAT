#!/usr/bin/env python3
"""Milestone 7c, EVAL_PLAN §4.1 and §10.9 (4.1 decisions 1-3): the synthetic grid.

  python3 Test/eval_scaling.py [OUT]     (default eval/scaling_synthetic.jsonl)

Every cell (4 families x k in {0,4,8,16,32} x N in {5,8,12} x 5 configurations) is counted
with `countOnly` (`eval_scaling cell ... count`), each in its own process under the 2.5 GB
cap (`Test/capped.sh`). Nothing is solved. Then, for decision 1, a full encode of the same
cell is run under the cap, in ascending k for each (family, configuration, N); once one is
killed by the cap, larger k of that triple are not tried. The full encode must equal the
count in variables, clauses and every family's count; a difference stops the script (exit 3).

The first line of OUT is a header; every cell line also carries the commit, the encoder
options of its configuration and the limits. Resumable: cells already in OUT are skipped.
"""
import json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "eval", "scaling_synthetic.jsonl")
FAMS = ["S", "T1", "T2", "T3"]
KS = [0, 4, 8, 16, 32]
NS = [5, 8, 12]
CFGS = {  # EVAL_PLAN §4.1's five configurations, as EncodeOptions changes from the default
    "all": {}, "none": {"symmetry": False, "pairPruning": False, "candidatePruning": False,
                        "framePruning": False, "ladderAmo": False},
    "no_candidate": {"candidatePruning": False}, "no_pair": {"pairPruning": False},
    "no_static": {"staticTyping": False}}
CAP_MB = 2500
BIN = os.path.join(ROOT, ".lake/build/bin/eval_scaling")


def git(*a):
    return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def cell(fam, k, n, cfg, mode):
    t0 = time.monotonic()
    p = subprocess.run([os.path.join(ROOT, "Test/capped.sh"), BIN, "cell", fam, str(k), str(n), cfg, mode],
                       cwd=ROOT, capture_output=True, text=True, env={**os.environ, "CAP_MB": str(CAP_MB)})
    peak = None
    for l in p.stderr.splitlines():
        if l.startswith("[memrun]"):
            peak = int(l.split("peak ")[1].split(" MB")[0])
    rec = None
    for l in p.stdout.splitlines():
        if l.startswith("{"):
            rec = json.loads(l)
    status = "ok" if (p.returncode == 0 and rec) else ("memout" if p.returncode in (137, -9) or "Killed" in p.stderr else f"error {p.returncode}")
    return rec, status, peak, time.monotonic() - t0, p.stderr[-300:]


def main():
    commit = git("rev-parse", "HEAD")[:7]
    dirty = bool(git("status", "--porcelain", "--untracked-files=no"))
    limits = {"cap_mb": CAP_MB, "solved": False}
    done = {}
    if os.path.exists(OUT):
        for l in open(OUT):
            r = json.loads(l)
            if "header" not in r:
                done[(r["family"], r["k"], r["N"], r["config"])] = r
    else:
        hdr = {"header": True, "plan": "EVAL_PLAN 4.1, 10.9 (4.1 decisions 1-3)", "git_commit": commit, "git_dirty": dirty,
               "families": FAMS, "k": KS, "N": NS, "configs": CFGS, "limits": limits,
               "goal": "forall x y z w : Nat, x <= y -> y <= z -> z <= w -> x <= w (L1), H = Nat.le_trans + first k Synth.<FAM>.mono_i",
               "machine": {"cpu": next((l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo") if l.startswith("model name")), "?"),
                           "kernel": os.uname().release}}
        with open(OUT, "w") as f:
            f.write(json.dumps(hdr) + "\n")
    with open(OUT, "a") as f:
        # 1. counts
        for fam in FAMS:
            for cfg in CFGS:
                for n in NS:
                    for k in KS:
                        if (fam, k, n, cfg) in done:
                            continue
                        rec, status, peak, wall, err = cell(fam, k, n, cfg, "count")
                        r = {"family": fam, "k": k, "N": n, "config": cfg, "status": status, "peak_mb": peak,
                             "wall_s": round(wall, 2), "commit": commit, "options": CFGS[cfg], "limits": limits}
                        if rec:
                            r.update({x: rec[x] for x in ("vars", "clauses", "families", "encode_ms", "H_size", "H_accepted",
                                                          "H_rejected", "forest_clauses", "forest_goals", "typing", "pairs",
                                                          "stored_clauses")})
                        else:
                            r["error"] = err
                        f.write(json.dumps(r, ensure_ascii=False) + "\n"); f.flush()
                        done[(fam, k, n, cfg)] = r
                        print(f"count {fam} k={k} N={n} {cfg}: {status} {r.get('clauses')} clauses, {peak} MB, {wall:.1f} s", flush=True)
    # 2. full-encode check (decision 1), written to a side file and merged into OUT
    chk_path = OUT.replace(".jsonl", ".fullcheck.jsonl")
    chk = {}
    if os.path.exists(chk_path):
        for l in open(chk_path):
            r = json.loads(l); chk[(r["family"], r["k"], r["N"], r["config"])] = r
    bad = 0
    with open(chk_path, "a") as f:
        for fam in FAMS:
            for cfg in CFGS:
                for n in NS:
                    skip = False
                    for k in KS:
                        key = (fam, k, n, cfg)
                        if key in chk:
                            skip = skip or chk[key]["full"] in ("memout", "skipped")
                            continue
                        c = done[key]
                        if skip:
                            r = {"family": fam, "k": k, "N": n, "config": cfg, "full": "skipped"}
                        else:
                            rec, status, peak, wall, err = cell(fam, k, n, cfg, "full")
                            if status != "ok":
                                r = {"family": fam, "k": k, "N": n, "config": cfg, "full": status, "peak_mb": peak}
                                skip = True
                            else:
                                eq = (rec["vars"] == c.get("vars") and rec["clauses"] == c.get("clauses")
                                      and rec["families"] == c.get("families") and rec["stored_clauses"] == rec["clauses"]
                                      and list(rec["families"]) == list(c.get("families") or {}))
                                r = {"family": fam, "k": k, "N": n, "config": cfg, "full": "equal" if eq else "DIFFER",
                                     "peak_mb": peak, "count_peak_mb": c.get("peak_mb"), "wall_s": round(wall, 2)}
                                if not eq:
                                    bad += 1
                                    r["full_rec"] = rec
                        f.write(json.dumps(r) + "\n"); f.flush()
                        chk[key] = r
                        print(f"full {fam} k={k} N={n} {cfg}: {r['full']} {r.get('peak_mb')} MB", flush=True)
                        if bad:
                            print("STOP: a full encode differs from countOnly"); sys.exit(3)
    print(f"done; full-encode check: {sum(1 for r in chk.values() if r['full'] == 'equal')} equal, "
          f"{sum(1 for r in chk.values() if r['full'] == 'memout')} memout, {sum(1 for r in chk.values() if r['full'] == 'skipped')} skipped, "
          f"{sum(1 for r in chk.values() if r['full'] == 'DIFFER')} differ")


if __name__ == "__main__":
    main()
