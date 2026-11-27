#!/usr/bin/env python3
"""Milestone 9a-2 (M9_PLAN 3, amendment 6.1): generate eval/m9a2/RULES.md from the data files alone. Facts only:
reading them is for the claude.ai project.

  python3 eval/m9a2/report.py

Inputs (all in eval/m9a2/): the test logs (`offswitch.log`, `diff.log`, `lean_suite.log`, `lean_classify.log`),
the 11 proofs (`rules8a_11.json`, `rules_11.jsonl`, `runs11/results.jsonl`), and the measurement
(`sizes_N5/`, `sizes_N10/`, `diag_rw_N5/`, `diag_rwnt_N5/`, `specs_points.jsonl`, `inputs/`: 8c-1's r1r2 sizes at
N = 5 and 10 and its N = 5 decomposition counts). Pooled figures sum over the goals; per-point figures are medians
(and quartiles) of per-goal values. A comparison between settings uses only the goals that completed in every
setting compared. Only the standard library is used; output is sorted throughout.
"""
import json, os, re, statistics, sys

D = os.path.dirname(os.path.abspath(__file__))
FAMS = ["1 node assignment", "2 tree shape", "3 context (local hypotheses, ancestors)", "4 matching",
        "5 decomposition", "6 links (environment copies)", "7 eigenvariables, occurs check, scope", "8 groundness",
        "10 symmetry breaking", "11 node bounds"]
SETS = [("norules", "no rules (milestone 7's H)"), ("rules8a", "8a's rules as lemmas (8c-1)"),
        ("rw", "iffEq and rewrite"), ("rwnt", "iffEq and rewrite, eqTrans off")]
KINDS = ["subst", "congr", "refl", "symm", "trans"]
ROWS = ["ground", "root", "H"]
GROUPS = [("rewrite_B", "rewriting, Tier B"), ("rewrite_A", "rewriting, Tier A"), ("control", "control")]

DATA_FILES = [
    "offswitch.log", "diff.log", "lean_suite.log", "lean_classify.log", "rules8a_11.json", "rules_11.jsonl",
    "runs11/results.jsonl", "specs_points.jsonl", "sizes_N5/results.jsonl", "sizes_N10/results.jsonl",
    "sizes_N5/timing.json", "sizes_N10/timing.json", "diag_rw_N5/sections.jsonl", "diag_rwnt_N5/sections.jsonl",
    "inputs/m8c1_r1r2_N5.jsonl", "inputs/m8c1_r1r2_N10.jsonl", "inputs/m8c1_diag_N5_m3.jsonl",
]


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
        return f"{statistics.median(xs):.2f}"
    q = statistics.quantiles(xs, n=4, method="inclusive")
    return f"{statistics.median(xs):.2f} [{q[0]:.2f}, {q[2]:.2f}]"


def goal_of(point):
    """`m8b:rules:main:B/x/1` -> `main:B/x/1`."""
    return point.split(":", 2)[2]


# ---------------------------------------------------------------- tests

def tests():
    L = ["## 1. Tests (M9_PLAN 3.2, amendment 6.1 clarification 4)", ""]
    off = open(os.path.join(D, "offswitch.log")).read().strip().splitlines()
    L += [f"- **Off-switch** (every milestone 9 option off): `{off[-1]}`."]
    dl = open(os.path.join(D, "diff.log")).read()
    m = re.search(r"differential with rules: (\d+) forests \((\d+) with rules, (\d+) rules\), (\d+) comparisons, "
                  r"(\d+) provable, (\d+) proofs use a generated rule, (\d+) mismatches", dl)
    if m:
        f, wr, nr, c, pv, ur, mm = m.groups()
        L += [f"- **Differentials** (`test_m9diff 600 4`, N = 1 to 5): {f} random forests ({wr} with rules, {nr} rules "
              f"in all), {c} comparisons with `Reference`, {pv} provable, **{ur} proofs use a generated rule**, "
              f"**{mm} mismatches**."]
    m = re.search(r"selection dropped \(liberal rules\): (\d+) comparisons, (\d+) proofs lost, (\d+) proofs gained, "
                  r"(\d+) mismatches", dl)
    if m:
        c, lo, ga, mm = m.groups()
        L += [f"- **Selection dropped, on the differential forests** (a third of the seeds): {c} comparisons, "
              f"**{lo} proofs lost**, {ga} gained, {mm} mismatches."]
    # the Lean suite
    ls = open(os.path.join(D, "lean_suite.log")).read().splitlines()
    cl = open(os.path.join(D, "lean_classify.log")).read().splitlines()
    passes = {}
    for l in ls:
        m = re.match(r"^(PASS|DIFFERS|FAIL) (off|on|liberal) (\S+)", l)
        if m:
            passes.setdefault(m.group(2), []).append((m.group(3), m.group(1)))
    L += ["- **The Lean suite** (`Test/m9a2_lean.sh`, with the bounds model check), per setting: files that pass "
          "unchanged, and files with differences (classified by `Test/m9a2_classify.py`):", ""]
    rows = []
    for st in ("off", "on", "liberal"):
        ps = passes.get(st, [])
        rows.append([st, sum(1 for _, r in ps if r == "PASS"), sum(1 for _, r in ps if r == "DIFFERS"),
                     sum(1 for _, r in ps if r == "FAIL")])
    L += table(["setting", "files passing unchanged", "files with differences", "files failing"], rows) + [""]
    tally = {}
    lines = []
    for l in cl:
        m = re.match(r"^(on|liberal) (\S+):(\d+) (gained|lost|message|unguarded): (.*)$", l)
        if m:
            st, f, g, c, txt = m.groups()
            tally[(st, c)] = tally.get((st, c), 0) + 1
            if c != "message":
                lines.append((st, f, int(g), c, txt))
    L += table(["setting", "guards: message only", "expected failure became a proof", "proof lost", "unguarded error"],
               [[st, tally.get((st, "message"), 0), tally.get((st, "gained"), 0), tally.get((st, "lost"), 0),
                 tally.get((st, "unguarded"), 0)] for st in ("on", "liberal")]) + [""]
    if lines:
        L += ["Each test whose outcome changed:", ""]
        L += table(["setting", "file", "line", "change", "first differing line"],
                   [[st, f"`{f}`", g, c, "`" + txt.replace("|", "\\|")[:120] + "`"] for st, f, g, c, txt in sorted(lines)])
        L += [""]
    for l in ls:
        if re.match(r"^\S+\.lean: decoded proofs", l):
            L.append(f"- {l}")
    L += [""]
    return L


# ---------------------------------------------------------------- the 11 proofs

def eleven():
    L = ["## 2. The 11 rewriting proofs of 8a (M9_PLAN 3.2)", "",
         "For each proof of 8a that used a substitution or congruence rule: the rules it used (kind, symbol, 8a's "
         "position), whether the strict selection, with milestone 7's spec and `iffEq` and `rewrite` on, makes a rule "
         "of the same kind, symbol and position (in any context), and whether the liberal variant would.", ""]
    R8 = json.load(open(os.path.join(D, "rules8a_11.json")))
    got = {j["key"][len("main:"):]: j for j in load(os.path.join(D, "rules_11.jsonl"))}
    runs = {j["key"][len("main:"):]: j for j in load(os.path.join(D, "runs11", "results.jsonl"))}
    rows, miss = [], 0
    for gid in sorted(R8):
        j = got[gid]
        strict = {(k, s, p) for _, (k, s, p, _r) in j["strict"]}
        lib = {(k, s, p) for (k, s, p, _r) in j["liberal"]}
        for k, s, p in R8[gid]["rules"]:
            ins = (k, "c:" + s, p) in strict
            inl = (k, "c:" + s, p) in lib
            miss += 0 if ins else 1
            rows.append([f"`{gid}`", k, f"`{s}`", p, "yes" if ins else "**no**", "yes" if inl else "no"])
    L += table(["goal", "kind", "symbol", "position", "strict", "liberal"], rows) + [""]
    L += [f"{len(rows) - miss} of {len(rows)} rules (in {len(R8)} proofs) have a strict rule of the same kind, symbol "
          f"and position; {miss} do not.", ""]
    L += ["**The runs** at 8a's N (the N loop from 1 to 8a's N, milestone 7's limits, R1 and R2 on, `iffEq` and "
          "`rewrite` on). A record, not a stop rule:", ""]
    rows = []
    for gid in sorted(R8):
        r = runs.get(gid, {})
        sk = (r.get("skeleton") or "").replace("|", "\\|")
        rows.append([f"`{gid}`", R8[gid]["N"], r.get("outcome", "–"), r.get("N", "–") if r.get("outcome") == "proved" else "–",
                     r.get("rules_total", "–"), ", ".join(f"`{u}`" for u in (r.get("rules_used") or [])) or "–",
                     f"`{sk}`" if sk else "–"])
    L += table(["goal", "8a's N", "outcome", "N", "rules made", "rules used", "skeleton"], rows) + [""]
    return L


# ---------------------------------------------------------------- the measurement

def sizes(n):
    """{goal: {setting: record}} at node bound n, and the points' group."""
    pts = {j["key"]: j for j in load(os.path.join(D, "specs_points.jsonl"))}
    out = {}
    for r in load(os.path.join(D, f"sizes_N{n}", "results.jsonl")):
        p = r["point"] if "point" in r else r["key"].split("|")[0]
        st = r.get("setting") or r["key"].split("|")[1]
        g = goal_of(p)
        if st == "none":
            st = "rules8a_recount" if pts[p].get("probe") else "norules"
        out.setdefault(g, {})[st] = r
    for r in load(os.path.join(D, "inputs", f"m8c1_r1r2_N{n}.jsonl")):
        g = goal_of(r["point"])
        out.setdefault(g, {})["rules8a" if pts[r["point"]].get("probe") else "norules_m8c1"] = r
    group = {goal_of(p): j.get("probe_group", "") for p, j in pts.items()}
    return out, group


def ok(r):
    return r is not None and r.get("status") == "ok"


def measurement():
    L = ["## 3. The measurement (M9_PLAN 3.3, amendment 6.1 clarification 5)", "",
         "The 400 points of `eval/m8b/specs_points.jsonl`: the 200 goals of 8a, each with 8a's rules as lemmas and "
         "without rules (milestone 7's H). `countOnly` counts, R1 and R2 on. The settings: "
         + "; ".join(f"**{k}**: {v}" for k, v in SETS) + ". `rw` and `rwnt` are measured on each goal's point "
         "without rules. Every point without rules and with 8a's rules is recounted with `rewrite` off and compared "
         "with 8c-1's records.", ""]
    for n in (5, 10):
        S, group = sizes(n)
        tj = json.load(open(os.path.join(D, f"sizes_N{n}", "timing.json")))
        L += [f"### N = {n}", ""]
        # consistency
        cons, bad, total = 0, [], 0
        for g, d in sorted(S.items()):
            for mine, ref in (("norules", "norules_m8c1"), ("rules8a_recount", "rules8a")):
                if mine in d and ref in d:
                    total += 1
                    a, b = d[mine], d[ref]
                    same = a.get("status") == b.get("status") and (a.get("status") != "ok" or all(
                        a[k] == b[k] for k in ("clauses", "vars", "families", "early_exit")))
                    cons += same
                    if not same:
                        bad.append(f"{g} ({mine})")
        L += [f"- **Consistency**: the recount with `rewrite` off equals 8c-1's r1r2 counts (clauses, variables, every "
              f"family, early exit) at **{cons} of {total}** points" + (f"; differs at {', '.join(bad)}" if bad else "")
              + f". Wall time of the run: {tj['wall_s'] / 3600:.2f} h.", ""]
        # outcomes per setting
        sts = {"norules": "norules", "rules8a": "rules8a", "rw": "rw", "rwnt": "rwnt"}
        rows = []
        for k, lab in SETS:
            c = {}
            for g, d in S.items():
                r = d.get(k)
                s = "missing" if r is None else ("early exit" if ok(r) and r.get("early_exit") else r.get("status"))
                c[s] = c.get(s, 0) + 1
            rows.append([lab] + [c.get(s, 0) for s in ("ok", "early exit", "memout", "crash", "compile_error", "missing")])
        L += table(["setting", "ok (encoded)", "early exit", "memout", "crash", "compile error", "missing"], rows) + [""]
        # pooled sizes over the goals complete in all four settings
        both = sorted(g for g, d in S.items() if all(ok(d.get(k)) for k, _ in SETS))
        L += [f"**Pooled over the {len(both)} goals measured in all four settings** (clauses and variables, sums):", ""]
        rows = []
        base = sum(S[g]["norules"]["clauses"] for g in both)
        base8 = sum(S[g]["rules8a"]["clauses"] for g in both)
        for k, lab in SETS:
            c = sum(S[g][k]["clauses"] for g in both)
            v = sum(S[g][k]["vars"] for g in both)
            rows.append([lab, c, v, f"{c / base:.3f}" if base else "–", f"{c / base8:.3f}" if base8 else "–"])
        L += table(["setting", "clauses", "variables", "÷ no rules", "÷ 8a's rules"], rows) + [""]
        # per goal ratios
        L += ["**Per goal** (median [quartiles] of the per-goal clause ratio, over the same goals):", ""]
        rows = []
        for k, lab in SETS[2:]:
            r0 = [S[g][k]["clauses"] / S[g]["norules"]["clauses"] for g in both if S[g]["norules"]["clauses"]]
            r8 = [S[g][k]["clauses"] / S[g]["rules8a"]["clauses"] for g in both if S[g]["rules8a"]["clauses"]]
            smaller = sum(1 for g in both if S[g][k]["clauses"] < S[g]["rules8a"]["clauses"])
            rows.append([lab, quart(r0), quart(r8), f"{smaller} of {len(both)}"])
        L += table(["setting", "÷ no rules", "÷ 8a's rules", "goals smaller than with 8a's rules"], rows) + [""]
        # per family pooled
        L += ["**Per family** (pooled clauses, and share of each setting's total):", ""]
        rows = []
        tot = {k: sum(S[g][k]["clauses"] for g in both) for k, _ in SETS}
        for f in FAMS:
            row = [f]
            for k, _ in SETS:
                c = sum(S[g][k]["families"].get(f, 0) for g in both)
                row.append(f"{fmt(c)} ({pct(c, tot[k])})")
            rows.append(row)
        L += table(["family"] + [lab for _, lab in SETS], rows) + [""]
        # per group
        rows = []
        for gr, glab in GROUPS:
            gs = [g for g in both if group.get(g) == gr]
            if not gs:
                continue
            row = [glab, len(gs)]
            for k, _ in SETS:
                row.append(sum(S[g][k]["clauses"] for g in gs))
            rows.append(row)
        L += ["**Per group** (pooled clauses):", ""]
        L += table(["group", "goals"] + [lab for _, lab in SETS], rows) + [""]
        # the rules
        L += ["**The rules made** (`rw`; pooled over the goals with a record, and the median per goal):", ""]
        for k in ("rw", "rwnt"):
            rs = [S[g][k] for g in sorted(S) if k in S[g] and "rules" in S[g][k]]
            rows = []
            for kind in KINDS:
                row = [kind]
                for row_ in ROWS:
                    xs = [r["rules"].get(kind, {}).get(row_, 0) for r in rs]
                    row.append(f"{sum(xs)} ({quart([float(x) for x in xs])})")
                rows.append(row)
            tot_ = [r["rules_total"] for r in rs]
            lib = [r["liberal_extra_total"] for r in rs]
            drop = [len(r["rules_dropped"]) for r in rs]
            L += [f"*{dict(SETS)[k]}*, {len(rs)} goals: {sum(tot_)} rules in all (per goal {quart([float(x) for x in tot_])}); "
                  f"the liberal variant would add {sum(lib)} substitution and congruence rules (per goal "
                  f"{quart([float(x) for x in lib])}); {sum(drop)} rules dropped at {sum(1 for x in drop if x)} goals; "
                  f"{sum(r['spines_broken'] for r in rs)} spines pass a non-term position; "
                  f"{sum(r['spine_nodes_no_row'] for r in rs)} spine nodes have a context that fits no row.", ""]
            L += table(["kind"] + [f"row {r}" for r in ROWS], rows) + [""]
        drops = {}
        for g in sorted(S):
            for k in ("rw",):
                for nm, msg in S[g].get(k, {}).get("rules_dropped", []):
                    reason = re.sub(r"[#@]\S+", "", msg)[:90]
                    drops[reason] = drops.get(reason, 0) + 1
        if drops:
            L += ["Rules dropped (`rw`), by message:", ""]
            L += table(["message (start)", "rules"], sorted(([f"`{m}`", c] for m, c in drops.items()), key=lambda r: (-r[1], r[0]))) + [""]
        mem = sorted(f"{g} ({k})" for g, d in S.items() for k, _ in SETS if d.get(k, {}).get("status") in ("memout", "crash"))
        if mem:
            L += [f"Points that ran out of memory or crashed: {', '.join(mem)}.", ""]
        if n == 10:
            L += per_point(S, both)
    L += level_share()
    return L


def per_point(S, both):
    L = ["### Per goal (N = 10)", "",
         "Clauses at N = 10 in each setting, and the rules made with `rw` (subst/congr/core).", ""]
    rows = []
    for g in both:
        d = S[g]
        r = d["rw"].get("rules", {})
        sc = sum(r.get(k, {}).get(w, 0) for k in ("subst", "congr") for w in ROWS)
        co = sum(r.get(k, {}).get(w, 0) for k in ("refl", "symm", "trans") for w in ROWS)
        rows.append([f"`{g}`", d["norules"]["clauses"], d["rules8a"]["clauses"], d["rw"]["clauses"], d["rwnt"]["clauses"],
                     f"{sc}/{co}", d["rw"].get("liberal_extra_total", 0)])
    return table(["goal", "no rules", "8a's rules", "rw", "rwnt", "rules (subst+congr/core)", "liberal extra"], rows) + [""]


def level_share():
    L = ["### The level-symbol share of decomposition (N = 5)", "",
         "M8Diag's M3 (decomposition clauses by pair), R1 and R2 on: the share of the decomposition clauses whose "
         "symbol is a level symbol, and, with the rules, the share of pairs that involve an object of a rule (its "
         "clause, its premises, or their variables). Pooled over the goals with a record in every setting.", ""]
    pts = {j["key"]: j for j in load(os.path.join(D, "specs_points.jsonl"))}
    m3 = {"norules": {}, "rules8a": {}}
    for r in load(os.path.join(D, "inputs", "m8c1_diag_N5_m3.jsonl")):
        m3["rules8a" if pts[r["key"]].get("probe") else "norules"][goal_of(r["key"])] = r["data"]
    for k in ("rw", "rwnt"):
        m3[k] = {goal_of(r["key"]): r["data"] for r in load(os.path.join(D, f"diag_{k}_N5", "sections.jsonl"))
                 if r.get("section") == "m3"}
    both = sorted(set.intersection(*(set(v) for v in m3.values())))
    rows = []
    for k, lab in SETS:
        tot = sum(m3[k][g]["total"] for g in both)
        lv = sum(m3[k][g]["by"].get("symclass:level", {}).get("clauses", 0) for g in both)
        ru = sum(m3[k][g]["by"].get("rule:yes", {}).get("clauses", 0) for g in both) if k in ("rw", "rwnt") else None
        rl = sum(m3[k][g]["by"].get("rule:yes|level", {}).get("clauses", 0) for g in both) if k in ("rw", "rwnt") else None
        ck = all(m3[k][g].get("check_total_equal", True) for g in both)
        shares = [m3[k][g]["by"].get("symclass:level", {}).get("clauses", 0) / m3[k][g]["total"]
                  for g in both if m3[k][g]["total"]]
        rows.append([lab, tot, f"{lv:,} ({pct(lv, tot)})", quart(shares),
                     "–" if ru is None else f"{ru:,} ({pct(ru, tot)})", "–" if rl is None else f"{rl:,} ({pct(rl, tot)})",
                     "yes" if ck else "**no**"])
    L += [f"{len(both)} goals.", ""]
    L += table(["setting", "decomposition clauses", "level symbols", "level share per goal",
                "pairs with a rule's object", "of which level", "recount equals the encoder"], rows) + [""]
    return L


def main():
    L = ["# Milestone 9a-2: equality rules made per use (RULES.md)", "",
         "Generated by `eval/m9a2/report.py` from the data files in `eval/m9a2/`. It states facts; reading them is for "
         "the claude.ai project. NOTES.md (\"9a-2: equality rules made per use\") has the definitions as built.", ""]
    L += tests() + eleven() + measurement()
    out = "\n".join(L).rstrip("\n") + "\n"
    open(os.path.join(D, "RULES.md"), "w").write(out)


def require_data():
    if not all(os.path.exists(os.path.join(D, p)) for p in DATA_FILES):
        print("the data for this report is in eval/m9a2/ on branch m9 (and on milestone 9's data tag); see eval/README.md")
        sys.exit(1)


if __name__ == "__main__":
    require_data()
    main()
