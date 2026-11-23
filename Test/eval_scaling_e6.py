#!/usr/bin/env python3
"""7d-2, E6 (EVAL_PLAN §10.10 decision 7, exploratory): the synthetic grid's 60 cells
(4 families x k in {0,4,8,16,32} x N in {5,8,12}) with static typing and candidate pruning
both off and every other refinement on (`eval_scaling` config `no_typing`), counted with
`countOnly` only, each in its own process under the 2.5 GB cap, as in Test/eval_scaling.py.

  python3 Test/eval_scaling_e6.py [OUT]     (default eval/scaling_synthetic_e6.jsonl)

The header has the same fields as eval/scaling_synthetic.jsonl. The pre-registered grid is
not touched. Resumable: cells already in OUT are skipped.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eval_scaling as G

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(G.ROOT, "eval", "scaling_synthetic_e6.jsonl")
CFG = "no_typing"
OPTS = {"staticTyping": False, "candidatePruning": False}


def main():
    commit = G.git("rev-parse", "HEAD")[:7]
    dirty = bool(G.git("status", "--porcelain", "--untracked-files=no"))
    limits = {"cap_mb": G.CAP_MB, "solved": False}
    done = set()
    if os.path.exists(OUT):
        for l in open(OUT):
            r = json.loads(l)
            if "header" not in r:
                done.add((r["family"], r["k"], r["N"], r["config"]))
    else:
        hdr = {"header": True, "plan": "EVAL_PLAN 10.10 decision 7 (E6, exploratory)", "git_commit": commit,
               "git_dirty": dirty, "families": G.FAMS, "k": G.KS, "N": G.NS, "configs": {CFG: OPTS}, "limits": limits,
               "goal": "forall x y z w : Nat, x <= y -> y <= z -> z <= w -> x <= w (L1), H = Nat.le_trans + first k Synth.<FAM>.mono_i",
               "machine": {"cpu": next((l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo") if l.startswith("model name")), "?"),
                           "kernel": os.uname().release}}
        with open(OUT, "w") as f:
            f.write(json.dumps(hdr) + "\n")
    with open(OUT, "a") as f:
        for fam in G.FAMS:
            for n in G.NS:
                for k in G.KS:
                    if (fam, k, n, CFG) in done:
                        continue
                    rec, status, peak, wall, err = G.cell(fam, k, n, CFG, "count")
                    r = {"family": fam, "k": k, "N": n, "config": CFG, "status": status, "peak_mb": peak,
                         "wall_s": round(wall, 2), "commit": commit, "options": OPTS, "limits": limits}
                    if rec:
                        r.update({x: rec[x] for x in ("vars", "clauses", "families", "encode_ms", "H_size", "H_accepted",
                                                      "H_rejected", "forest_clauses", "forest_goals", "typing", "pairs",
                                                      "stored_clauses")})
                    else:
                        r["error"] = err
                    f.write(json.dumps(r, ensure_ascii=False) + "\n"); f.flush()
                    print(f"count {fam} k={k} N={n} {CFG}: {status} {r.get('clauses')} clauses, {peak} MB, {wall:.1f} s", flush=True)


if __name__ == "__main__":
    main()
