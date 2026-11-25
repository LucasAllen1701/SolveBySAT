#!/usr/bin/env python3
"""Milestone 8c-2a (M8_PLAN.md 4.5): generate eval/m8c2a/R3SIM.md from the data files alone. Facts only:
whether R3 is built is the owner's decision.

  python3 eval/m8c2a/report.py

Inputs: eval/m8c2a/{models,sim_N5,sim_N10}/, eval/m8c1/{sizes_N5,sizes_N10}/ (8c-1's R1-and-R2 sizes),
eval/m8c1/diag_N5/sections.jsonl (M6), eval/m8c1/models/ (8c-1's skeletons).
Pooled figures sum over the points; per-point figures are medians [quartiles] of per-point values. A
comparison of R3 off with R3 on uses only the points that finished both and did not take the early exit.
Only the standard library is used; output is sorted throughout.
"""
import collections, json, os, statistics

D = os.path.dirname(os.path.abspath(__file__))
R = os.path.dirname(os.path.dirname(D))
VARIANTS = [("rules", "with the rules"), ("norules", "without rules")]
FAMS = ["1 node assignment", "2 tree shape", "3 context (local hypotheses, ancestors)", "4 matching",
        "5 decomposition", "6 links (environment copies)", "7 eigenvariables, occurs check, scope", "8 groundness",
        "10 symmetry breaking", "11 node bounds"]
# M8_PLAN 4.5: the pooled R1-and-R2 counts the replay with R3 off must reproduce
TABLE45 = {("rules", 5): (1198832528, 691355524), ("norules", 5): (233142772, 191867245),
           ("rules", 10): (8783597441, 5427950094), ("norules", 10): (1886439639, 1621030607)}
M6TYPING = {"rules": 4422137, "norules": 334786}
THRESHOLD = 0.8


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
    if not xs:
        return "–"
    xs = sorted(xs)
    if len(xs) < 4:
        return f"{statistics.median(xs):.3f}"
    q = statistics.quantiles(xs, n=4)
    return f"{q[1]:.3f} [{q[0]:.3f}, {q[2]:.3f}]"


def rat(a, b):
    return f"{a / b:.4f}" if b else "–"


def variant(key):
    return key.split(":")[1]


def sections(n):
    s = collections.defaultdict(dict)
    for r in load(os.path.join(D, f"sim_N{n}", "sections.jsonl")):
        if "section" in r:
            s[r["key"]][r["section"]] = r["data"]
    return s


def models_section(out):
    out += ["## The model check (4.5, a stop rule)", ""]
    rows, tot, fails = [], collections.Counter(), []
    for name, label in [("m8a", "the 64 proved 8a runs"), ("named", "the 26 named cases with a proof")]:
        rs = load(os.path.join(D, "models", f"{name}.jsonl"))
        ref = {r["key"]: r.get("skeleton") for r in load(os.path.join(R, "eval/m8c1/models", f"{name}.jsonl"))}
        ck = collections.Counter()
        for r in rs:
            for k, v in r.get("checked", {}).items():
                ck[k] += v["clauses"]
            fails += [f"`{r['key']}`: {f}" for f in r.get("failures", [])]
        tot.update(ck)
        rows.append([label, len(rs), sum(1 for r in rs if r.get("proof") == "ok"),
                     sum(1 for r in rs if ref.get(r["key"]) == r.get("skeleton")),
                     sum(r.get("chosen_typed", 0) for r in rs), ck["slot"], ck["ground"], ck["shared residual"],
                     sum(len(r.get("failures", [])) for r in rs), sum(r.get("label_mismatch", 0) for r in rs),
                     sum(r.get("unreadable", 0) for r in rs), sum(r.get("readback_conflicts", 0) for r in rs)])
    rows.append(["total", *[sum(r[i] for r in rows) for i in range(1, 12)]])
    out += table(["models", "solved", "proof kernel-checked", "skeleton equal to 8c-1's", "chosen candidates with a typing clause",
                  "bindings: slot", "bindings: ground", "bindings: shared residual", "failures", "label mismatches",
                  "unreadable", "read-back conflicts"], rows) + [""]
    out += [f"Bindings checked: {sum(tot.values()):,}. Failures: {len(fails)}." + "".join(f"\n- {f}" for f in fails[:20]), ""]
    t = os.path.join(D, "models", "timing.json")
    if os.path.exists(t):
        out += [f"Wall time {json.load(open(t))['wall_s']:.0f} s.", ""]


def consistency_section(n, sec, out):
    ref = {r["point"]: r for r in load(os.path.join(R, f"eval/m8c1/sizes_N{n}/results.jsonl")) if r.get("setting") == "r1r2"}
    res = {r["key"]: r for r in load(os.path.join(D, f"sim_N{n}", "results.jsonl"))}
    c = collections.Counter(r["status"] for r in res.values())
    out += [f"### Consistency at N = {n}", "",
            f"Points: {len(res)} ({', '.join(f'{k} {v}' for k, v in sorted(c.items()))}).", ""]
    rows = []
    for v, vl in VARIANTS:
        pts = sorted(k for k in sec if variant(k) == v and "r3_off" in sec[k])
        eq = sum(1 for k in pts if k in ref and sec[k]["r3_off"]["clauses"] == ref[k]["clauses"] and
                 sec[k]["r3_off"]["vars"] == ref[k]["vars"] and sec[k]["r3_off"]["families"] == ref[k]["families"])
        cl = sum(sec[k]["r3_off"]["clauses"] for k in pts)
        dc = sum(sec[k]["r3_off"]["families"].get("5 decomposition", 0) for k in pts)
        want = TABLE45.get((v, n), (None, None))
        rows.append([vl, f"{eq} of {len(pts)}", cl, want[0], "yes" if cl == want[0] else "no",
                     dc, want[1], "yes" if dc == want[1] else "no"])
    out += ["With R3 off, the replay against the encoder's counts (8c-1's R1-and-R2 sizes; clauses, variables and every "
            "family equal per point) and against the table of 4.5, pooled:", ""]
    out += table(["points", "equal per point", "clauses", "4.5", "equal", "decomposition", "4.5", "equal"], rows) + [""]
    if n == 5:
        m6 = collections.defaultdict(dict)
        for r in load(os.path.join(R, "eval/m8c1/diag_N5/sections.jsonl")):
            if r.get("section") in ("m6_r3", "m3"):
                m6[r["key"]][r["section"]] = r["data"]
        rows = []
        for v, vl in VARIANTS:
            pts = sorted(k for k in sec if variant(k) == v and "r3_off" in sec[k] and not sec[k]["r3_off"]["early_exit"])
            tu = sum(sec[k]["r3_off"]["typing_unify"] for k in pts)
            tn = sum(sec[k]["r3_off"]["typing_no_unify"] for k in pts)
            mu = sum(m6[k]["m6_r3"]["by"].get("typing clauses", {}).get("clauses", 0) for k in pts if "m6_r3" in m6[k])
            mn = sum(m6[k]["m6_r3"]["by"].get("typing clauses, templates do not unify", {}).get("clauses", 0)
                     for k in pts if "m6_r3" in m6[k])
            per = sum(1 for k in pts if "m6_r3" in m6[k] and
                      (sec[k]["r3_off"]["typing_unify"], sec[k]["r3_off"]["typing_no_unify"]) ==
                      (m6[k]["m6_r3"]["by"].get("typing clauses", {}).get("clauses", 0),
                       m6[k]["m6_r3"]["by"].get("typing clauses, templates do not unify", {}).get("clauses", 0)))
            # M6's decomposition by kinds, against the replay with R3 off
            kin = collections.Counter()
            mk = collections.Counter()
            for k in pts:
                kin.update(sec[k]["r3_off"]["decomposition_kinds"])
                for lab, x in m6[k].get("m3", {}).get("by", {}).items():
                    if lab.startswith("kinds:"):
                        mk[lab[len("kinds:"):]] += x["clauses"]
            rows.append([vl, f"{per} of {len(pts)}", tu, mu, M6TYPING[v], "yes" if tu == mu == M6TYPING[v] else "no", tn, mn,
                         "yes" if kin == mk else "no"])
        out += ["Typing clauses at N = 5 (whose templates unify, as M6 counts them; and whose templates do not), "
                "against M6, and the decomposition by object kinds with R3 off against M6's:", ""]
        out += table(["points", "equal per point", "typing clauses", "M6", "4.5", "equal", "do not unify", "M6",
                      "kinds equal to M6"], rows) + [""]


def projection_section(n, sec, out):
    out += [f"## The projection at N = {n}", ""]
    t = os.path.join(D, f"sim_N{n}", "timing.json")
    if os.path.exists(t):
        tm = json.load(open(t))
        out += [f"Wall time {tm['wall_s'] / 3600:.2f} h{'' if tm.get('finished') else ' (not finished)'}.", ""]
    consistency_section(n, sec, out)
    res = {r["key"]: r for r in load(os.path.join(D, f"sim_N{n}", "results.jsonl"))}
    mem = sorted((k, r) for k, r in res.items() if r["status"] != "ok")
    if mem:
        out += [f"Points that did not finish: {len(mem)}", ""]
        out += table(["point", "status", "last section"], [[f"`{k}`", r["status"], r.get("last_section", "–")] for k, r in mem]) + [""]
    for v, vl in VARIANTS:
        pts = sorted(k for k in sec if variant(k) == v and "r3_on" in sec[k] and not sec[k]["r3_off"]["early_exit"])
        ee = sum(1 for k in sec if variant(k) == v and sec[k].get("r3_off", {}).get("early_exit"))
        out += [f"### {vl}: {len(pts)} points ({ee} early exits left out)", ""]
        if not pts:
            continue
        off = {k: sec[k]["r3_off"] for k in pts}
        on = {k: sec[k]["r3_on"] for k in pts}
        # clauses and variables, pooled and per point
        rows = []
        for f in ["total"] + FAMS:
            g = (lambda x: x["clauses"]) if f == "total" else (lambda x, f=f: x["families"].get(f, 0))
            a, b = sum(g(off[k]) for k in pts), sum(g(on[k]) for k in pts)
            if a == 0 and b == 0:
                continue
            rows.append([f, a, b, b - a, rat(b, a), quart([g(on[k]) / g(off[k]) for k in pts if g(off[k])])])
        out += ["**Clauses**, R1 and R2 (R3 off) against R1, R2 and R3 (R3 on): pooled, and the per-point ratio R3 on / off:", ""]
        out += table(["family", "R1 R2", "R1 R2 R3", "difference", "pooled ratio", "per-point ratio"], rows) + [""]
        rows = []
        fams = sorted({f for k in pts for f in list(off[k]["family_vars"]) + list(on[k]["family_vars"])})
        for f in ["total"] + fams:
            g = (lambda x: x["vars"]) if f == "total" else (lambda x, f=f: x["family_vars"].get(f, 0))
            a, b = sum(g(off[k]) for k in pts), sum(g(on[k]) for k in pts)
            if a == 0 and b == 0:
                continue
            rows.append([f, a, b, b - a, rat(b, a), quart([g(on[k]) / g(off[k]) for k in pts if g(off[k])])])
        out += ["**Variables**, by the family in which each was allocated (structural variables first):", ""]
        out += table(["family", "R1 R2", "R1 R2 R3", "difference", "pooled ratio", "per-point ratio"], rows) + [""]
        # objects, bindings, candidates
        bt = sum(on[k]["type_rigid_built"] for k in pts)
        rt = sum(on[k]["type_rigid_retained"] for k in pts)
        tg = sum(on[k]["residual_targets"] for k in pts)
        b = collections.Counter()
        for k in pts:
            b.update(on[k]["bindings"])
        tu = sum(on[k]["typing_unify"] for k in pts)
        tn = sum(on[k]["typing_no_unify"] for k in pts)
        sv0, sv1 = sum(off[k]["sv"] for k in pts), sum(on[k]["sv"] for k in pts)
        p0, p1 = sum(off[k]["full_pairs"] for k in pts), sum(on[k]["full_pairs"] for k in pts)
        nb = b["slot"] + b["ground"] + b["residual"]
        rows = [["type-template objects built", bt, "", quart([on[k]["type_rigid_built"] for k in pts])],
                ["retained", rt, pct(rt, bt), quart([on[k]["type_rigid_retained"] / on[k]["type_rigid_built"]
                                                     for k in pts if on[k]["type_rigid_built"]])],
                ["of them ⟦t⟧ of some binding", tg, pct(tg, bt), ""],
                ["typing clauses (R1 R2)", tu + tn, "", ""],
                ["of them with templates that unify", tu, pct(tu, tu + tn), ""],
                ["candidates dropped (templates do not unify)", tn, pct(tn, tu + tn), ""],
                ["bindings", nb, "", f"{nb / tu:.2f} per typing clause" if tu else "–"],
                ["bindings: slot", b["slot"], pct(b["slot"], nb), ""],
                ["bindings: ground", b["ground"], pct(b["ground"], nb), ""],
                ["bindings: shared residual", b["residual"], pct(b["residual"], nb), ""],
                ["shared residual, in the variable's template", b["residual_in_L"], pct(b["residual_in_L"], b["residual"]), ""],
                ["shared residual, in the candidate's template", b["residual_in_R"], pct(b["residual_in_R"], b["residual"]), ""],
                ["typing clauses without a binding", "–", "", ""],
                ["sv (R1 R2 → R1 R2 R3)", f"{sv0:,} → {sv1:,}", pct(sv1, sv0), ""],
                ["full decomposition pairs (R1 R2 → R1 R2 R3)", f"{p0:,} → {p1:,}", pct(p1, p0), ""]]
        rows = [r for r in rows if r[0] != "typing clauses without a binding"]
        out += ["**Type-template objects, bindings and candidates**, pooled (per point: median [quartiles]):", ""]
        out += table(["", "count", "share", "per point"], rows) + [""]
        # decomposition after R3, as M6
        for lab, x in [("R1 R2", off), ("R1 R2 R3", on)]:
            kin = collections.Counter()
            cls = collections.Counter()
            for k in pts:
                kin.update(x[k]["decomposition_kinds"])
                cls.update(x[k]["decomposition_symclass"])
            dt = sum(cls.values())
            out += [f"**Decomposition by object kinds, {lab}**, pooled over {dt:,} clauses:", ""]
            out += table(["kinds of the pair", "symbol class", "clauses", "share"],
                         [[*kk.split("|"), kin[kk], pct(kin[kk], dt)] for kk in sorted(kin, key=lambda l: (-kin[l], l))] +
                         [["all", c, cls[c], pct(cls[c], dt)] for c in sorted(cls)]) + [""]


def decision_section(sec5, out):
    out += ["## The decision rule of 4.5", ""]
    pts = sorted(k for k in sec5 if variant(k) == "rules" and "r3_on" in sec5[k])
    a = sum(sec5[k]["r3_off"]["clauses"] for k in pts)
    b = sum(sec5[k]["r3_on"]["clauses"] for k in pts)
    if not a:
        out += ["No data.", ""]
        return
    r = b / a
    out += [f"With the rules at N = 5, over the {len(pts)} points that finished both settings (early exits included, one "
            f"clause each): R1 and R2 {a:,} clauses, R1, R2 and R3 projected {b:,}. Ratio {r:.4f} "
            f"({a / b:.3f} times smaller). The rule's threshold is {THRESHOLD} (1.25 times smaller): the ratio is "
            f"{'at most' if r <= THRESHOLD else 'above'} {THRESHOLD}.", ""]


def main():
    out = ["# 8c-2a: R3 simulated with shared residual objects", "",
           "Generated by `python3 eval/m8c2a/report.py` from the data files in `eval/m8c2a/` (and 8c-1's in `eval/m8c1/`). "
           "M8_PLAN 4.5 pre-registers the simulation, its checks and the decision rule; NOTES.md (\"8c-2a: R3 simulation\") "
           "has the definitions. R1 and R2 are on throughout. \"R3 off\" is the replay of today's encoder; \"R3 on\" the "
           "projection. Label widths are today's in both.", ""]
    models_section(out)
    sec5, sec10 = sections(5), sections(10)
    decision_section(sec5, out)
    projection_section(5, sec5, out)
    projection_section(10, sec10, out)
    open(os.path.join(D, "R3SIM.md"), "w").write("\n".join(out).rstrip("\n") + "\n")


if __name__ == "__main__":
    main()
