#!/usr/bin/env python3
"""Milestone 7d-1: generate EVAL.md from the 7b data alone (EVAL_PLAN §6, §10.6, §10.7, §10.8).

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
  reviews/*.jsonl                        the hand reviews (7d-1 step 3, redrawn after the merge).
                                         `*.evidence.jsonl` files are review evidence, not reviews.
                                         reviews/before_fix/ holds the reviews of the samples drawn
                                         before the fix; nothing in it is read or counted here.
Only the standard library is used; there are no charts (matplotlib is not installed).
"""
import collections, json, os, random, re, statistics, sys

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
    rd = d.reviews.get("r2_unexplained")
    if rd:
        out += review_summary(d, "r2_unexplained", rd, "Hand review of unexplained goals (§3.3)")
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
    out = ["# Solve By SAT: evaluation results (milestone 7, stage 7d-1)", "",
           "Generated by `eval/report.py` from `eval/final/` (the full 7b run merged with the 10.7 rerun), "
           "`eval/full/`, `eval/rerun/` and the corpus files alone. Facts and counts only: the reading of "
           "EVAL_PLAN §7 comes in 7d-2, after 7c.", "",
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
    out += ["## R5 Synthetic scaling", "", "*Pending 7c.*", "", "## R6 Real distractors", "", "*Pending 7c.*", ""]
    out += r7(d) + [""] + checks(d) + [""] + exploratory(d)
    open(os.path.join(ROOT, "EVAL.md"), "w").write("\n".join(out) + "\n")
    print("wrote EVAL.md")


if __name__ == "__main__":
    main()
