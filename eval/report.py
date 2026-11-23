#!/usr/bin/env python3
"""Milestone 7d: generate EVAL.md from the data files alone (EVAL_PLAN §6, §10.6–§10.10).

  python3 eval/report.py            write EVAL.md (repo root)
  python3 eval/report.py samples    write the seeded review samples to eval/reviews/

Inputs, all under eval/:
  final/results.jsonl                    the merged results (eval/merge.py, NOTES.md "10.7: merge
                                         rule"): every table and review population reads these
  full/results.jsonl, full/header.json   the full 7b run, "before" the type-template fix (used
                                         only in the "Effect of the type-template fix" section)
  rerun/header.json, specs_rerun.jsonl   the 10.7 rerun and its rerun set
  specs_full.jsonl                       the pre-registered specs
  corpus_A.jsonl, corpus_B.jsonl         the corpus (7a, with the §10.2/§10.4 H sets)
  corpus_numerals.jsonl                  rule 4 of §3.3, as fixed in NOTES.md (7d-1)
  corpus_hcompile.jsonl                  compiler acceptance of the goal and of each H
                                         constant, recomputed (checked here against the
                                         results that record it)
  scaling_synthetic*.jsonl               7c, EVAL_PLAN §4.1 (R5)
  specs_scaling.jsonl, scaling_full/     7c, EVAL_PLAN §4.2 (R6): results, countOnly sizes, header
  scaling_goals.jsonl, scaling_pool.jsonl  7c set-up: each goal's S, and the pool's clause heads (R6, 7d-2)
  scaling_synthetic_e6.jsonl             7d-2 E6: both typing filters off (§10.10 decision 7)
  m8_families.json, m8_obstacles.jsonl   7d-2 E5: the fixed family table and the constant facts
                                         (Test/M8Facts.lean) (§10.10 decision 6)
  reviews/*.jsonl                        the hand reviews (7d-1 step 3, redrawn after the merge).
                                         `*.evidence.jsonl` files are review evidence, not reviews.
                                         reviews/before_fix/ holds the reviews of the samples drawn
                                         before the fix; nothing in it is read or counted here.
Only the standard library is used; there are no charts (matplotlib is not installed).
"""
import collections, json, math, os, random, re, statistics, sys

E = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(E)

# seeds of the 7d-1 review samples (pre-registered in NOTES.md, 7d-1)
SEED_UNEXPLAINED, N_UNEXPLAINED = 70101, 50
SEED_R7, N_R7 = 70102, 100
SEED_E1, N_E1 = 70103, 50

BUCKETS = [(0, 5, "0–5"), (6, 10, "6–10"), (11, 20, "11–20"), (21, 10**9, ">20")]
REASONS = ["1 goal rejected", "2 H constant rejected", "3 elimination constant",
           "4 numerals", "5 timeout / memory", "6 unexplained"]


def load(p):
    out = []
    if os.path.exists(p):
        for l in open(p):
            l = l.strip()
            if l:
                out.append(json.loads(l))
    return out


def bucket(n):
    return next(b for lo, hi, b in BUCKETS if lo <= n <= hi)


def fmt(n):
    return f"{n:,}" if isinstance(n, int) else (f"{n:,.1f}" if isinstance(n, float) else str(n))


def pct(a, b):
    return f"{100 * a / b:.1f}%" if b else "–"


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "| " + " | ".join("---" for _ in head) + " |"]
    for r in rows:
        out.append("| " + " | ".join(fmt(x) for x in r) + " |")
    return "\n".join(out)


def quantile(xs, q):
    xs = sorted(xs)
    if not xs:
        return None
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def med(xs):
    return statistics.median(xs) if xs else None


def msg_class(m):
    m = m or ""
    if "is applied to arguments" in m:
        return "variable applied to arguments (higher order)"
    if "as its head symbol" in m:
        return "head, target or result is a variable"
    if "mentions a proof variable" in m:
        return "binder type mentions a proof"
    if "type former" in m:
        return "type former"
    if "witness would be a proof" in m:
        return "witness would be a proof"
    return "other: " + re.sub(r"\s+", " ", m.replace("solve_by_sat: ", ""))[:60]


def short(s, n=110):
    s = re.sub(r"\s+", " ", str(s or ""))
    return s if len(s) <= n else s[: n - 1] + "…"


# ---------------------------------------------------------------- data


class Data:
    def __init__(self):
        self.specs = {s["key"]: s for s in load(os.path.join(E, "specs_full.jsonl"))}
        self.final_lines = load(os.path.join(E, "final", "results.jsonl"))
        self.res = {r["key"]: r for r in self.final_lines}
        self.before = {r["key"]: r for r in load(os.path.join(E, "full", "results.jsonl"))}
        self.rerun_set = {s["key"]: s["rerun_set"] for s in load(os.path.join(E, "specs_rerun.jsonl"))}
        self.rerun = {r["key"]: r for r in load(os.path.join(E, "rerun", "results.jsonl"))}
        self.corpus = {}
        for t in "AB":
            for r in load(os.path.join(E, f"corpus_{t}.jsonl")):
                if "header" not in r:
                    self.corpus[r["id"]] = r
        self.num = {r["id"]: r for r in load(os.path.join(E, "corpus_numerals.jsonl"))}
        self.hc = {r["id"]: r for r in load(os.path.join(E, "corpus_hcompile.jsonl"))}
        self.reviews = {}
        rd = os.path.join(E, "reviews")
        if os.path.isdir(rd):
            for f in sorted(os.listdir(rd)):
                # only top-level review files; reviews/before_fix/ (a directory) is never read
                if f.endswith(".jsonl") and not f.endswith(".evidence.jsonl") and os.path.isfile(os.path.join(rd, f)):
                    self.reviews[f[:-6]] = [x for x in load(os.path.join(rd, f)) if not x.get("superseded")]
        # 7c, EVAL_PLAN §4.1 (R5): the synthetic grid and its full-encode check
        self.synth = [r for r in load(os.path.join(E, "scaling_synthetic.jsonl")) if "header" not in r]
        self.synth_hdr = next((r for r in load(os.path.join(E, "scaling_synthetic.jsonl")) if "header" in r), None)
        self.synth_full = load(os.path.join(E, "scaling_synthetic.fullcheck.jsonl"))
        # 7c, EVAL_PLAN §4.2 (R6): the full run with real distractors and its countOnly sizes
        self.sc_specs = {s["key"]: s for s in load(os.path.join(E, "specs_scaling.jsonl")) if "key" in s}
        self.sc_res = {r["key"]: r for r in load(os.path.join(E, "scaling_full", "results.jsonl"))}
        self.sc_size = {r["key"]: r for r in load(os.path.join(E, "scaling_full", "sizes.jsonl"))}
        self.sc_goals = {g["key"]: g for g in load(os.path.join(E, "scaling_goals.jsonl"))}
        self.pool = [r for r in load(os.path.join(E, "scaling_pool.jsonl")) if "name" in r]
        # 7d-2: E6 (§10.10 decision 7) and E5's fixed family table and constant facts (decision 6)
        self.e6 = [r for r in load(os.path.join(E, "scaling_synthetic_e6.jsonl")) if "header" not in r]
        fp = os.path.join(E, "m8_families.json")
        self.m8 = json.load(open(fp)) if os.path.exists(fp) else None
        self.m8_facts = {r["name"]: r for r in load(os.path.join(E, "m8_obstacles.jsonl"))}
        hp = os.path.join(E, "scaling_full", "header.json")
        self.sc_hdr = json.load(open(hp)) if os.path.exists(hp) else None
        self.checks = []
        self._acceptance()

    def keys(self, run, tier=None):
        return [k for k, s in self.specs.items() if s["run"] == run and (tier is None or s["tier"] == tier)]

    def _acceptance(self):
        """Per key: (goal accepted, rejected H constants with messages), from the result when it
        records them, else from the recomputed corpus_hcompile; and a consistency check."""
        self.acc = {}
        agree = disagree = 0
        bad = []
        for k, s in self.specs.items():
            r = self.res[k]
            h = self.hc.get(s["id"], {}).get("r1b" if s["run"] == "r1b" else "main")
            rec = None
            if r["outcome"] == "goal_rejected":
                rec = (False, [])
            elif "H_rejected" in r:
                rec = (True, [tuple(x) for x in r["H_rejected"]])
            comp = None
            if h is not None:
                comp = (False, []) if "goal_rejected" in h else (True, [tuple(x) for x in h["rejected"]])
            if rec is not None and comp is not None:
                if rec[0] == comp[0] and sorted(c for c, _ in rec[1]) == sorted(c for c, _ in comp[1]):
                    agree += 1
                else:
                    disagree += 1
                    bad.append(k)
            self.acc[k] = rec if rec is not None else comp
        self.checks.append(("compiler acceptance recomputed (corpus_hcompile) against the results that record it",
                            f"{agree:,} agree, {disagree:,} disagree" + (f" (e.g. {', '.join(bad[:5])})" if bad else "")))
        missing = [k for k in self.specs if self.acc[k] is None]
        self.checks.append(("goals without acceptance data", f"{len(missing):,}"))

    # ---- classification (§3.3)

    def reason(self, k, with4=True):
        r = self.res[k]
        if r["outcome"] == "proved":
            return None
        s = self.specs[k]
        c = self.corpus[s["id"]]
        acc = self.acc[k]
        if r["outcome"] == "goal_rejected" or (acc and not acc[0]):
            return REASONS[0]
        if acc and acc[1]:
            return REASONS[1]
        if c.get("uses_elim"):
            return REASONS[2]
        if with4 and self.num.get(s["id"], {}).get("rule4"):
            return REASONS[3]
        if r["outcome"] in ("timeout", "crash", "memout"):
            return REASONS[4]
        if r["outcome"] == "no_proof_le_Nmax":
            return REASONS[5]
        return "other: " + r["outcome"]

    def raw(self, k, res=None):
        r = (res or self.res)[k]
        o = r["outcome"]
        return {"crash": "memory crash", "no_proof_le_Nmax": "no proof ≤ 10", "goal_rejected": "goal rejected",
                "timeout": "solver timeout", "proved": "proved"}.get(o, o)

    def proved(self, k):
        return self.res[k]["outcome"] == "proved"

    def sbe(self, k, which="sbe_like"):
        b = self.res[k].get("baselines") or {}
        return (b.get(which) or {}).get("outcome")

    def lib(self, k):
        b = self.res[k].get("baselines") or {}
        return (b.get("library_search") or {}).get("exact")

    def oracle_in_class(self, k):
        s = self.specs[k]
        c = self.corpus[s["id"]]
        acc = self.acc[k]
        return (s["tier"] == "B" and acc is not None and acc[0] and not acc[1]
                and not c.get("uses_elim") and c.get("node_est", 99) <= 10)


# ---------------------------------------------------------------- samples


def sample(keys, n, seed):
    keys = sorted(keys)
    return keys if len(keys) <= n else sorted(random.Random(seed).sample(keys, n))


def read_sample(path):
    """The keys of a written sample file (first line is a comment), or None if it does not exist."""
    if not os.path.exists(path):
        return None
    return [l.strip() for l in open(path) if l.strip() and not l.startswith("#")]


def sample_comparison(d):
    """10.8 decision 2: the redrawn samples against those drawn before the fix
    (eval/reviews/before_fix/*.sample.txt). Rows: review, population, sample, kept from before,
    kept with a changed forest, new, and changed-forest goals in the sample."""
    rows = []
    for name, (pop, smp, seed) in review_sets(d).items():
        old = read_sample(os.path.join(E, "reviews", "before_fix", f"{name}.sample.txt")) or []
        kept = [k for k in smp if k in set(old)]
        ch = [k for k in smp if d.rerun_set.get(k) == "changed"]
        rows.append((name, seed, len(pop), len(smp), len(kept), sum(1 for k in kept if d.rerun_set.get(k) == "changed"),
                     len(smp) - len(kept), len(ch), len(old)))
    return rows


def review_sets(d):
    main = d.keys("main")
    unexplained = [k for k in main if d.reason(k) == REASONS[5]]
    r7 = [k for k in d.keys("main", "B") if d.oracle_in_class(k) and d.res[k]["outcome"] == "no_proof_le_Nmax"]
    e1 = [k for k in main if d.sbe(k) == "closed" and d.res[k]["outcome"] == "no_proof_le_Nmax"]
    sbs_only = [k for k in main if d.proved(k) and d.sbe(k) != "closed"]
    return {
        "r2_unexplained": (unexplained, sample(unexplained, N_UNEXPLAINED, SEED_UNEXPLAINED), SEED_UNEXPLAINED),
        "r7_soft_completeness": (r7, sample(r7, N_R7, SEED_R7), SEED_R7),
        "e1_sbe_wins": (e1, sample(e1, N_E1, SEED_E1), SEED_E1),
        "sbs_only": (sbs_only, sorted(sbs_only), None),
    }


# ---------------------------------------------------------------- sections


RAW_COLS = ["proved", "no proof ≤ 10", "memory crash", "goal rejected", "solver timeout"]
RUNS = [("main", "A", "Tier A"), ("main", "B", "Tier B"), ("r1b", "B", "R1b (Tier B, H_full)")]
LIMIT_RAW = ("memory crash", "solver timeout")


def effect(d):
    """EVAL_PLAN §10.7 decision 7, §10.8 decision 3, NOTES.md "10.7: merge rule"."""
    out = ["## Effect of the type-template fix (EVAL_PLAN §10.7, §10.8)", "",
           "7d-1 found a completeness bug in the compiler: type templates were built from the raw inferred "
           "type, without the preprocessing of SPEC 4.1 (§10.7). After the fix, every goal whose compiled "
           "forest changed was rerun (SAT phase only), and its `solve_by_sat` result replaces the original "
           "(`eval/final/`, by the merge rule pre-registered in NOTES.md). *Before* is `eval/full/` as "
           "recorded; *after* is `eval/final/`. Every other table in this report reads *after*.", ""]
    ch = sorted(k for k, v in d.rerun_set.items() if v == "changed")
    spot = sorted(k for k, v in d.rerun_set.items() if v == "spot")
    rows = []
    for run, t, name in RUNS:
        ks = d.keys(run, t)
        for lab, res in (("before", d.before), ("after", d.res)):
            c = collections.Counter(d.raw(k, res) for k in ks)
            rows.append([name, lab, len(ks)] + [c.get(o, 0) for o in RAW_COLS])
    out += ["Raw `solve_by_sat` outcomes, before and after:", "",
            table(["run", "", "goals"] + RAW_COLS, rows), ""]
    rows = []
    for run, t, name in RUNS:
        for lab, res in (("before", d.before), ("after", d.res)):
            c = collections.Counter(res[k]["N"] for k in d.keys(run, t) if res[k]["outcome"] == "proved")
            rows.append([name, lab, sum(c.values())] + [c.get(n, 0) for n in range(1, 11)])
    out += ["Smallest N at which `solve_by_sat` found a proof, before and after:", "",
            table(["run", "", "proved"] + [f"N = {n}" for n in range(1, 11)], rows), ""]
    per = collections.Counter(d.specs[k]["run"] + " " + d.specs[k]["tier"] for k in ch)
    x = collections.Counter((d.raw(k, d.before), d.raw(k)) for k in ch)
    out += [f"The {len(ch):,} goals whose forest changed (main A {per.get('main A', 0):,}, main B "
            f"{per.get('main B', 0):,}, R1b {per.get('r1b B', 0):,}): original outcome (rows) against final "
            "outcome (columns):", "",
            table(["before \\ after"] + RAW_COLS + ["total"],
                  [[a] + [x.get((a, b), 0) for b in RAW_COLS] + [sum(x.get((a, b), 0) for b in RAW_COLS)]
                   for a in RAW_COLS if any(x.get((a, b)) for b in RAW_COLS)]), ""]
    new = [k for k in ch if d.proved(k) and d.before[k]["outcome"] != "proved"]
    lost = [k for k in ch if d.before[k]["outcome"] == "proved" and not d.proved(k)]
    sameN = [k for k in ch if d.before[k]["outcome"] == "proved" and d.proved(k) and d.before[k]["N"] == d.res[k]["N"]]
    rows = [[f"`{k}`", d.res[k]["N"], d.raw(k, d.before), f"`{short(d.res[k].get('skeleton'), 120)}`"] for k in new]
    out += [f"New proofs: {len(new)}. Proofs lost: {len(lost)}. Goals proved before and after: "
            f"{len(sameN) + sum(1 for k in ch if d.before[k]['outcome'] == 'proved' and d.proved(k) and k not in sameN)}, "
            f"{len(sameN)} of them at the same N.", "",
            table(["goal", "N", "outcome before", "proof (skeleton)"], rows), ""]
    both = [k for k in ch if d.raw(k, d.before) == "memory crash" and d.raw(k) == "memory crash"]
    tolim = [k for k in ch if d.raw(k, d.before) == "no proof ≤ 10" and d.raw(k) in LIMIT_RAW]
    out += ["**Caveat (§10.8 decision 3).** "
            f"{len(both):,} of the {len(ch):,} changed goals crashed on memory both before and after the fix, so "
            "the fix's effect on them is not measured: a goal that crashed both times may or may not have a proof "
            "within N ≤ 10 that the bug excluded. The fix can also change a CNF's size, so a result can move "
            f"towards a resource limit: {len(tolim)} changed goal{'s' if len(tolim) != 1 else ''} went from no proof "
            "≤ 10 to a resource limit"
            + (": " + "; ".join(f"`{k}` ({d.raw(k)}{', last N ' + str(d.res[k].get('last_N')) if d.res[k].get('last_N') else ''})" for k in tolim) if tolim else "")
            + ".", ""]
    sx = collections.Counter((d.raw(k, d.before), d.raw(k, {k: d.rerun[k]})) for k in spot if k in d.rerun)
    out += [f"**Spot check (§10.7 decision 5).** {len(spot)} goals whose forest did not change were also rerun; "
            "their original line stands. Original outcome → rerun outcome: "
            + "; ".join(f"{a} → {b} {v}" for (a, b), v in sorted(sx.items(), key=lambda z: (-z[1], z[0]))) + ". "
            f"Proved goals keep their N in {sum(1 for k in spot if k in d.rerun and d.before[k]['outcome'] == 'proved' and d.rerun[k].get('N') == d.before[k].get('N'))} "
            f"of {sum(1 for k in spot if d.before[k]['outcome'] == 'proved')}. Every difference has a resource limit on "
            "one of the runs, which the check allows (`eval/final/merge_report.txt`)."]
    return out


def r1(d):
    ncr = sum(1 for k in d.specs if d.res[k]["outcome"] == "crash" and "H_rejected" not in d.res[k])
    out = ["## R1 Funnel", "",
           "Main run (`H_main`). *Goal accepted*: the compiler accepts the goal. *H fully accepted*: "
           f"it also accepts every `H_main` constant on its own. For the {ncr:,} memory crashes (all runs), whose "
           "result lines do not record acceptance, it is taken from `corpus_hcompile` (see Data checks).", ""]
    rows = []
    for t in "AB":
        ks = d.keys("main", t)
        ga = [k for k in ks if d.acc[k][0]]
        hf = [k for k in ga if not d.acc[k][1]]
        pr = [k for k in ks if d.proved(k)]
        prh = [k for k in hf if d.proved(k)]
        rows.append([f"Tier {t}", len(ks), f"{len(ga):,} ({pct(len(ga), len(ks))})",
                     f"{len(hf):,} ({pct(len(hf), len(ks))})", f"{len(pr):,} ({pct(len(pr), len(ks))})",
                     f"{len(prh):,} of {len(hf):,} ({pct(len(prh), len(hf))})"])
    out.append(table(["tier", "goals", "goal accepted", "H fully accepted", "proved at N ≤ 10",
                      "proved, among H fully accepted"], rows))
    out += ["", "Raw `solve_by_sat` outcomes:", ""]
    rows = []
    for run, t, name in [("main", "A", "Tier A"), ("main", "B", "Tier B"), ("r1b", "B", "R1b (Tier B, H_full)")]:
        c = collections.Counter(d.raw(k) for k in d.keys(run, t))
        rows.append([name, sum(c.values())] + [c.get(o, 0) for o in
                    ["proved", "no proof ≤ 10", "memory crash", "goal rejected", "solver timeout"]])
    out.append(table(["run", "goals", "proved", "no proof ≤ 10", "memory crash", "goal rejected", "solver timeout"], rows))
    return out


def r1b(d):
    out = ["## R1b H_full against H_main (300 Tier B goals)", "",
           "The same 300 goals (seed 70005) run with `H_full` (R1b) and with `H_main` (main run).", ""]
    ids = [d.specs[k]["id"] for k in d.keys("r1b")]
    rows = []
    for run in ("main", "r1b"):
        ks = [f"{run}:{i}" for i in ids]
        c = collections.Counter(d.raw(k) for k in ks)
        hs = [len(d.specs[k]["H"]) for k in ks]
        cl = [d.res[k]["clauses"] for k in ks if "clauses" in d.res[k]]
        Ns = sorted(collections.Counter(d.res[k]["N"] for k in ks if d.proved(k)).items())
        rows.append(["H_main" if run == "main" else "H_full", f"{med(hs):g} / {quantile(hs, .9)}",
                     c.get("proved", 0), c.get("no proof ≤ 10", 0), c.get("memory crash", 0),
                     c.get("goal rejected", 0), c.get("solver timeout", 0),
                     f"{med(cl):,.0f}" if cl else "–", " ".join(f"{n}:{v}" for n, v in Ns)])
    out.append(table(["H", "\\|H\\| median / p90", "proved", "no proof ≤ 10", "memory crash", "goal rejected",
                      "solver timeout", "median clauses at final N", "proved at N (N:count)"], rows))
    out += ["", "Outcome with `H_main` (rows) against outcome with `H_full` (columns), same goal:", ""]
    cols = ["proved", "no proof ≤ 10", "memory crash", "goal rejected", "solver timeout"]
    x = collections.Counter((d.raw("main:" + i), d.raw("r1b:" + i)) for i in ids)
    out.append(table(["H_main \\ H_full"] + cols, [[a] + [x.get((a, b), 0) for b in cols] for a in cols]))
    both = [i for i in ids if d.proved("main:" + i) and d.proved("r1b:" + i)]
    diffN = [i for i in both if d.res["main:" + i]["N"] != d.res["r1b:" + i]["N"]]
    out += ["", f"Proved with both: {len(both)}; with a different N: {len(diffN)}."]
    return out


def r2(d):
    out = ["## R2 Failure reasons", "",
           "Each goal of the main run that is not proved gets one primary reason (§3.3), by the rules in "
           "order. Rule 4 is the exact version fixed in NOTES.md (7d-1) before this table was computed; "
           "the table is given with and without it.", ""]
    rows = []
    cnt = {}
    for t in "AB":
        for w in (True, False):
            cnt[(t, w)] = collections.Counter(d.reason(k, w) for k in d.keys("main", t) if not d.proved(k))
    for rsn in REASONS:
        rows.append([rsn] + [cnt[(t, w)].get(rsn, 0) for t in "AB" for w in (True, False)])
    rows.append(["total not proved"] + [sum(cnt[(t, w)].values()) for t in "AB" for w in (True, False)])
    out.append(table(["reason", "Tier A, with rule 4", "Tier A, without", "Tier B, with rule 4", "Tier B, without"], rows))
    out += ["", "Two examples per reason (with rule 4; the first two goal ids in order):", ""]
    rows = []
    for rsn in REASONS:
        ks = sorted(k for k in d.keys("main") if d.reason(k) == rsn)[:2]
        for k in ks:
            s = d.specs[k]
            c = d.corpus[s["id"]]
            r = d.res[k]
            if rsn == REASONS[0]:
                det = r.get("reason") or "goal rejected (recomputed)"
            elif rsn == REASONS[1]:
                c0, m0 = d.acc[k][1][0]
                det = f"`{c0}`: {m0}"
            elif rsn == REASONS[2]:
                det = "uses " + ", ".join(f"`{e}`" for e in c["elim"][:3])
            elif rsn == REASONS[3]:
                m = d.num[s["id"]]["first_numeral_mismatch"]
                det = f"expected `{short(m['at_expected'], 50)}`, inferred `{short(m['at_inferred'], 50)}`"
            elif rsn == REASONS[4]:
                det = d.raw(k) + (f" at N = {r.get('last_N') or r.get('N')}")
            else:
                det = f"no proof ≤ 10, \\|H_main\\| {len(s['H'])}"
            rows.append([rsn, f"`{s['id']}`", short(det, 120)])
    out.append(table(["reason", "goal", "detail"], rows))
    out += ["", "Rule 1 (goal rejected) and rule 2 (an `H_main` constant rejected) by the compiler's reason "
            "(rule 2: the reason for each rejected constant, counted once per goal and reason):", ""]
    rows = []
    for t in "AB":
        c1 = collections.Counter(msg_class(d.res[k].get("reason") or (d.hc.get(d.specs[k]["id"], {}).get("main", {}).get("goal_rejected")))
                                 for k in d.keys("main", t) if d.reason(k) == REASONS[0])
        c2 = collections.Counter()
        for k in d.keys("main", t):
            if d.reason(k) == REASONS[1]:
                for cl in {msg_class(m) for _, m in d.acc[k][1]}:
                    c2[cl] += 1
        for cl in sorted(set(c1) | set(c2), key=lambda x: (-(c1[x] + c2[x]), x)):
            rows.append([f"Tier {t}", cl, c1.get(cl, 0), c2.get(cl, 0)])
    out.append(table(["tier", "compiler's reason", "rule 1 goals", "rule 2 goals"], rows))
    out += ["", "Raw outcome (rows) against primary reason (columns), with rule 4. A memory crash on a goal "
            "that also uses an elimination constant is classified as elimination; this table keeps the "
            "crash visible.", ""]
    for t in "AB":
        x = collections.Counter((d.raw(k), d.reason(k)) for k in d.keys("main", t) if not d.proved(k))
        raws = ["no proof ≤ 10", "memory crash", "solver timeout", "goal rejected"]
        out += [f"Tier {t}:", "",
                table(["raw outcome"] + [r.split(" ", 1)[1] for r in REASONS] + ["total"],
                      [[a] + [x.get((a, b), 0) for b in REASONS] + [sum(x.get((a, b), 0) for b in REASONS)]
                       for a in raws]), ""]
    out += r2_breakdown(d)
    rd = d.reviews.get("r2_unexplained")
    if rd:
        out += review_summary(d, "r2_unexplained", rd, "Hand review of unexplained goals (§3.3)")
    return out


R2_REASON_NAMES = {"variable applied to arguments (higher order)": "clause variable applied to arguments",
                   "head, target or result is a variable": "clause variable as head symbol"}


def r2_goals(d, t):
    """Main-run goals of tier t with primary reason 2: goal accepted, not proved, some H_main constant rejected."""
    return [k for k in d.keys("main", t) if d.reason(k) == REASONS[1]]


def r2_stats(d, t):
    ks = r2_goals(d, t)
    rc, cc, one = collections.Counter(), collections.Counter(), collections.Counter()
    cls = collections.defaultdict(collections.Counter)
    for k in ks:
        rej = d.acc[k][1]
        for c in {R2_REASON_NAMES.get(msg_class(m), msg_class(m)) for _, m in rej}:
            rc[c] += 1
        cs = {c for c, _ in rej}
        for c, m in rej:
            cls[c][R2_REASON_NAMES.get(msg_class(m), msg_class(m))] += 1
        for c in cs:
            cc[c] += 1
        if len(cs) == 1:
            one[next(iter(cs))] += 1
    return ks, rc, cc, one, cls


def r2_breakdown(d):
    """§10.10 decision 4: reason 2 by rejection reason, by constant, and by single blocking constant."""
    out = ["### R2: what blocks reason 2 (EVAL_PLAN §7, §10.10 decision 4)", "",
           "Reason 2 goals: accepted by the compiler, not proved, and at least one `H_main` constant rejected. "
           "A goal counts once for each rejection reason, and once for each constant, that occurs among its rejected "
           "constants, so columns do not sum to the number of goals.", ""]
    st = {t: r2_stats(d, t) for t in "AB"}
    out.append(f"Goals: Tier A {len(st['A'][0]):,}, Tier B {len(st['B'][0]):,}.")
    out += ["", "By rejection reason (goals with at least one constant rejected for that reason):", ""]
    allr = sorted(set(st["A"][1]) | set(st["B"][1]), key=lambda x: (-(st["A"][1][x] + st["B"][1][x]), x))
    out.append(table(["rejection reason", "Tier A goals", "share", "Tier B goals", "share"],
                     [[r, st["A"][1][r], pct(st["A"][1][r], len(st["A"][0])), st["B"][1][r], pct(st["B"][1][r], len(st["B"][0]))]
                      for r in allr]))
    for t in "BA":
        ks, _, cc, _, cls = st[t]
        rows = [[f"`{c}`", v, pct(v, len(ks)), ", ".join(f"{a} {b:,}" for a, b in cls[c].most_common())]
                for c, v in sorted(cc.items(), key=lambda z: (-z[1], z[0]))[:15]]
        out += ["", f"Tier {t}: the 15 constants that block the most goals (goals where the constant is rejected; "
                "its rejection reasons, counted per goal and constant):", "",
                table(["constant", "goals", f"share of {len(ks):,}", "rejection reasons"], rows)]
    out += ["", "Goals blocked by exactly one rejected constant (removing that constant's rejection alone would "
            "leave the goal with a fully accepted `H_main`), by constant:", ""]
    for t in "BA":
        ks, _, _, one, _ = st[t]
        n1 = sum(one.values())
        top = sorted(one.items(), key=lambda z: (-z[1], z[0]))
        out.append(f"- **Tier {t}:** {n1:,} of {len(ks):,} goals ({pct(n1, len(ks))}); {len(one):,} distinct constants. "
                   + "; ".join(f"`{c}` {v}" for c, v in top[:12]) + ".")
    return out


def r3(d):
    out = ["## R3 Node counts", "", "Smallest N at which `solve_by_sat` found a proof:", ""]
    rows = []
    for run, t, name in [("main", "A", "Tier A"), ("main", "B", "Tier B"), ("r1b", "B", "R1b")]:
        c = collections.Counter(d.res[k]["N"] for k in d.keys(run, t) if d.proved(k))
        rows.append([name, sum(c.values())] + [c.get(n, 0) for n in range(1, 11)])
    out.append(table(["run", "proved"] + [f"N = {n}" for n in range(1, 11)], rows))
    out += ["", "Tier B: the oracle node estimate (§2.2) against the N found, proved goals of the main run "
            "(rows: estimate, `>10` pooled; columns: N found):", ""]
    ks = [k for k in d.keys("main", "B") if d.proved(k)]
    x = collections.Counter((min(d.corpus[d.specs[k]["id"]]["node_est"], 11), d.res[k]["N"]) for k in ks)
    rows = [[(">10" if e == 11 else e)] + [x.get((e, n), 0) for n in range(1, 10)] + [sum(x.get((e, n), 0) for n in range(1, 10))]
            for e in range(1, 12) if any(x.get((e, n)) for n in range(1, 10))]
    out.append(table(["estimate \\ N"] + [str(n) for n in range(1, 10)] + ["total"], rows))
    lt = sum(1 for k in ks if d.res[k]["N"] < d.corpus[d.specs[k]["id"]]["node_est"])
    eq = sum(1 for k in ks if d.res[k]["N"] == d.corpus[d.specs[k]["id"]]["node_est"])
    out += ["", f"N found below the estimate: {lt}; equal: {eq}; above: {len(ks) - lt - eq}."]
    return out


def r4(d):
    out = ["## R4 Baselines", "",
           "All baselines ran before the `solve_by_sat` N loop, from a fresh state, with 200,000 "
           "heartbeats (§10.5). *Like-for-like*: `solve_by_elim` with `H_main` and the local hypotheses "
           "only, `symm`/`exfalso` off, `maxDepth := 10`. *Default*: `solve_by_elim [H_main]` with its default "
           "lemmas, `maxDepth := 10`.", ""]
    for which, name in [("sbe_like", "like-for-like"), ("sbe_default", "default")]:
        rows = []
        for t in "AB":
            ks = d.keys("main", t)
            a = sum(1 for k in ks if d.proved(k) and d.sbe(k, which) == "closed")
            b = sum(1 for k in ks if d.proved(k) and d.sbe(k, which) != "closed")
            c = sum(1 for k in ks if not d.proved(k) and d.sbe(k, which) == "closed")
            e = len(ks) - a - b - c
            rows.append([f"Tier {t}", a, b, c, e])
        out += [f"`solve_by_sat` against `solve_by_elim` ({name}):", "",
                table(["tier", "both", "solve_by_sat only", "solve_by_elim only", "neither"], rows), ""]
    ks = d.keys("main", "B")
    a = sum(1 for k in ks if d.proved(k) and d.lib(k) == "closed_other")
    b = sum(1 for k in ks if d.proved(k) and d.lib(k) != "closed_other")
    c = sum(1 for k in ks if not d.proved(k) and d.lib(k) == "closed_other")
    out += ["`solve_by_sat` against `exact?` (Tier B only, §10.5; a closure counts only if `closed_other`):", "",
            table(["tier", "both", "solve_by_sat only", "exact? only", "neither"], [["Tier B", a, b, c, len(ks) - a - b - c]]), ""]
    rows = []
    for t in "AB":
        c = collections.Counter(d.lib(k) for k in d.keys("main", t))
        rows.append([f"Tier {t}"] + [c.get(o, 0) for o in ["closed_self", "closed_other", "none", "heartbeats", "max_rec_depth"]])
    out += ["`exact?` closures by kind (`apply?` has the same closures, with `partial` for `none`). Tier A is "
            "not compared: its own declaration is in the environment.", "",
            table(["tier", "closed_self", "closed_other", "none (apply?: partial)", "heartbeats", "max_rec_depth"], rows), ""]
    rows = []
    for t in "AB":
        ks = d.keys("main", t)
        sbs = [d.res[k]["loop_ms"] for k in ks if d.proved(k)]
        sl = [d.res[k]["baselines"]["sbe_like"]["ms"] for k in ks if d.sbe(k) == "closed"]
        sd = [d.res[k]["baselines"]["sbe_default"]["ms"] for k in ks if d.sbe(k, "sbe_default") == "closed"]
        ex = [d.res[k]["baselines"]["library_search"]["ms"] for k in ks if d.lib(k) == "closed_other"]
        for name, xs in [("solve_by_sat (N loop)", sbs), ("solve_by_elim like-for-like", sl),
                         ("solve_by_elim default", sd), ("exact? (closed_other)", ex)]:
            rows.append([f"Tier {t}", name, len(xs), med(xs), quantile(xs, .9)])
    out += ["Wall time in ms on the goals each one closes. `solve_by_sat`'s time is the whole N loop from "
            "N = 1, including compilation and every encode and solve:", "",
            table(["tier", "tactic", "goals closed", "median ms", "p90 ms"], rows)]
    rv = d.reviews.get("sbs_only")
    pop, _, _ = review_sets(d)["sbs_only"]
    c = collections.Counter((d.specs[k]["tier"], d.sbe(k) or "none") for k in pop)
    out += ["", f"Main-run goals `solve_by_sat` proves and like-for-like `solve_by_elim` does not: {len(pop)} "
            f"(Tier A {sum(v for (t, _), v in c.items() if t == 'A')}, Tier B {sum(v for (t, _), v in c.items() if t == 'B')}). "
            "`solve_by_elim`'s outcome on them:", "",
            table(["tier", "failed", "heartbeats", "max_rec_depth"],
                  [[f"Tier {t}"] + [c.get((t, o), 0) for o in ("failed", "heartbeats", "max_rec_depth")] for t in "AB"])]
    if rv:
        out += [""] + review_summary(d, "sbs_only", rv,
                                     "Review: why like-for-like `solve_by_elim` missed the proof (EVAL_PLAN §7)")
        _, _, _, recs, _, _ = in_sample(d, "sbs_only", rv)
        x = collections.Counter((r.get("sbe_outcome"), r.get("class")) for r in recs)
        cls = sorted({b for _, b in x}, key=str)
        out += ["", "`solve_by_elim`'s outcome (rows) against the reason (columns):", "",
                table(["outcome"] + cls + ["total"],
                      [[o] + [x.get((o, b), 0) for b in cls] + [sum(x.get((o, b), 0) for b in cls)]
                       for o in ("failed", "heartbeats", "max_rec_depth") if any(x.get((o, b)) for b in cls)])]
        cd = collections.Counter((r.get("class"), r.get("detail", "")) for r in recs)
        out += ["", "By reason and detail:", "",
                table(["reason", "detail", "goals"], [[a, b, v] for (a, b), v in sorted(cd.items(), key=lambda z: (-z[1], z[0]))])]
        Nc = collections.Counter(r.get("N") for r in recs)
        out += ["", "`solve_by_sat`'s N on these goals: " + ", ".join(f"N = {n}: {v}" for n, v in sorted(Nc.items())) + ".",
                "", "Every goal:", "",
                table(["goal", "solve_by_elim", "N", "solve_by_sat proof (skeleton)", "reason", "note"],
                      [[f"`{r['id']}`", r.get("sbe_outcome", ""), r.get("N", ""), f"`{short(r.get('skeleton'), 90)}`",
                        r.get("class", ""), short(r.get("note", ""), 120)] for r in recs])]
    return out


# SPEC 7.3 as published (Test/bench.py): (lemmas, N) -> (variables after, clauses before, clauses after)
SPEC73 = {(1, 5): (1237, 16910, 14283), (1, 8): (2829, 52800, 44119), (1, 12): (5723, 141128, 116999),
          (5, 5): (19292, 193350, 189563), (5, 8): (58101, 620176, 608135), (5, 12): (151055, 1681688, 1649015),
          (9, 5): (69242, 618190, 613943), (9, 8): (215493, 1978320, 1965351), (9, 12): (553199, 5159936, 5126687)}
SYN_FAMS = ["S", "T1", "T2", "T3"]
SYN_KS = [0, 4, 8, 16, 32]
SYN_NS = [5, 8, 12]
SYN_CFGS = ["all", "none", "no_candidate", "no_pair", "no_static"]


def gd_share(x):
    fm = x["families"]
    return (fm.get("8 groundness", 0) + fm.get("5 decomposition", 0)) / max(1, x["clauses"])


def r5(d):
    out = ["## R5 Synthetic scaling (§4.1)", ""]
    if not d.synth:
        return out + ["*Pending 7c.*"]
    R = {(x["family"], x["k"], x["N"], x["config"]): x for x in d.synth}
    h = d.synth_hdr or {}
    out += [f"SPEC 7.3's chain `x ≤ w` from `x ≤ y`, `y ≤ z`, `z ≤ w` with `Nat.le_trans` and k distractors "
            "`∀ m n, R m n → R (f m) (f n)` of one family (`Test/Synth.lean`): S, one shared `s : Nat → Nat` and `≤` on "
            "`Nat`; T1, distinct `fᵢ : Nat → Nat`; T2, distinct structures `Cᵢ` with their own `LE` instances and "
            "`fᵢ : Cᵢ → Cᵢ`; T3, distinct predicates `Pᵢ : Nat → Nat → Prop` with one shared `s`. Every cell goes through "
            "the Lean compile path and is counted with `countOnly`; nothing is solved "
            f"(`eval/scaling_synthetic.jsonl`, commit `{h.get('git_commit', '?')}`). Configurations: *all* refinements on; "
            "*none* (all milestone 6 refinements off; static typing stays on); *no_candidate*, *no_pair*: all on except "
            "candidate or pair pruning; *no_static*: all on with static typing off.", ""]
    bad = [x for x in d.synth if x["status"] != "ok" or x.get("H_rejected")]
    out += [f"Cells: {len(d.synth)}; not counted or with a rejected constant: {len(bad)}.", ""]
    fams = sorted({f for x in d.synth for f in x["families"]}, key=lambda f: int(f.split()[0]))
    rows = []
    for fa in SYN_FAMS:
        for k in SYN_KS:
            x = R[(fa, k, 8, "all")]
            rows.append([fa, k] + [x["families"].get(f, 0) for f in fams] + [x["clauses"], f"{100 * gd_share(x):.1f}"])
    out += ["Clauses per family at N = 8, all refinements on:", "",
            table(["family", "k"] + [f.split(" ", 1)[1].split(" (")[0] for f in fams] + ["total", "groundness + decomposition %"], rows), ""]
    rows = []
    X6 = {(x["family"], x["k"], x["N"]): x for x in d.e6}
    for fa in SYN_FAMS:
        for n in SYN_NS:
            rows.append([fa, n] + [R[(fa, 32, n, c)]["clauses"] for c in SYN_CFGS]
                        + ([X6[(fa, 32, n)]["clauses"]] if X6 else []))
    out += ["Total clauses at k = 32 by configuration" + (" (the last column is E6, exploratory: static typing and candidate "
            "pruning both off; see below)" if X6 else "") + ":", "",
            table(["family", "N"] + SYN_CFGS + (["no_typing (E6, exploratory)"] if X6 else []), rows), ""]
    same = {c: all(R[(fa, k, n, c)]["clauses"] == R[(fa, k, n, "all")]["clauses"] and
                   R[(fa, k, n, c)]["families"] == R[(fa, k, n, "all")]["families"]
                   for fa in SYN_FAMS for k in SYN_KS for n in SYN_NS) for c in SYN_CFGS[1:]}
    out += ["Configurations whose counts equal *all* in every cell: "
            + (", ".join(f"*{c}*" for c, v in same.items() if v) or "none") + ".", ""]
    rows = []
    for fa in SYN_FAMS:
        for c in SYN_CFGS:
            rows.append([fa, c] + [f"{math.log(R[(fa, 32, n, c)]['clauses'] / R[(fa, 8, n, c)]['clauses']) / math.log(4):.2f}"
                                   for n in SYN_NS])
    out += ["Growth exponent in k: log-log slope of total clauses from k = 8 to k = 32 "
            "(log(c₃₂ / c₈) / log 4). SPEC 7.3 reports about 2.", "",
            table(["family", "configuration"] + [f"N = {n}" for n in SYN_NS], rows), ""]
    rows = []
    for fa in SYN_FAMS:
        for n in SYN_NS:
            rows.append([fa, n] + [f"{100 * gd_share(R[(fa, k, n, 'all')]):.1f}" for k in SYN_KS])
    out += ["Share of groundness plus decomposition (%), all refinements on:", "",
            table(["family", "N"] + [f"k = {k}" for k in SYN_KS], rows), ""]
    rows = []
    for (l, n), (v, cb, ca) in SPEC73.items():
        a, b = R[("S", l - 1, n, "all")], R[("S", l - 1, n, "none")]
        rows.append([f"{l} lemma{'s' if l > 1 else ''} / k = {l - 1}", n, v, a["vars"], f"{a['vars'] / v:.3f}",
                     cb, b["clauses"], f"{b['clauses'] / cb:.3f}", ca, a["clauses"], f"{a['clauses'] / ca:.3f}"])
    out += ["Family S against SPEC 7.3 (untyped `bench` forests); *before* is all refinements off, *after* all on:", "",
            table(["7.3 row / S", "N", "7.3 vars after", "S vars", "ratio", "7.3 clauses before", "S none", "ratio",
                   "7.3 clauses after", "S all", "ratio"], rows), ""]
    fc = collections.Counter(x["full"] for x in d.synth_full)
    mo = sorted((x["family"], x["k"], x["N"], x["config"]) for x in d.synth_full if x["full"] == "memout")
    eqmax = max((R[(x["family"], x["k"], x["N"], x["config"])]["clauses"] for x in d.synth_full if x["full"] == "equal"), default=0)
    out += [f"**`countOnly` against a full encode (§10.9, 4.1 decision 1).** Every cell was also encoded in full under the "
            f"{h.get('limits', {}).get('cap_mb', 2500):,} MB cap (`eval/scaling_synthetic.fullcheck.jsonl`): "
            + ", ".join(f"{v} {k}" for k, v in sorted(fc.items())) + f". The largest equal cell has {eqmax:,} clauses. "
            "The memouts are " + "; ".join(f"{a} k = {b} N = {c} {e}" for a, b, c, e in mo) + "."
            if mo else f"**`countOnly` against a full encode.** " + ", ".join(f"{v} {k}" for k, v in sorted(fc.items())) + "."]
    out += [""] + e6(d, R)
    return out


def e6(d, R):
    """§10.10 decision 7 (E6, exploratory): both typing filters off, every other refinement on."""
    out = ["### E6 (exploratory): both typing filters off (§10.10 decision 7)", ""]
    if not d.e6:
        return out + ["*Pending.*"]
    X = {(x["family"], x["k"], x["N"]): x for x in d.e6}
    bad = [x for x in d.e6 if x["status"] != "ok" or x.get("H_rejected")]
    out += [f"Not pre-registered. The 60 cells of the grid (4 families × k ∈ {{0, 4, 8, 16, 32}} × N ∈ {{5, 8, 12}}) counted with "
            "`countOnly` in a sixth configuration, *no_typing*: static typing and candidate pruning both off, every other "
            "refinement on (`eval/scaling_synthetic_e6.jsonl`). The pre-registered grid is unchanged. "
            f"Cells: {len(d.e6)}; not counted or with a rejected constant: {len(bad)}. With it, *no_static* is candidate "
            "pruning alone, *no_candidate* is static typing alone, and *all* is both.", ""]
    rows = []
    for fa in SYN_FAMS:
        for n in SYN_NS:
            dd = X[(fa, 32, n)]["clauses"]
            rows.append([fa, n, dd, R[(fa, 32, n, "no_static")]["clauses"], R[(fa, 32, n, "no_candidate")]["clauses"],
                         R[(fa, 32, n, "all")]["clauses"],
                         f"{dd / R[(fa, 32, n, 'all')]['clauses']:.2f}"])
    out += ["Total clauses at k = 32:", "",
            table(["family", "N", "no_typing (E6)", "candidate pruning alone (no_static)", "static typing alone (no_candidate)",
                   "both (all)", "no_typing / all"], rows), ""]
    rows = []
    for fa in SYN_FAMS:
        rows.append([fa] + [f"{math.log(X[(fa, 32, n)]['clauses'] / X[(fa, 8, n)]['clauses']) / math.log(4):.2f}" for n in SYN_NS]
                    + [f"{100 * gd_share(X[(fa, 32, n)]):.1f}" for n in SYN_NS])
    out += ["*no_typing*: growth exponent from k = 8 to 32, and the share of groundness plus decomposition (%) at k = 32:", "",
            table(["family"] + [f"exponent N = {n}" for n in SYN_NS] + [f"g + d % N = {n}" for n in SYN_NS], rows), ""]
    same = [fa for fa in SYN_FAMS if all(X[(fa, k, n)]["clauses"] == R[(fa, k, n, "all")]["clauses"]
                                         and X[(fa, k, n)]["families"] == R[(fa, k, n, "all")]["families"]
                                         for k in SYN_KS for n in SYN_NS)]
    t2 = []
    for n in SYN_NS:
        dd, cand, stat, both = (X[("T2", 32, n)]["clauses"], R[("T2", 32, n, "no_static")]["clauses"],
                                R[("T2", 32, n, "no_candidate")]["clauses"], R[("T2", 32, n, "all")]["clauses"])
        t2.append((n, dd, cand, stat, both))
    out.append("**What each filter does alone in T2** (k = 32): with both off, T2 has "
               + ", ".join(f"{dd:,}" for _, dd, _, _, _ in t2) + " clauses at N = 5, 8, 12. Candidate pruning alone keeps "
               + ", ".join(pct(c, dd) for _, dd, c, _, _ in t2) + " of them; static typing alone keeps "
               + ", ".join(pct(st_, dd) for _, dd, _, st_, _ in t2) + "; both keep "
               + ", ".join(pct(b, dd) for _, dd, _, _, b in t2) + ". "
               + ("The two filters remove the same clauses in T2: either alone gives the count of both. "
                  if all(c == b and st_ == b for _, _, c, st_, b in t2) else "")
               + "Families where *no_typing* equals *all* in every cell: " + (", ".join(same) or "none") + ".")
    return out


SC_KS = [2, 4, 8, 16, 32]
SC_BUCKETS = ["1", "2", "3-4", "5+"]


def r6(d):
    out = ["## R6 Real distractors (§4.2)", ""]
    if not d.sc_res or not d.sc_hdr:
        return out + ["*Pending the full 4.2 run (EVAL_PLAN §10.9).*"]
    S, R, Z, h = d.sc_specs, d.sc_res, d.sc_size, d.sc_hdr
    goals = sorted({k.split(":", 3)[3] for k in S})
    nb = collections.Counter(S["scale:none:0:" + g]["bucket"] for g in goals)
    short = sorted((k, S[k]["k_actual"]) for k in S if S[k]["k_actual"] < S[k]["k"])
    oc = collections.Counter(r["outcome"] for r in R.values())
    out += [f"{len(goals)} main-run goals proved in `eval/final/`, drawn by proved N (EVAL_PLAN §10.9 decision 1: "
            + ", ".join(f"{nb[b]} at N {'= ' if b in ('1', '2') else ''}{b.replace('-', '–').replace('+', ' or more')}" for b in SC_BUCKETS)
            + "). Distractors are compiler-accepted core theorems (`eval/scaling_pool.jsonl`), nested in k, chosen "
            "uniformly (*random*) or with a matching head symbol (*near*). Each goal runs once at k = 0 and at "
            "k = 2, 4, 8, 16 and 32 in each mode, with N from 1 up to its original N "
            f"({len(R):,} runs; `eval/scaling_full/`, commit `{h['git_commit'][:7]}`, the 7b limits: solver "
            f"{h['solver_s']} s per call, N loop {h['loop_s']} s, memory cap {h['cap_mb']:,} MB, P = {h['parallel_shards']}; "
            f"{h['machine']['cpu']}, {h['machine']['ram_mib']:,} MiB). Every run's clauses at the original N are also "
            "counted with `countOnly` (`eval/scaling_full/sizes.jsonl`), so crashed runs have sizes too. "
            + (f"Too few near candidates for k = 32: " + "; ".join(f"`{k.split(':', 3)[3]}` ({a})" for k, a in short) + ". " if short else "")
            + "Outcomes: " + ", ".join(f"{v:,} {k}" for k, v in sorted(oc.items())) + ".", ""]
    k0 = collections.Counter(R["scale:none:0:" + g]["outcome"] for g in goals)
    below = sum(1 for r in R.values() if r.get("below_original"))
    used = sum(1 for r in R.values() if r.get("distractors_used"))
    stops = sum(1 for r in R.values() if "stop" in r)
    out += [f"**Stop rules (§10.9 decision 9).** No run stopped: every run within the limits found a proof at or below "
            f"its original N, and the k = 0 runs agree with `eval/final/` ({', '.join(f'{v} {k}' for k, v in k0.items())}). "
            f"Runs with a `stop` field: {stops}. Proofs shorter than the original N: {below}. Proofs that use a "
            f"distractor: {used}.", ""]
    rows = []
    for m in ("random", "near"):
        for k in SC_KS:
            ks = [x for x in S if S[x]["mode"] == m and S[x]["k"] == k]
            c = collections.Counter(R[x]["outcome"] for x in ks)
            cl = [Z[x]["clauses"] for x in ks]
            ratio = [Z[x]["clauses"] / Z["scale:none:0:" + x.split(":", 3)[3]]["clauses"] for x in ks]
            t = [R[x]["total_ms"] for x in ks if R[x]["outcome"] == "proved"]
            rows.append([m, k, c.get("proved", 0), c.get("crash", 0), c.get("timeout", 0), int(med(cl)), max(cl),
                         f"{med(ratio):.1f}", int(med(t)) if t else "–"])
    c0 = [Z["scale:none:0:" + g]["clauses"] for g in goals]
    t0 = [R["scale:none:0:" + g]["total_ms"] for g in goals]
    out += [f"Outcomes, clauses at the original N (`countOnly`) and time against k. At k = 0: median "
            f"{int(med(c0)):,} clauses (max {max(c0):,}), median {int(med(t0)):,} ms. *Growth* is the median over goals "
            "of clauses at k over clauses at k = 0. Time is the whole run (compile, encode, solve, decode, all N), "
            "proved runs only. Every crash is the memory cap.", "",
            table(["mode", "k", "proved", "memory crash", "timeout", "median clauses", "max clauses", "growth",
                   "median ms (proved)"], rows), ""]
    cr = [Z[k]["clauses"] for k in R if R[k]["outcome"] == "crash"]
    pr = [Z[k]["clauses"] for k in R if R[k]["outcome"] == "proved"]
    out += [f"The smallest crashed run has {min(cr):,} clauses at the original N; the largest proved run {max(pr):,}.", ""]

    def feas(g, m):
        fe = {0: R["scale:none:0:" + g]["outcome"] == "proved"}
        for k in SC_KS:
            fe[k] = R[f"scale:{m}:{k}:{g}"]["outcome"] == "proved"
        pre = None
        for k in [0] + SC_KS:
            if not fe[k]:
                break
            pre = k
        alone = max((k for k in [0] + SC_KS if fe[k]), default=None)
        return pre, alone

    F = {(g, m): feas(g, m) for g in goals for m in ("random", "near")}
    rows = []
    for m in ("random", "near"):
        for i, what in ((0, "every k′ ≤ k feasible"), (1, "largest feasible k alone")):
            v = [F[(g, m)][i] for g in goals]
            dist = collections.Counter(v)
            rows.append([m, what] + [dist.get(k, 0) for k in [0] + SC_KS] + [fmt(med(v))])
    same = sum(1 for x in F.values() if x[0] == x[1])
    out += ["**Largest feasible k** per goal (§10.9 decision 8: a proof at or below the original N within the "
            "limits). Number of goals by largest feasible k, and the median:", "",
            table(["mode", "definition"] + [f"k = {k}" for k in [0] + SC_KS] + ["median"], rows), "",
            f"The two definitions agree for {same} of {len(F)} goal–mode pairs.", ""]
    rows = []
    for b in SC_BUCKETS:
        gs = [g for g in goals if S["scale:none:0:" + g]["bucket"] == b]
        rows.append([b.replace("-", "–"), len(gs)] + [fmt(med([F[(g, m)][0] for g in gs])) for m in ("random", "near")]
                    + [sum(1 for g in gs if F[(g, m)][0] == 32) for m in ("random", "near")])
    out += ["By original N (bucket): median largest feasible k, and goals feasible at every k up to 32:", "",
            table(["original N", "goals", "median random", "median near", "all k random", "all k near"], rows), ""]
    out += r6_additions(d, goals, F)
    return out


def sc_eq_split(d, goals):
    """§10.10 decision 5: the goals whose S (eval/scaling_goals.jsonl) contains `c:Eq`, and the others."""
    eq = [g for g in goals if "c:Eq" in d.sc_goals[g]["S"]]
    return [("S contains `c:Eq`", eq), ("S without `c:Eq`", [g for g in goals if g not in set(eq)])]


def sc_exponent(d, g, m, actual=False):
    """Per-goal growth exponent in k from 8 to 32: log(c₃₂ / c₈) / log(k₃₂ / k₈), clauses at the original N."""
    S, Z = d.sc_specs, d.sc_size
    a, b = f"scale:{m}:8:{g}", f"scale:{m}:32:{g}"
    ka, kb = (S[a]["k_actual"], S[b]["k_actual"]) if actual else (8, 32)
    return math.log(Z[b]["clauses"] / Z[a]["clauses"]) / math.log(kb / ka)


def r6_additions(d, goals, F):
    S, R, Z = d.sc_specs, d.sc_res, d.sc_size
    groups = [("all goals", goals)] + sc_eq_split(d, goals)
    out = ["**Per-goal growth exponent** (§10.10 decision 5): for each goal and mode, the log-log slope of its clauses "
           "at the original N (`countOnly`) from k = 8 to k = 32, log(c₃₂ / c₈) / log 4; the table gives the median over "
           "goals, with the quartiles.", ""]
    rows = []
    for name, gs in groups:
        row = [name, len(gs)]
        for m in ("random", "near"):
            v = [sc_exponent(d, g, m) for g in gs]
            row.append(f"{med(v):.2f} ({quantile(v, .25):.2f}–{quantile(v, .75):.2f})")
        rows.append(row)
    out.append(table(["goals", "n", "random", "near"], rows))
    short = [g for g in goals if S[f"scale:near:32:{g}"]["k_actual"] < 32]
    va = [sc_exponent(d, g, "near", True) for g in goals]
    out += ["", f"k is the nominal k. {len(short)} goals have fewer than 32 near candidates (R6 above); with their actual k "
            f"the median near exponent over all goals is {med(va):.2f}. The random sets always have the nominal k.", ""]
    out += ["**R6's main table by whether S contains `c:Eq`** (§10.10 decision 5; S as in `eval/scaling_goals.jsonl`). "
            "When it does, about "
            f"{pct(sum(1 for p in d.pool if 'c:Eq' in p['heads']), len(d.pool))} of the pool "
            f"({sum(1 for p in d.pool if 'c:Eq' in p['heads']):,} of {len(d.pool):,} constants) has an `Eq` head, so *near* "
            "draws from most of the pool.", ""]
    rows = []
    for name, gs in groups[1:]:
        c0 = [Z["scale:none:0:" + g]["clauses"] for g in gs]
        rows.append([name, len(gs), "none", 0, sum(1 for g in gs if R["scale:none:0:" + g]["outcome"] == "proved"),
                     0, 0, int(med(c0)), "1.0"])
        for m in ("random", "near"):
            for k in SC_KS:
                ks = [f"scale:{m}:{k}:{g}" for g in gs]
                c = collections.Counter(R[x]["outcome"] for x in ks)
                cl = [Z[x]["clauses"] for x in ks]
                ratio = [Z[x]["clauses"] / Z["scale:none:0:" + x.split(":", 3)[3]]["clauses"] for x in ks]
                rows.append([name, len(gs), m, k, c.get("proved", 0), c.get("crash", 0), c.get("timeout", 0),
                             int(med(cl)), f"{med(ratio):.1f}"])
    out.append(table(["goals", "n", "mode", "k", "proved", "memory crash", "timeout", "median clauses", "growth"], rows))
    rows = []
    for name, gs in groups:
        nb = collections.Counter(S["scale:none:0:" + g]["bucket"] for g in gs)
        rows.append([name, len(gs), " ".join(f"{b.replace('-', '–')}:{nb.get(b, 0)}" for b in SC_BUCKETS)]
                    + [fn(med([F[(g, m)][0] for g in gs])) for m in ("random", "near")]
                    + [sum(1 for g in gs if F[(g, m)][0] == 32) for m in ("random", "near")])
    out += ["", "Largest feasible k (every k′ ≤ k feasible) by the same split, with the goals per original-N bucket:", "",
            table(["goals", "n", "original N buckets", "median random", "median near", "all k random", "all k near"], rows)]
    return out


def r7(d):
    out = ["## R7 Soft completeness (§3.4)", "",
           "A Tier B goal is oracle-in-class if the compiler accepts the goal and every `H_main` constant, the "
           "oracle term uses no elimination constant, and its node estimate is at most 10.", ""]
    ks = d.keys("main", "B")
    ic = [k for k in ks if d.oracle_in_class(k)]
    c = collections.Counter(d.raw(k) for k in ic)
    out.append(table(["oracle-in-class Tier B goals"] + list(c.keys()), [[len(ic)] + list(c.values())]))
    rv = d.reviews.get("r7_soft_completeness")
    if rv:
        out += [""] + review_summary(d, "r7_soft_completeness", rv, "Review of the oracle-in-class goals with no proof ≤ 10")
        rows = [[f"`{x['id']}`", x.get("class", ""), short(x.get("note", ""), 140)] for x in in_sample(d, "r7_soft_completeness", rv)[3]]
        out += ["", "Every reviewed case:", "", table(["goal", "classification", "note"], rows)]
    return out


def in_sample(d, name, rv):
    """The review records of the current sample only (10.8 decision 2: a review of a goal that left
    the sample is superseded and not counted), with the sample keys that have no record."""
    pop, smp, seed = review_sets(d)[name]
    ss = set(smp)
    recs = [x for x in rv if x["key"] in ss]
    have = {x["key"] for x in recs}
    return pop, smp, seed, recs, [k for k in smp if k not in have], [x["key"] for x in rv if x["key"] not in ss]


def review_summary(d, name, rv, title):
    pop, smp, seed, recs, missing, outside = in_sample(d, name, rv)
    c = collections.Counter(x.get("class", "?") for x in recs)
    reused = sum(1 for x in recs if x.get("reused"))
    chg = sum(1 for x in recs if d.rerun_set.get(x["key"]) == "changed")
    out = [f"### {title}", "",
           f"Population {len(pop):,}; sample {len(smp)}"
           + (f" (seeded, seed {seed})" if seed and len(pop) > len(smp) else " (all)") + f"; reviewed {len(recs)}"
           + (f", {len(missing)} not yet reviewed" if missing else "") + ". "
           f"{reused} reviews were reused from the sample drawn before the fix (same goal, forest unchanged); "
           f"the other {len(recs) - reused} were done after the merge, including {chg} goals whose forest changed. "
           f"Per-goal records: `eval/reviews/{name}.jsonl`."
           + (f" Records outside the sample (not counted): {len(outside)}." if outside else ""), "",
           table(["classification", "goals"], sorted(c.items(), key=lambda z: (-z[1], z[0])))]
    return out


def exploratory(d):
    out = ["# Exploratory analyses (not pre-registered)", "",
           "These analyses were added after the full run (EVAL_PLAN §10.6). They were not pre-registered.", ""]
    # E1
    out += ["## E1 Where `solve_by_elim` wins", "",
            "Goals that like-for-like `solve_by_elim` closes and `solve_by_sat` does not prove, by "
            "`solve_by_sat`'s raw outcome and by primary reason:", ""]
    rows = []
    for t in "AB":
        ks = [k for k in d.keys("main", t) if d.sbe(k) == "closed" and not d.proved(k)]
        c = collections.Counter(d.raw(k) for k in ks)
        r = collections.Counter(d.reason(k) for k in ks)
        rows.append([f"Tier {t}", len(ks)] + [c.get(o, 0) for o in ["no proof ≤ 10", "memory crash", "goal rejected", "solver timeout"]])
        rows.append([f"  by reason", ""] + [", ".join(f"{x.split(' ', 1)[1]} {v}" for x, v in r.most_common()), "", "", ""])
    out.append(table(["tier", "goals", "no proof ≤ 10", "memory crash", "goal rejected", "solver timeout"], rows))
    if "e1_sbe_wins" in d.reviews:
        rv = d.reviews["e1_sbe_wins"]
        out += [""] + review_summary(d, "e1_sbe_wins", rv,
                                     "Review: why `solve_by_sat` found no proof where `solve_by_elim` closed the goal")
        _, _, _, recs, _, _ = in_sample(d, "e1_sbe_wins", rv)
        ev = collections.Counter((x.get("evidence") or {}).get("source") for x in recs)
        out += ["", f"The first E1 pass (before the fix) recorded `solve_by_elim`'s proof terms but classified none of them, "
                f"so every goal is classified here. The evidence (like-for-like `solve_by_elim` rerun by `eval_numerals inspect sbe`) "
                f"is the pre-fix record for {ev.get('before_fix', 0)} goals (in the earlier sample, forest unchanged) and new for "
                f"{ev.get('after_merge', 0)} (`eval/reviews/e1_sbe_wins.evidence.jsonl`)."]
        c = collections.Counter((x.get("class", "?"), x.get("detail", "")) for x in recs)
        out += ["", "By class and detail (for definitional unfolding: what is unfolded; for a rejected constant: "
                "the constant's rejection reason):", "",
                table(["class", "detail", "goals"], [[a, b, v] for (a, b), v in sorted(c.items(), key=lambda z: (z[0][0], -z[1], z[0][1]))]),
                "", "Every reviewed goal:", "",
                table(["goal", "class", "detail", "note"],
                      [[f"`{x['id']}`", x.get("class", ""), x.get("detail", ""), short(x.get("note", ""), 140)] for x in recs])]
    # E2
    out += ["", "## E2 The data-constant rule", "",
            "R1b against the main run on the same 300 goals. A goal proved with `H_full` and not with `H_main` "
            "would be a counterexample to the §10.2 rule.", ""]
    ids = [d.specs[k]["id"] for k in d.keys("r1b")]
    only_full = [i for i in ids if d.proved("r1b:" + i) and not d.proved("main:" + i)]
    only_main = [i for i in ids if d.proved("main:" + i) and not d.proved("r1b:" + i)]
    rows = []
    for i in only_full:
        r = d.res["r1b:" + i]
        extra = sorted(set(d.specs["r1b:" + i]["H"]) - set(d.specs["main:" + i]["H"]))
        rows.append([f"`{i}`", r["N"], d.raw("main:" + i), short(", ".join(extra), 80), f"`{short(r.get('skeleton'), 120)}`"])
    out += [f"Proved only with `H_full`: {len(only_full)}. Proved only with `H_main`: {len(only_main)}"
            + (f" ({', '.join(f'`{i}`' for i in only_main[:10])}{'…' if len(only_main) > 10 else ''})" if only_main else "") + ".", ""]
    if rows:
        out.append(table(["goal", "N (H_full)", "H_main outcome", "constants only in H_full", "proof (skeleton)"], rows))
    # E3
    out += ["", "## E3 CNF composition on real goals", "",
            "Per-family share of the clauses at the final N, main run, goals with a recorded CNF (proved, "
            "no proof ≤ 10, solver timeout). Mean of the per-goal shares.", ""]
    fams = sorted({f for k in d.keys("main") for f in (d.res[k].get("families") or {})}, key=lambda f: int(f.split()[0]))
    def shares(ks):
        acc = collections.defaultdict(list)
        for k in ks:
            fm = d.res[k]["families"]
            tot = sum(fm.values()) or 1
            for f in fams:
                acc[f].append(fm.get(f, 0) / tot)
        return {f: statistics.mean(v) for f, v in acc.items()}
    rows = []
    for t in "AB":
        for kind, pred in [("proved", lambda k: d.proved(k)), ("no proof ≤ 10", lambda k: d.res[k]["outcome"] == "no_proof_le_Nmax")]:
            ks = [k for k in d.keys("main", t) if pred(k) and d.res[k].get("families")]
            sh = shares(ks)
            rows.append([f"Tier {t}", kind, len(ks)] + [f"{100 * sh.get(f, 0):.1f}" for f in fams])
    out.append(table(["tier", "goals", "n"] + [f.split(" ", 1)[1].split(" (")[0] for f in fams], rows))
    out += ["", "Share of groundness + decomposition (%), and median clauses at the final N, by \\|H_main\\| "
            "(main run, proved and no-proof goals pooled):", ""]
    rows = []
    for t in "AB":
        for _, _, b in BUCKETS:
            ks = [k for k in d.keys("main", t) if d.res[k].get("families") and d.res[k]["outcome"] in ("proved", "no_proof_le_Nmax")
                  and bucket(len(d.specs[k]["H"])) == b]
            if not ks:
                continue
            gd = [(d.res[k]["families"].get("8 groundness", 0) + d.res[k]["families"].get("5 decomposition", 0)) / max(1, d.res[k]["clauses"]) for k in ks]
            rows.append([f"Tier {t}", b, len(ks), f"{100 * statistics.mean(gd):.1f}", f"{med([d.res[k]['clauses'] for k in ks]):,.0f}"])
    out.append(table(["tier", "\\|H_main\\|", "goals", "groundness + decomposition %", "median clauses"], rows))
    out += ["", "No-proof goals (final N = 10): median clauses at N = 10 by \\|H_main\\|. Proved goals: share of "
            "groundness + decomposition by the N found:", ""]
    rows = []
    for t in "AB":
        for n in range(1, 10):
            ks = [k for k in d.keys("main", t) if d.proved(k) and d.res[k]["N"] == n and d.res[k].get("families")]
            if ks:
                gd = [(d.res[k]["families"].get("8 groundness", 0) + d.res[k]["families"].get("5 decomposition", 0)) / max(1, d.res[k]["clauses"]) for k in ks]
                rows.append([f"Tier {t}", n, len(ks), f"{100 * statistics.mean(gd):.1f}", f"{med([d.res[k]['clauses'] for k in ks]):,.0f}"])
    out.append(table(["tier", "N found", "goals", "groundness + decomposition %", "median clauses"], rows))
    out += ["", "Memory crashes: the last N reached, by \\|H_main\\|. The clause counts at that N are not in the "
            "data: a crash kills the shard before its result line is written, and the per-N log is part of that "
            "line. They could only be recomputed by encoding again, which 7d-1 does not do.", ""]
    rows = []
    for t in "AB":
        for _, _, b in BUCKETS:
            ks = [k for k in d.keys("main", t) if d.res[k]["outcome"] == "crash" and bucket(len(d.specs[k]["H"])) == b]
            if ks:
                c = collections.Counter(d.res[k].get("last_N") for k in ks)
                rows.append([f"Tier {t}", b, len(ks)] + [c.get(n, 0) for n in range(1, 11)])
    out.append(table(["tier", "\\|H_main\\|", "crashes"] + [f"N={n}" for n in range(1, 11)], rows))
    # E4
    out += ["", "## E4 Time on goals both prove", "",
            "Goals proved by `solve_by_sat` and closed by like-for-like `solve_by_elim`. `solve_by_sat`: the whole "
            "N loop (compilation, every encode and solve, the decode). `solve_by_elim`: its call.", ""]
    rows = []
    for t in "AB":
        ks = [k for k in d.keys("main", t) if d.proved(k) and d.sbe(k) == "closed"]
        a = [d.res[k]["loop_ms"] for k in ks]
        b = [d.res[k]["baselines"]["sbe_like"]["ms"] for k in ks]
        ratio = [x / max(1, y) for x, y in zip(a, b)]
        faster = sum(1 for x, y in zip(a, b) if x < y)
        rows.append([f"Tier {t}", len(ks), med(a), quantile(a, .9), med(b), quantile(b, .9),
                     f"{med(ratio):.1f}" if ratio else "–", faster])
    out.append(table(["tier", "goals", "solve_by_sat median ms", "p90", "solve_by_elim median ms", "p90",
                      "median ratio (sat / elim)", "goals where solve_by_sat is faster"], rows))
    out += ["", "By the N found (both tiers pooled):", ""]
    rows = []
    for n in range(1, 10):
        ks = [k for k in d.keys("main") if d.proved(k) and d.sbe(k) == "closed" and d.res[k]["N"] == n]
        if ks:
            rows.append([n, len(ks), med([d.res[k]["loop_ms"] for k in ks]), med([d.res[k]["baselines"]["sbe_like"]["ms"] for k in ks])])
    out.append(table(["N", "goals", "solve_by_sat median ms", "solve_by_elim median ms"], rows))
    return out


M8_ORDER = ["3A", "1", "2", "out"]


def m8_family(d, name):
    """The family of one obstacle constant by the fixed table eval/m8_families.json (its `how`)."""
    T = d.m8
    if name in T["explicit"]:
        return T["explicit"][name]
    last = name.rsplit(".", 1)[-1]
    if last in T["suffix_3A"]:
        return "3A"
    f = d.m8_facts.get(name, {})
    kind = f.get("kind")
    if kind in ("recursor", "auxrec"):
        ind = f["inductive"]
        return "1" if ind in T["inductives_1"] else "3A" if ind in T["inductives_3A"] else "2"
    if kind == "matcher":
        heads = [x["head"] if x["head_ind"] else (x["whnf_head"] if x["whnf_ind"] else None) for x in f["discrs"]]
        hs = [h for h in heads if h is not None]
        if any(h not in T["inductives_1"] and h not in T["inductives_3A"] for h in hs):
            return "2"
        if any(h in T["inductives_1"] for h in hs):
            return "1"
        if any(h in T["inductives_3A"] for h in hs):
            return "3A"
        return "out"
    if re.search(T["induction_regex"], last, re.I):
        return "1" if name.rsplit(".", 1)[0] in T["inductives_1"] else "2"
    return "out"


def m8_obstacles(d, k):
    c = d.corpus[d.specs[k]["id"]]
    return sorted({x for x, _ in d.acc[k][1]} | set(c.get("elim", [])))


def m8_population(d, t):
    """Main-run goals of tier t that the compiler accepts and solve_by_sat does not prove."""
    return [k for k in d.keys("main", t) if d.acc[k][0] and not d.proved(k)]


def e5(d):
    out = ["## E5 What milestone 8 would reach (§10.10 decision 6)", ""]
    if not d.m8 or not d.m8_facts:
        return out + ["*Pending.*"]
    out += ["Not pre-registered. Population: the main-run goals that the compiler accepts and `solve_by_sat` does not prove. "
            "A goal's *obstacles* are its rejected `H_main` constants and the elimination constants of its oracle term "
            "(§2.1, §10.4). Each obstacle is mapped to a family of the milestone 8 proposal by the fixed table "
            "`eval/m8_families.json`, committed before any count, using the structural facts of `eval/m8_obstacles.jsonl` "
            "(`Test/M8Facts.lean`): **3A** rewriting by first-order equality rules; **1** eliminations whose motive is "
            "the goal; **2** cases and induction on data; **out** out of reach.", "",
            "**This is an upper bound.** Removing every obstacle does not make a goal provable: definitional unfolding, "
            "instances and proof size can still block it (R2's unexplained goals and R7's reviews are goals with no "
            "obstacle that are still not proved), and the `congrArg` chains of elaborated `simp` proofs may need many nodes.", ""]
    names = sorted({x for t in "AB" for k in m8_population(d, t) for x in m8_obstacles(d, k)})
    miss = [x for x in names if x not in d.m8_facts or d.m8_facts[x].get("kind") == "missing"]
    fc = collections.Counter(m8_family(d, x) for x in names)
    out += [f"Distinct obstacle constants: {len(names):,} (" + ", ".join(f"{f} {fc.get(f, 0):,}" for f in M8_ORDER)
            + f"); without facts: {len(miss)}.", ""]
    combos, single = {}, {}
    rows = []
    for t in "AB":
        ks = m8_population(d, t)
        cb = collections.Counter("+".join(f for f in M8_ORDER if f in {m8_family(d, x) for x in m8_obstacles(d, k)}) or "no obstacle"
                                 for k in ks)
        combos[t] = (ks, cb)
    labels = sorted(set(combos["A"][1]) | set(combos["B"][1]),
                    key=lambda x: (x == "no obstacle", -(combos["A"][1][x] + combos["B"][1][x]), x))
    out += ["Goals by the combination of families among their obstacles:", "",
            table(["families", "Tier A", "Tier B"], [[x, combos["A"][1][x], combos["B"][1][x]] for x in labels]
                  + [["total", len(combos["A"][0]), len(combos["B"][0])]]), ""]
    rows = []
    for f in M8_ORDER:
        rows.append([f"all in {f}"] + [f"{combos[t][1][f]:,} ({pct(combos[t][1][f], len(combos[t][0]))})" for t in "AB"])
    reach = {t: sum(v for x, v in combos[t][1].items() if x != "no obstacle" and "out" not in x.split("+")) for t in "AB"}
    rows.append(["all in 3A, 1 or 2 (no out-of-reach obstacle)"] + [f"{reach[t]:,} ({pct(reach[t], len(combos[t][0]))})" for t in "AB"])
    rows.append(["no obstacle"] + [f"{combos[t][1]['no obstacle']:,} ({pct(combos[t][1]['no obstacle'], len(combos[t][0]))})" for t in "AB"])
    out += ["Goals whose obstacles all fall in a single family (share of the population):", "",
            table(["", "Tier A", "Tier B"], rows), ""]
    prov = {t: sum(1 for k in d.keys("main", t) if d.proved(k)) for t in "AB"}
    out += ["For scale: `solve_by_sat` proves " + ", ".join(f"{prov[t]:,} Tier {t} goals" for t in "AB")
            + ". If every goal whose obstacles all lie in 3A became provable, the proved share would be at most "
            + ", ".join(f"{pct(prov[t] + combos[t][1]['3A'], 3000)} in Tier {t}" for t in "AB")
            + "; with 3A, 1 and 2 together, at most " + ", ".join(f"{pct(prov[t] + reach[t], 3000)} in Tier {t}" for t in "AB") + ".", ""]
    for t in "BA":
        ks = combos[t][0]
        oc = collections.Counter(x for k in ks for x in m8_obstacles(d, k) if m8_family(d, x) == "out")
        out.append(f"- **Tier {t}, most common out-of-reach constants** (goals): "
                   + "; ".join(f"`{c}` {v}" for c, v in sorted(oc.items(), key=lambda z: (-z[1], z[0]))[:15]) + ".")
    for t in "BA":
        ks = combos[t][0]
        fc2 = collections.defaultdict(collections.Counter)
        for k in ks:
            for x in m8_obstacles(d, k):
                fc2[m8_family(d, x)][x] += 1
        out.append(f"- **Tier {t}, most common constant per family** (goals): "
                   + "; ".join(f"{f}: " + ", ".join(f"`{c}` {v}" for c, v in sorted(fc2[f].items(), key=lambda z: (-z[1], z[0]))[:5])
                               for f in M8_ORDER[:3]) + ".")
    return out


def fn(x):
    """A number for prose: integral floats without the decimal point."""
    if isinstance(x, float) and x.is_integer():
        x = int(x)
    return fmt(x)


def rng(xs, f):
    a, b = format(min(xs), f), format(max(xs), f)
    return a if a == b else f"{a}–{b}"


class Facts:
    """The numbers the summary, the reading and the threats rest on, computed once from the data."""

    def __init__(self, d):
        self.d = d
        self.n = {t: len(d.keys("main", t)) for t in "AB"}
        self.proved = {t: sum(1 for k in d.keys("main", t) if d.proved(k)) for t in "AB"}
        self.hfull = {t: [k for k in d.keys("main", t) if d.acc[k][0] and not d.acc[k][1]] for t in "AB"}
        self.proved_hfull = {t: sum(1 for k in self.hfull[t] if d.proved(k)) for t in "AB"}
        self.notp = {t: collections.Counter(d.reason(k) for k in d.keys("main", t) if not d.proved(k)) for t in "AB"}
        self.r2 = {t: r2_stats(d, t) for t in "AB"}
        self.Ns = {t: [d.res[k]["N"] for k in d.keys("main", t) if d.proved(k)] for t in "AB"}
        self.crash = {t: sum(1 for k in d.keys("main", t) if d.res[k]["outcome"] == "crash") for t in "AB"}
        self.crash_all = sum(1 for k in d.specs if d.res[k]["outcome"] == "crash")
        self.nop = {t: sum(1 for k in d.keys("main", t) if d.res[k]["outcome"] == "no_proof_le_Nmax") for t in "AB"}
        self.both = {t: sum(1 for k in d.keys("main", t) if d.proved(k) and d.sbe(k) == "closed") for t in "AB"}
        self.sbe = {t: sum(1 for k in d.keys("main", t) if d.sbe(k) == "closed") for t in "AB"}
        self.exact_b = sum(1 for k in d.keys("main", "B") if d.lib(k) == "closed_other")
        self.exact_both_b = sum(1 for k in d.keys("main", "B") if d.lib(k) == "closed_other" and d.proved(k))
        self.time = {}
        for t in "AB":
            ks = [k for k in d.keys("main", t) if d.proved(k) and d.sbe(k) == "closed"]
            a = [d.res[k]["loop_ms"] for k in ks]
            b = [d.res[k]["baselines"]["sbe_like"]["ms"] for k in ks]
            self.time[t] = (med(a), med(b), sum(1 for x, y in zip(a, b) if x < y), len(ks))
        ic = [k for k in d.keys("main", "B") if d.oracle_in_class(k)]
        self.inclass = (len(ic), sum(1 for k in ic if d.proved(k)))
        self.rev = {}
        for name in ("sbs_only", "r7_soft_completeness", "r2_unexplained", "e1_sbe_wins"):
            if name in d.reviews:
                _, _, _, recs, _, _ = in_sample(d, name, d.reviews[name])
                self.rev[name] = (len(recs), collections.Counter(r.get("class") for r in recs))
        # synthetic (R5): growth exponent and g + d share at k = 32, per family, over N
        R = {(x["family"], x["k"], x["N"], x["config"]): x for x in d.synth}
        self.syn_exp = {fa: [math.log(R[(fa, 32, n, "all")]["clauses"] / R[(fa, 8, n, "all")]["clauses"]) / math.log(4) for n in SYN_NS]
                        for fa in SYN_FAMS}
        self.syn_gd = {fa: [100 * gd_share(R[(fa, 32, n, "all")]) for n in SYN_NS] for fa in SYN_FAMS}
        # real distractors (R6)
        S, Rr, Z = d.sc_specs, d.sc_res, d.sc_size
        self.sc_goals = sorted({k.split(":", 3)[3] for k in S})
        g = self.sc_goals

        def pre(gg, m):
            v = 0
            for k in SC_KS:
                if Rr[f"scale:{m}:{k}:{gg}"]["outcome"] != "proved":
                    break
                v = k
            return v if Rr["scale:none:0:" + gg]["outcome"] == "proved" else None
        self.feas = {m: [pre(x, m) for x in g] for m in ("random", "near")}
        self.sc_exp = {m: med([sc_exponent(d, x, m) for x in g]) for m in ("random", "near")}
        self.sc_eq = sc_eq_split(d, g)
        self.sc_exp_eq = {name: {m: med([sc_exponent(d, x, m) for x in gs]) for m in ("random", "near")} for name, gs in self.sc_eq}
        self.sc_growth32 = med([Z[f"scale:{m}:32:{x}"]["clauses"] / Z["scale:none:0:" + x]["clauses"] for m in ("random", "near") for x in g])
        cr = [Z[k]["clauses"] for k in Rr if Rr[k]["outcome"] == "crash"]
        pr = [Z[k]["clauses"] for k in Rr if Rr[k]["outcome"] == "proved"]
        self.cap = (min(cr), max(pr))
        self.sc_oc = collections.Counter(r["outcome"] for r in Rr.values())
        self.bucket_feas = {}
        for b in SC_BUCKETS:
            gs = [x for x in g if S["scale:none:0:" + x]["bucket"] == b]
            self.bucket_feas[b] = (len(gs), med([self.feas["near"][g.index(x)] for x in gs]), med([self.feas["random"][g.index(x)] for x in gs]))
        self.pool_eq = (sum(1 for p in d.pool if "c:Eq" in p["heads"]), len(d.pool))
        # E5
        self.e5 = None
        if d.m8 and d.m8_facts:
            self.e5 = {}
            for t in "AB":
                ks = m8_population(d, t)
                cb = collections.Counter(frozenset(m8_family(d, x) for x in m8_obstacles(d, k)) for k in ks)
                self.e5[t] = (len(ks), cb)


def e5_count(F, t, fams):
    return F.e5[t][1].get(frozenset(fams), 0) if F.e5 else None


def p1(a, b):
    return 100 * a / b if b else 0.0


def summary(d, F):
    """§10.10 decision 3: Q1–Q4 of EVAL_PLAN §1, in numbers, each pointing to its table."""
    nA, nB = F.n["A"], F.n["B"]
    r2B, r2A = F.r2["B"], F.r2["A"]
    out = ["## Summary: answers to Q1–Q4 (EVAL_PLAN §1)", ""]
    out.append(f"- **Q1 Coverage.** With oracle H (`H_main`) and N ≤ 10, `solve_by_sat` proves {F.proved['B']:,} of {nB:,} Tier B "
               f"goals ({pct(F.proved['B'], nB)}) and {F.proved['A']:,} of {nA:,} Tier A goals ({pct(F.proved['A'], nA)}). Among goals "
               f"whose statement and every `H_main` constant the compiler accepts, it proves {F.proved_hfull['B']:,} of "
               f"{len(F.hfull['B']):,} in Tier B ({pct(F.proved_hfull['B'], len(F.hfull['B']))}) and {F.proved_hfull['A']:,} of "
               f"{len(F.hfull['A']):,} in Tier A ({pct(F.proved_hfull['A'], len(F.hfull['A']))}). Proofs are small: the median N is "
               f"{fn(med(F.Ns['B']))} in Tier B and {fn(med(F.Ns['A']))} in Tier A, and "
               f"{pct(sum(1 for n in F.Ns['B'] if n <= 2), len(F.Ns['B']))} of Tier B proofs have N ≤ 2. (R1, R3)")
    out.append(f"- **Q2 Why not.** The compiler's rejection of an `H_main` constant (reason 2) is the primary reason for "
               f"{F.notp['B'][REASONS[1]]:,} of the {sum(F.notp['B'].values()):,} unproved Tier B goals "
               f"({pct(F.notp['B'][REASONS[1]], sum(F.notp['B'].values()))}) and {F.notp['A'][REASONS[1]]:,} of "
               f"{sum(F.notp['A'].values()):,} in Tier A ({pct(F.notp['A'][REASONS[1]], sum(F.notp['A'].values()))}). In "
               f"{pct(r2B[1]['clause variable applied to arguments'], len(r2B[0]))} of Tier B's reason 2 goals a constant is rejected "
               f"because a clause variable is applied to arguments; `congrArg` alone is rejected in {r2B[2]['congrArg']:,} of them "
               f"({pct(r2B[2]['congrArg'], len(r2B[0]))}), and in Tier A in {r2A[2]['congrArg']:,} ({pct(r2A[2]['congrArg'], len(r2A[0]))}). "
               f"Next come unexplained goals ({F.notp['B'][REASONS[5]]:,} in Tier B; in review mostly definitional unfolding at a "
               f"proof position), goal rejection ({F.notp['B'][REASONS[0]]:,}) and elimination constants ({F.notp['B'][REASONS[2]]:,}). "
               "(R2, its breakdown, E5)")
    se = F.syn_exp
    out.append(f"- **Q3 Typed scaling.** On the synthetic families, the growth exponent of total clauses in k (8 to 32, all "
               f"refinements on) is {min(se['S']):.2f}–{max(se['S']):.2f} for S, {min(se['T1']):.2f}–{max(se['T1']):.2f} for T1, "
               f"{min(se['T2']):.2f}–{max(se['T2']):.2f} for T2 and {min(se['T3']):.2f}–{max(se['T3']):.2f} for T3; groundness plus "
               f"decomposition is still {min(F.syn_gd['S']):.0f}–{max(F.syn_gd['S']):.0f}% of the clauses at k = 32 in S, and "
               f"{min(F.syn_gd['T2']):.0f}–{max(F.syn_gd['T2']):.0f}% in T2, the only family where typing acts. With real "
               f"distractors, the median per-goal exponent is {F.sc_exp['random']:.2f} (random) and {F.sc_exp['near']:.2f} (near), "
               f"clauses at k = 32 are about {F.sc_growth32:,.0f} times those at k = 0, and the median largest feasible k is "
               f"{fn(med(F.feas['random']))} (random) and {fn(med(F.feas['near']))} (near); every infeasible run hit the memory "
               f"cap (about {F.cap[0] / 1e6:.1f}–{F.cap[1] / 1e6:.1f} M clauses) or, twice, a timeout. (R5, E6, R6)")
    tB, tA = F.time["B"], F.time["A"]
    out.append(f"- **Q4 Baselines.** Like-for-like `solve_by_elim` closes {F.sbe['B']:,} Tier B goals ({pct(F.sbe['B'], nB)}) and "
               f"{F.sbe['A']:,} Tier A goals ({pct(F.sbe['A'], nA)}). Of `solve_by_sat`'s proofs it also finds {F.both['B']:,} of "
               f"{F.proved['B']:,} in Tier B ({pct(F.both['B'], F.proved['B'])}) and {F.both['A']:,} of {F.proved['A']:,} in Tier A "
               f"({pct(F.both['A'], F.proved['A'])}). On goals both close, the median time is {fn(tB[0])} ms against {fn(tB[1])} ms "
               f"(Tier B) and {fn(tA[0])} ms against {fn(tA[1])} ms (Tier A). `exact?` closes {F.exact_b:,} Tier B goals with "
               f"another library lemma ({pct(F.exact_b, nB)}), {F.exact_both_b:,} of them also proved by `solve_by_sat`. (R4, E4)")
    return out


def reading(d, F):
    """§10.10 decision 2: each rule of EVAL_PLAN §7, its condition, the numbers, and whether it holds. No recommendation."""
    nB = F.n["B"]
    pB = p1(F.proved["B"], nB)
    r2B, r2A = F.r2["B"], F.r2["A"]
    nrB, nrA = sum(F.notp["B"].values()), sum(F.notp["A"].values())
    out = ["## Reading the results (EVAL_PLAN §7)", "",
           "Each rule of §7 with its condition, the numbers it rests on, and whether it holds. §7's thresholds are "
           "indicative. This section does not choose between scope and scale: the owner decides after 7d-2 (§10.11).", ""]
    # rule 1
    one_r = (r2B[1]["clause variable applied to arguments"], len(r2B[0]))
    out += ["### Rule 1: scope first", "",
            "*Condition:* under about 20% of Tier B goals are proved with oracle H, **and** R2 is dominated by one or two "
            "reasons that a targeted extension could address. R2 then names the extension.", "",
            f"- *Proved share, Tier B:* {F.proved['B']:,} of {nB:,}, **{pB:.1f}%**, against about 20%: "
            f"{pB - 20:.1f} percentage points above the threshold ({F.proved['B'] - 600:,} goals more than 20% would be). "
            f"Tier A is at {pct(F.proved['A'], F.n['A'])}.",
            f"- *Dominance:* reason 2 is {pct(F.notp['B'][REASONS[1]], nrB)} of Tier B's unproved goals and "
            f"{pct(F.notp['A'][REASONS[1]], nrA)} of Tier A's. Within it, one rejection reason, a clause variable applied to "
            f"arguments, occurs in {pct(*one_r)} of Tier B's goals ({one_r[0]:,} of {one_r[1]:,}) and "
            f"{pct(r2A[1]['clause variable applied to arguments'], len(r2A[0]))} of Tier A's. One constant, `congrArg`, is rejected "
            f"in {pct(r2B[2]['congrArg'], len(r2B[0]))} of Tier B's reason 2 goals; it alone blocks "
            f"{r2B[3]['congrArg']:,} of the {sum(r2B[3].values()):,} goals blocked by a single constant.",
            ]
    if F.e5:
        a3B, a3A = e5_count(F, "B", ["3A"]), e5_count(F, "A", ["3A"])
        out.append(f"- *The extension R2 names:* rewriting by first-order equality rules (family 3A of the milestone 8 proposal). "
                   f"In E5, {a3B:,} of Tier B's {F.e5['B'][0]:,} accepted, unproved goals ({pct(a3B, F.e5['B'][0])}) and {a3A:,} of "
                   f"Tier A's {F.e5['A'][0]:,} ({pct(a3A, F.e5['A'][0])}) have only 3A obstacles. "
                   f"Only {e5_count(F, 'B', ['1']):,} and {e5_count(F, 'B', ['2']):,} Tier B goals have only family 1 or only family 2 "
                   "obstacles. E5 is an upper bound: removing the obstacles does not make a goal provable.")
    out += [f"- *Holds?* **Only in part.** The dominance condition holds clearly. The proved-share condition does not: Tier B is "
            f"{pB - 20:.1f} points above the indicative 20%.", ""]
    # rule 2
    near_med, rnd_med = med(F.feas["near"]), med(F.feas["random"])
    n32 = {m: sum(1 for v in F.feas[m] if v == 32) for m in ("random", "near")}
    lt16 = {m: sum(1 for v in F.feas[m] if v is not None and v < 16) for m in ("random", "near")}
    ng = len(F.sc_goals)
    out += ["### Rule 2: scale first", "",
            "*Condition:* a fair share of goals is in the class, **and** R6 shows the feasible k falling well short of what premise "
            "selection would supply (tens of lemmas): in-class goals become infeasible around k = 16 to 32 with near distractors.", "",
            f"- *Share in the class:* {pB:.1f}% of Tier B goals are proved; {pct(F.proved_hfull['B'], len(F.hfull['B']))} of those "
            f"whose goal and `H_main` are fully accepted; {F.inclass[0]:,} Tier B goals ({pct(F.inclass[0], nB)}) are oracle-in-class "
            f"(R7), and {F.inclass[1]:,} of them are proved. §7 gives no number for \"a fair share\".",
            f"- *Feasible k with near distractors* ({ng} proved goals, R6): median largest feasible k **{fn(near_med)}**; "
            f"{lt16['near']} of {ng} goals are infeasible before k = 16, and {n32['near']} are feasible at every k up to 32. With "
            f"random distractors: median {fn(rnd_med)}, {lt16['random']} before 16, {n32['random']} up to 32.",
            "- *By original N* (median largest feasible k, near / random): "
            + "; ".join(f"N {b.replace('-', '–').replace('+', ' or more')}: {fn(v[1])} / {fn(v[2])} ({v[0]} goals)"
                        for b, v in F.bucket_feas.items()) + ".",
            f"- *Cause:* of the {sum(F.sc_oc.values()) - F.sc_oc.get('proved', 0)} runs that are not proved, "
            f"{F.sc_oc.get('crash', 0)} hit the 2.5 GB cap and {F.sc_oc.get('timeout', 0)} a timeout; none ran out of N. The cap "
            f"falls at about {F.cap[0] / 1e6:.1f}–{F.cap[1] / 1e6:.1f} M clauses, and clauses at k = 32 are a median "
            f"{F.sc_growth32:,.0f} times those at k = 0.",
            f"- *Holds?* **The R6 condition holds:** the median feasible k is at or below the rule's 16–32 range, and lower for "
            f"larger N. §7 sets no threshold for \"a fair share\", so that part is the owner's to judge. Caveat on near: for {len(F.sc_eq[0][1])} of the {ng} goals S contains `c:Eq` and near is close to random "
            f"({pct(*F.pool_eq)} of the pool has an `Eq` head; threats below).", ""]
    # rule 3
    se, sg = F.syn_exp, F.syn_gd
    out += ["### Rule 3: scale is less urgent than SPEC 7.3 suggests", "",
            "*Condition:* the typed families show a growth exponent near 1, **or** pruning removes most of groundness and "
            "decomposition.", "",
            "- *Growth exponent* (k = 8 to 32, all refinements on, over N = 5, 8, 12): "
            + ", ".join(f"{fa} {rng(se[fa], '.2f')}" for fa in SYN_FAMS)
            + f". Real distractors: median per-goal {F.sc_exp['random']:.2f} (random), {F.sc_exp['near']:.2f} (near). Only T2 is near 1.",
            "- *Groundness plus decomposition at k = 32*, all refinements on: "
            + ", ".join(f"{fa} {rng(sg[fa], '.0f')}%" for fa in SYN_FAMS)
            + ". With all refinements on, groundness and decomposition are still most of the clauses in every family except T2.",
            "- *Holds?* **No**, except in T2, the family with distinct carrier types, where both parts hold in part (E6 separates "
            "the two typing filters).", ""]
    # rule 4
    tB, tA = F.time["B"], F.time["A"]
    so = F.rev.get("sbs_only")
    out += ["### Rule 4: value against baselines", "",
            "*Condition:* `solve_by_elim` with the same H proves nearly everything `solve_by_sat` proves, and faster. Then the "
            "tactic's distinctive contributions are minimal proofs and certified \"no proof with at most N nodes\" answers, and "
            "R4 should single out the goals where `solve_by_elim` fails and `solve_by_sat` succeeds, and say why.", "",
            f"- *Tier B:* like-for-like `solve_by_elim` closes {F.both['B']:,} of `solve_by_sat`'s {F.proved['B']:,} proofs "
            f"({pct(F.both['B'], F.proved['B'])}); on them its median time is {fn(tB[1])} ms against {fn(tB[0])} ms, and "
            f"`solve_by_sat` is faster on {tB[2]:,} of {tB[3]:,}. It also closes {F.sbe['B'] - F.both['B']:,} goals "
            "`solve_by_sat` does not prove (E1).",
            f"- *Tier A:* {F.both['A']:,} of {F.proved['A']:,} ({pct(F.both['A'], F.proved['A'])}), median {fn(tA[1])} ms against "
            f"{fn(tA[0])} ms. The like-for-like baseline's single depth budget handicaps it on Tier A (§10.9; threats below).",
            (f"- *R4's single-out:* {so[0]} goals that only `solve_by_sat` proves, all reviewed: "
             + ", ".join(f"{c} {v}" for c, v in so[1].most_common())
             + ". Most of the \"other, explained\" ones use an `↔` or `∧` projection, a built-in rule of `solve_by_sat` that "
             "like-for-like `solve_by_elim` cannot build from `H_main` (§10.9)." if so else "- *R4's single-out:* not reviewed."),
            f"- *Certified answers:* {F.nop['B']:,} Tier B and {F.nop['A']:,} Tier A goals end with \"no proof with at most 10 "
            "nodes\" over the compiled fragment. §8's bounded-failure caveat applies: this is not \"outside the class\".",
            "- *Holds?* **Yes for Tier B; not for Tier A**, where the baseline's step budget is a confound.", ""]
    # where the rules disagree
    out += ["### Where the rules point different ways", "",
            f"- Rules 1 and 2 are not exclusive, and the data meet parts of both. Rule 1's dominance condition holds strongly "
            f"(one rejection reason, one constant), but its threshold is missed: Tier B's {pB:.1f}% is above about 20%. "
            f"Rule 2's R6 condition holds: the median goal is infeasible before k = 16 with near distractors.",
            f"- They measure different populations. Rule 1 counts the {nrB:,} unproved Tier B goals. Rule 2 rests on {ng} goals that "
            "are already proved, chosen by proved N, and on oracle H plus distractors, not on premise selection.",
            "- Rule 3 does not hold, which agrees with rule 2: SPEC 7.3's growth of about k² is what the real data show.",
            "- Rule 4 holds for Tier B: nearly every goal `solve_by_sat` proves, the baseline also closes, faster. Rules 1 "
            "and 2 are about the tactic alone. `solve_by_elim` was not run with distractors, so how the baseline behaves as "
            "H grows (rule 2's axis) is not measured.", ""]
    return out


def threats(d, F):
    """§10.10 decision 8: EVAL_PLAN §8 restated with what the data show."""
    so = F.rev.get("sbs_only")
    depth = so[1].get("depth", 0) if so else 0
    out = ["## Threats to validity (EVAL_PLAN §8, with the data)", ""]
    out.append(f"- **Oracle H is optimistic.** It assumes premise selection is solved. R6 measures the cost side only: with k "
               f"distractors, the median largest feasible k is {fn(med(F.feas['random']))} (random) and {fn(med(F.feas['near']))} "
               f"(near) on {len(F.sc_goals)} proved goals. Whether a selector would put the right lemmas in its top k is not measured.")
    out.append(f"- **\"Near\" is close to random when S contains `c:Eq`.** That is {len(F.sc_eq[0][1])} of the {len(F.sc_goals)} "
               f"scaling goals, and {pct(*F.pool_eq)} of the pool ({F.pool_eq[0]:,} of {F.pool_eq[1]:,}) has an `Eq` head. The median "
               f"per-goal exponent is {F.sc_exp_eq[F.sc_eq[0][0]]['random']:.2f} / {F.sc_exp_eq[F.sc_eq[0][0]]['near']:.2f} "
               f"(random / near) with `c:Eq` and {F.sc_exp_eq[F.sc_eq[1][0]]['random']:.2f} / {F.sc_exp_eq[F.sc_eq[1][0]]['near']:.2f} "
               f"without, on {len(F.sc_eq[1][1])} goals (R6). For most goals, then, R6's near mode is not the harder test §4.2 intended.")
    nm = F.n["A"] + F.n["B"]
    cm = F.crash["A"] + F.crash["B"]
    out.append(f"- **One machine, one memory cap.** {cm:,} of the {nm:,} main-run goals ({pct(cm, nm)}; Tier A {F.crash['A']:,}, "
               f"Tier B {F.crash['B']:,}) crashed at the 2.5 GB cap and are unmeasured: they may or may not have a proof with "
               f"N ≤ 10. With R1b, {F.crash_all:,} of {len(d.specs):,} runs ({pct(F.crash_all, len(d.specs))}). In R6 every "
               f"infeasible run but two is a crash. Another cap or machine moves these numbers; it does not change a CNF.")
    out.append(f"- **The like-for-like baseline's step budget.** `maxDepth := 10` is one budget for the whole search, and a Tier A "
               f"goal pays a step for every binder of its statement (§10.9). {depth} of the {so[0] if so else 0} goals only "
               "`solve_by_sat` proves are lost to depth, almost all in Tier A. Tier A's baseline comparison understates "
               "`solve_by_elim`.")
    r2B = F.r2["B"]
    out.append(f"- **Elaborated `simp` proofs inflate the rewriting obstacles.** Tier B goals come from elaborated terms, where "
               f"`simp` leaves `congrArg`, `of_eq_true`, `propext` and `congr` chains: `congrArg` is rejected in {r2B[2]['congrArg']:,} "
               f"Tier B goals, `of_eq_true` in {r2B[2]['of_eq_true']:,}, `propext` in {r2B[2]['propext']:,}. A user's proof with "
               "rewriting lemmas would not use these constants, and a proof through them may need many nodes. R2's breakdown and "
               "E5 count obstacles in the oracle term, not in the shortest proof.")
    out.append(f"- **Core proofs are tactic-heavy.** Tier A proves {pct(F.proved['A'], F.n['A'])} against Tier B's "
               f"{pct(F.proved['B'], F.n['B'])}; Tier A's statements are whole theorems whose proofs need tactics.")
    out.append("- **Core only.** Without Mathlib, goals about the algebraic hierarchy, where instances matter most, are "
               f"under-represented. Even so, in R7's review instances are the most common reason an oracle-in-class goal has no "
               f"proof ({F.rev['r7_soft_completeness'][1].most_common(1)[0][1] if 'r7_soft_completeness' in F.rev else '?'} of "
               f"{F.rev['r7_soft_completeness'][0] if 'r7_soft_completeness' in F.rev else '?'}).")
    out.append(f"- **Bounded failure.** {F.nop['B']:,} Tier B and {F.nop['A']:,} Tier A goals have no proof with N ≤ 10. That "
               "does not put them outside the class.")
    out.append(f"- **R6's sample.** {len(F.sc_goals)} goals, all proved in the main run, drawn by proved N (12, 12, 13, 13). "
               "Goals with larger N have smaller feasible k (median 32 at N = 1, 4 at N ≥ 5), and most proved main-run goals "
               "have N = 1, so the per-goal median is not a median over proved goals.")
    out.append("- **E5 is an upper bound.** Removing every obstacle does not make a goal provable: definitional unfolding, "
               "instances and proof size can still block it. The family table is a judgment, fixed before counting.")
    return out


def checks(d):
    num = [d.num.get(d.specs[k]["id"]) for k in d.keys("main")]
    nmiss = sum(1 for x in num if x is None)
    cut = sum(1 for x in num if x and x.get("cut"))
    err = sum(1 for x in num if x and "error" in x)
    skipped = sum(x.get("skipped", 0) for x in num if x)
    checked = sum(x.get("checked", 0) for x in num if x)
    rows = [list(c) for c in d.checks] + [
        ["rule 4 annotation (corpus_numerals): goals missing / with an error / walk cut at the budget",
         f"{nmiss:,} / {err:,} / {cut:,}"],
        ["rule 4: positions checked / skipped (expected type not computable, or a runtime limit)", f"{checked:,} / {skipped:,}"],
        ["eval/full/ result lines (before) / specs", f"{len(d.before):,} / {len(d.specs):,}"],
    ]
    fk = collections.Counter(r["key"] for r in d.final_lines)
    rows += [
        ["eval/final/: lines / specs; keys with exactly one line; missing; duplicated; not in the specs",
         f"{len(d.final_lines):,} / {len(d.specs):,}; {sum(1 for k in d.specs if fk.get(k) == 1):,}; "
         f"{sum(1 for k in d.specs if k not in fk):,}; {sum(1 for v in fk.values() if v > 1):,}; "
         f"{sum(1 for k in fk if k not in d.specs):,}"],
        ["eval/final/: lines without a `code_version`", f"{sum(1 for r in d.final_lines if 'code_version' not in r):,}"],
        ["eval/final/: lines by `code_version` (source, commit)",
         ", ".join(f"{a} {b}: {v:,}" for (a, b), v in sorted(collections.Counter(
             (r["code_version"]["source"], r["code_version"]["commit"]) for r in d.final_lines if "code_version" in r).items()))],
        ["eval/final/: rerun lines are exactly the `changed` keys of the rerun set",
         "yes" if {r["key"] for r in d.final_lines if r.get("code_version", {}).get("source") == "rerun"}
         == {k for k, v in d.rerun_set.items() if v == "changed"} else "NO"],
    ]
    return ["## Data checks", "", table(["check", "result"], rows)]


def main():
    d = Data()
    if sys.argv[1:] == ["samples"]:
        os.makedirs(os.path.join(E, "reviews"), exist_ok=True)
        for name, (pop, smp, seed) in review_sets(d).items():
            with open(os.path.join(E, "reviews", f"{name}.sample.txt"), "w") as f:
                f.write(f"# {name}: population {len(pop)}, sample {len(smp)}, seed {seed}\n")
                for k in smp:
                    f.write(k + "\n")
            print(f"{name}: population {len(pop)}, sample {len(smp)}")
        print("review | seed | population | sample | kept from before | kept, forest changed | new | forest changed in sample | old sample size")
        for row in sample_comparison(d):
            print(" | ".join(str(x) for x in row))
        return
    h = json.load(open(os.path.join(E, "full", "header.json")))
    hr = json.load(open(os.path.join(E, "rerun", "header.json")))
    segs = collections.Counter(r["code_version"]["commit"] for r in d.final_lines if r["code_version"]["source"] == "full")
    F = Facts(d)
    out = ["# Solve By SAT: evaluation results (milestone 7)", "",
           "Generated by `eval/report.py` from the data files alone: `eval/final/` (the full 7b run merged with the 10.7 "
           "rerun), `eval/full/`, `eval/rerun/`, the corpus files, the 7c scaling data and the 7d-2 files (E5's family "
           "table and constant facts, E6's counts). The reading of EVAL_PLAN §7 states facts against each rule; it does not "
           "choose between scope and scale.", ""]
    out += summary(d, F) + [""]
    out += ["## The runs", "",
           f"**Full run (7b, `eval/full/`).** {h['n_specs']:,} goals, Lean {h['toolchain']}, N ≤ {h['nmax']}, "
           f"solver {h['solver_s']} s per call, N loop {h['loop_s']} s, memory cap {h['cap_mb']:,} MB, "
           f"P = {h['parallel_shards']}, baselines {h['baseline_heartbeats']:,} heartbeats; test machine "
           f"{h['machine']['cpu']}, {h['machine']['ram_mib']:,} MiB, kernel {h['machine']['kernel']}. Three commits "
           f"wrote it: `c3a3ec8` (the start commit, recorded in the header as `{h['git_commit'][:7]}`; "
           f"{segs.get('c3a3ec8', 0):,} final lines), `2394acf` (first decoder fix, R1; {segs.get('2394acf', 0):,}) and "
           f"`f35c182` (second decoder fix, R2; {segs.get('f35c182', 0):,}). The decoder fixes change results only on "
           "goals whose CNF is satisfiable (NOTES.md, 7b).", "",
           f"**Rerun (§10.7, `eval/rerun/`).** {hr['n_specs']:,} goals ({sum(1 for v in d.rerun_set.values() if v == 'changed'):,} "
           f"whose compiled forest changed with the type-template fix, {sum(1 for v in d.rerun_set.values() if v == 'spot'):,} "
           f"spot-check goals), SAT phase only, commit `{hr['git_commit'][:7]}`, the same limits and P = "
           f"{hr['parallel_shards']}; the same test machine ({hr['machine']['cpu']}, {hr['machine']['ram_mib']:,} MiB). "
           f"Goals 1–123 ran under kernel {hr['machine']['kernel']}; a power loss stopped the run, and after it the machine "
           "booted only with kernel 7.3.5 and changed boot parameters, under which the remaining goals ran. That can change "
           "times, not CNFs (NOTES.md, \"10.7: the rerun on the test machine\"). Every final line records its "
           "`code_version`.", ""]
    out += effect(d) + [""]
    out += r1(d) + [""] + r1b(d) + [""] + r2(d) + [""] + r3(d) + [""] + r4(d) + [""]
    out += r5(d) + [""] + r6(d) + [""]
    out += r7(d) + [""] + reading(d, F) + threats(d, F) + [""] + checks(d) + [""] + exploratory(d) + [""] + e5(d)
    open(os.path.join(ROOT, "EVAL.md"), "w").write("\n".join(out) + "\n")
    print("wrote EVAL.md")


if __name__ == "__main__":
    main()
