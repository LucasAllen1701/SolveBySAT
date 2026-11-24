#!/usr/bin/env python3
"""Milestone 8c-1 (M8_PLAN.md 4.4): generate eval/m8c1/SCALE.md from the data files alone. Facts only:
reading them, and choosing what 8c-2 builds, is for the claude.ai project.

  python3 eval/m8c1/report.py

Inputs: eval/m8c1/{sizes_N5,sizes_N10,diag_N5}/, eval/m8c1/rerun/, eval/m8c1/models/, eval/m8b/specs_points.jsonl,
eval/m8b/points/sections.jsonl (8b's counts), eval/m8a/full/ (8a's runs and sizes), eval/m8a/specs.jsonl.
Pooled figures sum over the points; per-point figures are medians (and quartiles) of per-point values.
A size comparison between settings uses only the points that completed in every setting compared.
Only the standard library is used; output is sorted throughout.
"""
import collections, json, os, statistics

D = os.path.dirname(os.path.abspath(__file__))
R = os.path.dirname(os.path.dirname(D))
VARIANTS = [("rules", "with the 8a rules"), ("norules", "milestone 7's H, no rules")]
SETTINGS = [("off", "both flags off"), ("r1", "R1 on"), ("r1r2", "R1 and R2 on")]
UNITS = "11 node bounds"
FAMS = ["1 node assignment", "2 tree shape", "3 context (local hypotheses, ancestors)", "4 matching",
        "5 decomposition", "6 links (environment copies)", "7 eigenvariables, occurs check, scope", "8 groundness",
        "10 symmetry breaking", UNITS]
GROUPS = [("rewrite_B", "rewriting, Tier B"), ("rewrite_A", "rewriting, Tier A"), ("control", "control")]


def load(p):
    out = []
    if os.path.exists(p):
        for l in open(p):
            l = l.strip()
            if l:
                try:
                    out.append(json.loads(l))
                except json.JSONDecodeError:
                    pass
    return out


def fmt(x):
    if isinstance(x, float):
        return f"{int(x):,}" if x.is_integer() else f"{x:,.2f}"
    return f"{x:,}" if isinstance(x, int) else str(x)


def table(head, rows):
    return (["| " + " | ".join(head) + " |", "| " + " | ".join("---" for _ in head) + " |"]
            + ["| " + " | ".join(fmt(x) for x in r) + " |" for r in rows])


def pct(a, b):
    return f"{100 * a / b:.1f}%" if b else "–"


def quart(xs):
    """median [q1, q3] of a list, as text."""
    if not xs:
        return "–"
    xs = sorted(xs)
    if len(xs) < 4:
        return f"{statistics.median(xs):.2f}"
    q = statistics.quantiles(xs, n=4)
    return f"{q[1]:.2f} [{q[0]:.2f}, {q[2]:.2f}]"


def ratio(a, b):
    return f"{a / b:.2f}×" if b else "–"


def variant(key):
    return key.split(":")[1]


def sizes_section(n, out):
    rs = load(os.path.join(D, f"sizes_N{n}", "results.jsonl"))
    out += [f"## Sizes at N = {n}", ""]
    if not rs:
        out += ["No data.", ""]
        return {}
    by = collections.defaultdict(dict)   # point -> setting -> record
    for r in rs:
        p, s = r["key"].split("|")
        by[p][s] = r
    t = os.path.join(D, f"sizes_N{n}", "timing.json")
    if os.path.exists(t):
        tm = json.load(open(t))
        out += [f"Wall time {tm['wall_s'] / 3600:.2f} h for {tm['n']} (point, setting) records"
                f"{'' if tm.get('finished') else ' (not finished)'}.", ""]
    # status per setting
    rows = []
    for v, vl in VARIANTS:
        for s, sl in SETTINGS:
            c = collections.Counter(by[p][s]["status"] for p in by if variant(p) == v and s in by[p])
            ee = sum(1 for p in by if variant(p) == v and by[p].get(s, {}).get("early_exit"))
            rows.append([vl, sl, sum(c.values()), c.get("ok", 0), c.get("memout", 0), c.get("crash", 0), ee])
    out += ["### Records", ""] + table(["points", "setting", "records", "ok", "memout", "crash", "early exit"], rows) + [""]
    # pooled sizes on points complete in all three settings
    for v, vl in VARIANTS:
        pts = sorted(p for p in by if variant(p) == v and all(by[p].get(s, {}).get("status") == "ok" for s, _ in SETTINGS))
        out += [f"### Pooled, {vl} ({len(pts)} points complete in all three settings)", ""]
        if not pts:
            continue
        rows = []
        for f in ["total"] + FAMS:
            vals = []
            for s, _ in SETTINGS:
                vals.append(sum((by[p][s]["clauses"] if f == "total" else by[p][s]["families"].get(f, 0)) for p in pts))
            rows.append([f, vals[0], vals[1], vals[2], ratio(vals[0], vals[1]), ratio(vals[0], vals[2]),
                         ratio(vals[1], vals[2])])
        rows.append(["variables", *[sum(by[p][s]["vars"] for p in pts) for s, _ in SETTINGS],
                     ratio(sum(by[p]["off"]["vars"] for p in pts), sum(by[p]["r1"]["vars"] for p in pts)),
                     ratio(sum(by[p]["off"]["vars"] for p in pts), sum(by[p]["r1r2"]["vars"] for p in pts)),
                     ratio(sum(by[p]["r1"]["vars"] for p in pts), sum(by[p]["r1r2"]["vars"] for p in pts))])
        out += table(["clauses", "off", "R1", "R1 R2", "off / R1", "off / R1 R2", "R1 / R1 R2"], rows) + [""]
        # per-point ratios
        rows = []
        for f in ["total", "5 decomposition", "8 groundness", "4 matching", "6 links (environment copies)",
                  "7 eigenvariables, occurs check, scope"]:
            get = (lambda r: r["clauses"]) if f == "total" else (lambda r, f=f: r["families"].get(f, 0))
            r1 = [get(by[p]["off"]) / get(by[p]["r1"]) for p in pts if get(by[p]["r1"])]
            r2 = [get(by[p]["off"]) / get(by[p]["r1r2"]) for p in pts if get(by[p]["r1r2"])]
            r12 = [get(by[p]["r1"]) / get(by[p]["r1r2"]) for p in pts if get(by[p]["r1r2"])]
            rows.append([f, quart(r1), quart(r2), quart(r12), sum(1 for p in pts if get(by[p]["r1r2"]) == 0)])
        out += ["Per-point ratios, median [q1, q3]; points with a family emptied by R1 and R2 are left out of"
                " that family's ratios and counted in the last column:", ""]
        out += table(["clauses", "off / R1", "off / R1 R2", "R1 / R1 R2", "emptied (R1 R2)"], rows) + [""]
        # label width and objects
        rows = []
        for k in ["W", "IB", "rigid", "type_rigid", "full_pairs"]:
            rows.append([k, *[quart([by[p][s][k] for p in pts if not by[p][s].get("early_exit")]) for s, _ in SETTINGS]])
        rows.append(["R2: pairs skipped", "–", "–", quart([by[p]["r1r2"]["exclusive_skipped"] for p in pts])])
        rows.append(["R1: gp excluded / gp pairs", "–", quart([by[p]["r1"]["gp_excluded"] / by[p]["r1"]["gp_pairs"]
                                                             for p in pts if by[p]["r1"]["gp_pairs"]]), "–"])
        rows.append(["R1: cl excluded / cl pairs", "–", quart([by[p]["r1"]["cl_excluded"] / by[p]["r1"]["cl_pairs"]
                                                             for p in pts if by[p]["r1"]["cl_pairs"]]), "–"])
        out += ["Per point, median [q1, q3] (early exits left out of the first five rows):", ""]
        out += table(["", "off", "R1", "R1 R2"], rows) + [""]
        enc = [[by[p][s]["encode_ms"] / 1000 for p in pts] for s, _ in SETTINGS]
        out += [f"Encoding time (countOnly), pooled: off {sum(enc[0]):,.0f} s, R1 {sum(enc[1]):,.0f} s, "
                f"R1 R2 {sum(enc[2]):,.0f} s.", ""]
    # memouts
    mem = sorted((p, s) for p in by for s, _ in SETTINGS if by[p].get(s, {}).get("status") not in (None, "ok"))
    if mem:
        out += [f"Points that did not complete (point, setting, status): {len(mem)}", ""]
        out += table(["point", "setting", "status"], [[f"`{p}`", s, by[p][s]["status"]] for p, s in mem]) + [""]
    return by


def bound_section(by5, out):
    m4 = {j["key"]: j["data"] for j in load(os.path.join(R, "eval/m8b/points/sections.jsonl")) if j.get("section") == "m4"}
    out += ["## Checks of 4.4 at N = 5", ""]
    if not by5:
        out += ["No data.", ""]
        return
    rows = []
    for v, vl in VARIANTS:
        pts = sorted(p for p in by5 if variant(p) == v)
        off = [p for p in pts if by5[p].get("off", {}).get("status") == "ok"]
        eq = sum(1 for p in off if by5[p]["off"]["clauses"] == m4[p]["total_clauses"])
        rows.append([vl, "flags-off count equals 8b's total_clauses", f"{eq} of {len(off)}"])
        for s, sl in SETTINGS[1:]:
            ok = [p for p in pts if by5[p].get(s, {}).get("status") == "ok"]
            within = sum(1 for p in ok if by5[p][s]["clauses"] - by5[p][s]["families"].get(UNITS, 0)
                         <= m4[p]["total_clauses"] - m4[p]["groundness_dead"] - m4[p]["decomposition_dead"])
            rows.append([vl, f"{sl}: clauses less R1's units within 8b's total less the dead shares", f"{within} of {len(ok)}"])
            got = sum(by5[p][s]["clauses"] - by5[p][s]["families"].get(UNITS, 0) for p in ok)
            bnd = sum(m4[p]["total_clauses"] - m4[p]["groundness_dead"] - m4[p]["decomposition_dead"] for p in ok)
            rows.append([vl, f"{sl}: pooled, clauses less units / bound", f"{got:,} / {bnd:,} ({pct(got, bnd)})"])
            gx = sum(1 for p in ok if by5[p][s]["gp_excluded"] >= m4[p]["gp_excluded"]
                     and by5[p][s]["cl_excluded"] >= m4[p]["cl_excluded"])
            rows.append([vl, f"{sl}: excluded gp and cl pairs at least 8b's", f"{gx} of {len(ok)}"])
            more = sum(by5[p][s]["gp_excluded"] + by5[p][s]["cl_excluded"] - m4[p]["gp_excluded"] - m4[p]["cl_excluded"]
                       for p in ok)
            rows.append([vl, f"{sl}: excluded pairs beyond 8b's (e(c) and the built-in rule)", more])
    out += table(["points", "check", "result"], rows) + [""]


def models_section(out):
    out += ["## The scope term e(c) on models (4.4)", ""]
    rows = []
    for f, label in [("m8a", "64 proved 8a runs"), ("named", "named cases with a proof")]:
        rs = load(os.path.join(D, "models", f"{f}.jsonl"))
        rows.append([label, len(rs), sum(1 for r in rs if r.get("proof") == "ok"), sum(r.get("pairs_used", 0) for r in rs),
                     sum(r.get("local_nodes", 0) for r in rs), sum(len(r.get("bound_violations", [])) for r in rs),
                     sum(len(r.get("bound_violations_e", [])) for r in rs)])
    out += table(["models", "re-solved", "proof kernel-checked", "gp and cl pairs used", "nodes applying a local clause",
                  "violations, 8b bounds", "violations, R1 bounds with e(c)"], rows) + [""]


def diag_section(out):
    sec = collections.defaultdict(dict)
    for r in load(os.path.join(D, "diag_N5", "sections.jsonl")):
        if "section" in r:
            sec[r["key"]][r["section"]] = r["data"]
    res = {r["key"]: r for r in load(os.path.join(D, "diag_N5", "results.jsonl"))}
    out += ["## M6 to M8 at N = 5, R1 and R2 on (3.9)", ""]
    if not res:
        out += ["No data.", ""]
        return
    c = collections.Counter(r["status"] for r in res.values())
    bad = sorted(k for k, s in sec.items() for n in ("m2", "m3", "r1") if n in s and
                 any(v is False for kk, v in s[n].items() if kk.startswith("check_")))
    out += [f"Points: {len(res)} ({', '.join(f'{k} {v}' for k, v in sorted(c.items()))}). Recount checks (groundness, "
            f"decomposition, R1's units, R2's skipped pairs equal to the encoder's): {len(bad)} failed.", ""]
    for v, vl in VARIANTS:
        pts = sorted(k for k in sec if variant(k) == v and "m3" in sec[k] and "m7" in sec[k])
        ee = sorted(k for k in sec if variant(k) == v and sec[k].get("r1", {}).get("early_exit"))
        out += [f"### {vl}: {len(pts)} points with every section ({len(ee)} early exits, no sections)", ""]
        if not pts:
            continue
        # M8: family shares
        tot = sum(sec[k]["m4"]["total_clauses"] for k in pts)
        fam = collections.Counter()
        for k in pts:
            fam.update(sec[k]["m4"]["families"])
        out += ["**M8: family shares after R1 and R2**, pooled (and the median per-point share):", ""]
        rows = [[f, fam[f], pct(fam[f], tot),
                 quart([sec[k]["m4"]["families"].get(f, 0) / sec[k]["m4"]["total_clauses"] for k in pts])]
                for f in sorted(fam, key=lambda f: -fam[f])]
        out += table(["family", "clauses", "pooled share", "per-point share"], rows) + [""]
        # M6: decomposition by kinds x level/term
        dt = sum(sec[k]["m3"]["total"] for k in pts)
        by = collections.Counter()
        for k in pts:
            for lab, x in sec[k]["m3"]["by"].items():
                by[lab] += x["clauses"]
        out += [f"**M6: decomposition by object kinds**, pooled over {dt:,} decomposition clauses:", ""]
        rows = [[lab[len("kinds:"):], by[lab], pct(by[lab], dt)] for lab in sorted(by, key=lambda l: (-by[l], l))
                if lab.startswith("kinds:")]
        out += table(["kinds of the pair | symbol class", "clauses", "share"], rows) + [""]
        rows = [[lab, by[lab], pct(by[lab], dt)] for lab in sorted(by, key=lambda l: (-by[l], l))
                if lab.startswith("symclass:") or lab.startswith("node:") and "|" not in lab]
        out += table(["class", "clauses", "share"], rows) + [""]
        top = collections.Counter()
        for k in pts:
            for s, x in sec[k]["m3"]["top_symbols"]:
                top[s] += x
        out += ["Largest symbols (each point's ten largest, pooled): " +
                ", ".join(f"`{s}` {pct(x, dt)}" for s, x in sorted(top.items(), key=lambda t: (-t[1], t[0]))[:8]) + ".", ""]
        # M6 for R3
        r3 = collections.Counter()
        for k in pts:
            for lab, x in sec[k]["m6_r3"]["by"].items():
                r3[lab] += x["clauses"]
        out += ["**M6 for R3**: the solved forms of the typing clauses (one per kept candidate with a typing clause), pooled:", ""]
        rows = [[lab, r3[lab]] for lab in sorted(r3)]
        out += table(["", "count"], rows) + [""]
        tc = r3.get("typing clauses", 0)
        if tc:
            out += [f"Per typing clause: {r3['equations:slot'] / tc:.2f} slot, {r3['equations:ground'] / tc:.2f} ground and "
                    f"{r3['equations:residual'] / tc:.2f} residual equations, {r3['residual objects'] / tc:.2f} residual "
                    f"objects; {pct(r3.get('typing clauses without residual', 0), tc)} need no residual object.", ""]
        # M6 for R4
        lam = [sec[k]["m6_r4"]["lambda"] for k in pts]
        over = sum(1 for x in lam if x is None)
        lamv = sorted(x for x in lam if x is not None)
        out += [f"**M6 for R4**: |Λ| per point (cap {sec[pts[0]]['m6_r4']['cap']:,}): median {quart(lamv)}, "
                f"max {max(lamv) if lamv else '–'}, over the cap {over}; |Λ₀| median {quart([sec[k]['m6_r4']['lambda0'] for k in pts])}; "
                f"level templates median {quart([sec[k]['m6_r4']['level_templates'] for k in pts])}; closure reached in "
                f"fewer than N rounds at {sum(1 for k in pts if sec[k]['m6_r4']['lambda'] is not None and sec[k]['m6_r4']['rounds'] < 5)} points.", ""]
        hist = collections.Counter()
        for x in lamv:
            b = 1
            while b < x:
                b *= 4
            hist[b] += 1
        out += table(["|Λ| at most", "points"], [[b, hist[b]] for b in sorted(hist)] + [["over the cap", over]]) + [""]
        # M7
        m7 = collections.Counter()
        m7s = collections.Counter()
        for k in pts:
            for lab, x in sec[k]["m7"]["by"].items():
                m7[lab] += x["clauses"]
                m7s[lab] += x["vars"]
        gt = sum(m7.values())
        out += [f"**M7: groundness by variable** (R5), pooled over {gt:,} groundness clauses:", ""]
        out += table(["variable", "groundness clauses", "share", "slots"],
                     [[lab, m7[lab], pct(m7[lab], gt), m7s[lab]] for lab in sorted(m7, key=lambda l: (-m7[l], l))]) + [""]


def rerun_section(out):
    out += ["## The rerun of 8a with R1 and R2 on (4.4)", ""]
    new = {r["key"]: r for r in load(os.path.join(D, "rerun", "results.jsonl"))}
    old = {r["key"]: r for r in load(os.path.join(R, "eval/m8a/full/results.jsonl"))}
    specs = {s["key"]: s for s in load(os.path.join(R, "eval/m8a/specs.jsonl"))}
    if not new:
        out += ["No data.", ""]
        return
    tm = os.path.join(D, "rerun", "timing.json")
    if os.path.exists(tm):
        t = json.load(open(tm))
        out += [f"Wall time: runs {t['runs_s'] / 3600:.2f} h, sizes {t['sizes_s'] / 3600:.2f} h (8a: "
                f"{json.load(open(os.path.join(R, 'eval/m8a/full/timing.json')))['runs_s'] / 3600:.2f} h and "
                f"{json.load(open(os.path.join(R, 'eval/m8a/full/timing.json')))['sizes_s'] / 3600:.2f} h).", ""]
    stops = sorted((k, r["stop"]) for k, r in new.items() if r.get("stop"))
    out += [f"Runs: {len(new)} of {len(specs)}. Stops (4.4 exactness, 2.5): {len(stops)}." +
            "".join(f"\n- `{k}`: {m}" for k, m in stops), ""]

    def lastn(r):
        return r.get("N") if r.get("outcome") != "crash" else r.get("last_N")
    outs = ["proved", "no_proof_le_Nmax", "timeout", "memout", "crash", "limitation"]
    for grp, gl in [(None, "all runs")] + GROUPS:
        ks = sorted(k for k in new if grp is None or specs[k].get("probe_group") == grp)
        if not ks:
            continue
        tr = collections.Counter((old[k]["outcome"], new[k]["outcome"]) for k in ks)
        rows = [[o, *[tr.get((o, n), 0) for n in outs], sum(v for (a, _), v in tr.items() if a == o)] for o in outs]
        rows.append(["total", *[sum(v for (_, b), v in tr.items() if b == n) for n in outs], len(ks)])
        out += [f"### Outcomes, {gl}: 8a (rows) against the rerun (columns)", ""]
        out += table(["8a \\ rerun", *outs, "total"], rows) + [""]
    # goal by goal: changes
    rows = []
    for k in sorted(new):
        a, b = old[k], new[k]
        if (a["outcome"], lastn(a)) != (b["outcome"], lastn(b)):
            rows.append([f"`{specs[k]['id']}`", specs[k].get("probe_group", ""), f"{a['outcome']} {lastn(a)}",
                         f"{b['outcome']} {lastn(b)}", b.get("memout_kind", b.get("timeout_kind", ""))])
    out += [f"### Runs whose outcome or last N changed ({len(rows)} of {len(new)})", ""]
    out += table(["goal", "group", "8a: outcome, N", "rerun: outcome, N", "limit kind"], rows) + [""]
    # proved in 8a, ended at a resource limit before 8a's N in the rerun (recorded, not a stop)
    lim = [k for k in sorted(new) if old[k]["outcome"] == "proved" and new[k]["outcome"] in ("timeout", "memout", "crash")
           and (lastn(new[k]) or 0) <= old[k]["N"]]
    out += [f"Proved in 8a, rerun ended at a resource limit at or before 8a's N: {len(lim)}" +
            "".join(f"\n- `{specs[k]['id']}`: 8a N {old[k]['N']}, rerun {new[k]['outcome']} at N {lastn(new[k])}"
                    for k in lim), ""]
    # per-N rows where both answered the same N
    pairs = []
    for k in sorted(new):
        an = {x["N"]: x for x in old[k].get("per_N", [])}
        for x in new[k].get("per_N", []):
            y = an.get(x["N"])
            if y and y["result"] == x["result"] and x["result"] in ("unsat", "proved"):
                pairs.append((k, x, y))
    if pairs:
        ss = [(y["solve_s"], x["solve_s"]) for _, x, y in pairs]
        ee = [(y["encode_ms"], x["encode_ms"]) for _, x, y in pairs]
        cc = [(y["clauses"], x["clauses"]) for _, x, y in pairs]
        rows = [["(N, answer) pairs", len(pairs), "", ""],
                ["clauses, pooled", sum(a for a, _ in cc), sum(b for _, b in cc), ratio(sum(a for a, _ in cc), sum(b for _, b in cc))],
                ["encoding ms, pooled", sum(a for a, _ in ee), sum(b for _, b in ee), ratio(sum(a for a, _ in ee), sum(b for _, b in ee))],
                ["solving s, pooled", round(sum(a for a, _ in ss), 1), round(sum(b for _, b in ss), 1),
                 ratio(sum(a for a, _ in ss), sum(b for _, b in ss))],
                ["clauses, per-pair ratio 8a / rerun", "", "", quart([a / b for a, b in cc if b])],
                ["encoding, per-pair ratio 8a / rerun (8a ≥ 100 ms)", "", "", quart([a / b for a, b in ee if b and a >= 100])],
                ["solving, per-pair ratio 8a / rerun (8a ≥ 0.1 s)", "", "", quart([a / b for a, b in ss if b and a >= 0.1])]]
        out += ["### Times where both runs gave the same answer at the same N", ""]
        out += table(["", "8a", "rerun", "8a / rerun"], rows) + [""]
    # goal by goal, all runs
    rows = []
    for k in sorted(new, key=lambda k: (specs[k].get("probe_group", ""), specs[k]["id"])):
        a, b = old[k], new[k]
        rows.append([f"`{specs[k]['id']}`", specs[k].get("probe_group", ""), a["outcome"], lastn(a),
                     b["outcome"], lastn(b), "same" if (a["outcome"], lastn(a)) == (b["outcome"], lastn(b)) else "changed"])
    out += [f"### Goal by goal ({len(rows)} runs)", ""]
    out += table(["goal", "group", "8a outcome", "8a N", "rerun outcome", "rerun N", ""], rows) + [""]
    ee = sum(1 for r in new.values() for x in r.get("per_N", []) if x["result"] == "early_exit")
    out += [f"Early exits in the rerun's per-N records: {ee}.", ""]
    # sizes of the rerun at N = 5 against 8a's
    sz_new = {r["key"]: r for r in load(os.path.join(D, "rerun", "sizes.jsonl"))}
    sz_old = {r["key"]: r for r in load(os.path.join(R, "eval/m8a/full/sizes.jsonl"))}
    both = sorted(k for k in sz_new if k.endswith("@N5") and k in sz_old and sz_new[k].get("status") == "ok"
                  and sz_old[k].get("status") == "ok")
    if both:
        a = sum(sz_old[k]["clauses"] for k in both)
        b = sum(sz_new[k]["clauses"] for k in both)
        out += [f"Sizes at N = 5 (`countOnly`), {len(both)} runs with both records: 8a {a:,} clauses, rerun {b:,} "
                f"({ratio(a, b)}); per-run ratio {quart([sz_old[k]['clauses'] / sz_new[k]['clauses'] for k in both])}.", ""]
    c = collections.Counter(r.get("status") for r in sz_new.values())
    out += [f"Rerun size records: {len(sz_new)} ({', '.join(f'{k} {v}' for k, v in sorted(c.items()))}).", ""]


def main():
    out = ["# Milestone 8c-1: node bounds (R1) and exclusive pairs (R2)", "",
           "Generated by `eval/m8c1/report.py` from the data files alone (M8_PLAN 4.4). It states facts; reading them "
           "is for the claude.ai project. The 400 points are 8b's (`eval/m8b/specs_points.jsonl`): 200 with the 8a "
           "rules and the same 200 goals without. Settings: both milestone 8 flags off, R1 on, R1 and R2 on; every "
           "other option at its default; `countOnly`.", ""]
    models_section(out)
    by5 = sizes_section(5, out)
    bound_section(by5, out)
    sizes_section(10, out)
    diag_section(out)
    rerun_section(out)
    open(os.path.join(D, "SCALE.md"), "w").write("\n".join(out).rstrip("\n") + "\n")


if __name__ == "__main__":
    main()
