#!/usr/bin/env python3
"""Milestone 9a-3 (M9_PLAN 4.6, amendment 6.2): writes eval/m9a3/EVAL9A.md from the data files of eval/m9a3/ alone.

  python3 eval/m9a3/report.py

It states facts and recommends nothing. Without its data files it prints which one is missing and exits 1, writing
nothing. The output is a deterministic function of the data (sorted keys, fixed number formats), so it regenerates
byte-identically.
"""
import hashlib, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUTFILE = os.path.join(HERE, "EVAL9A.md")
INP = os.path.join(HERE, "inputs")
DATA_FILES = [
    "inputs.md5", "setup.txt", "sample.tsv", "specs.jsonl", "expect.jsonl",
    "inputs/m8-data__m8c1__rerun__results.jsonl", "inputs/m7-data__final__results.jsonl",
    "inputs/m8-data__m8c1__sizes_N5__results.jsonl",
    "runs/header.json", "runs/results.jsonl", "runs/driver.jsonl",
    "sizes_N5/results.jsonl", "sizes_last/results.jsonl", "rules.jsonl",
]
GUARD = ("the data of 9a-3 is in eval/m9a3/ on branch m9 (and, after milestone 9, on its data tag); "
         "missing: {}")

GROUPS = [("g1_rewrite_B", "group 1: 8a's rewriting Tier B"), ("g1_rewrite_A", "group 1: 8a's rewriting Tier A"),
          ("g1_control", "group 1: 8a's controls"), ("rewrite_B", "group 2: fresh rewriting Tier B"),
          ("rewrite_A", "group 2: fresh rewriting Tier A"), ("control", "group 3: fresh controls")]
GNAME = dict(GROUPS)
OUTCOMES = ["proved", "no_proof_le_Nmax", "timeout", "memout", "crash", "limitation", "goal_rejected"]
OUTNAME = {"proved": "proved", "no_proof_le_Nmax": "no proof ≤ 10", "timeout": "timeout", "memout": "memout",
           "crash": "crash", "limitation": "limitation", "goal_rejected": "goal rejected"}
KINDS = ["subst", "congr", "refl", "symm", "trans"]
ROWS = ["ground", "root", "H"]
POPULATION = {"rewrite_B": 846, "rewrite_A": 472}


def load(p):
    with open(os.path.join(HERE, p)) as f:
        return [json.loads(l) for l in f if l.strip()]


def md5(p):
    return hashlib.md5(open(os.path.join(HERE, p), "rb").read()).hexdigest()


def fmt(n):
    return f"{n:,}"


def med(xs):
    xs = sorted(xs)
    if not xs:
        return None
    m = len(xs) // 2
    return xs[m] if len(xs) % 2 else (xs[m - 1] + xs[m]) / 2


def quart(xs):
    xs = sorted(xs)
    if not xs:
        return "–"
    def q(p):
        k = (len(xs) - 1) * p
        lo, hi = math.floor(k), math.ceil(k)
        return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)
    return f"{q(0.5):.2f} [{q(0.25):.2f}, {q(0.75):.2f}]"


def wilson(k, n, z=1.959963984540054):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "| " + " | ".join("---" for _ in head) + " |"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return out


def kr(d):
    """A {kind: {row: n}} record as counts per kind and per row."""
    bk = {k: 0 for k in KINDS}
    br = {r: 0 for r in ROWS}
    for k, rs in (d or {}).items():
        for r, n in rs.items():
            bk[k] = bk.get(k, 0) + n
            br[r] = br.get(r, 0) + n
    return bk, br


def probe_rule(u):
    """8a's rule name (8c-1's probe_extra_used) as (kind, symbol, position), ('core', kind) or ('propext', lemma)."""
    if u in ("Eq.refl", "Eq.symm", "Eq.trans"):
        return ("core", u.split(".")[1])
    if u.startswith("_probe.") and ".propext" in u:
        return ("propext", u[len("_probe."):].split(".propext")[0])
    if u.startswith("_probe."):
        body = u[len("_probe."):].replace("«", "").replace("»", "")
        sym, kind, pos = body.rsplit(".", 2)
        return (kind, "c:" + sym, int(pos))
    return ("other", u)


def last_n(r):
    out = r.get("outcome")
    if out in ("proved", "no_proof_le_Nmax", "limitation") and r.get("N"):
        return r["N"]
    if out == "crash":
        return r.get("last_N") or 1
    return max((x.get("N", 0) for x in r.get("per_N") or []), default=0) or r.get("N") or 1


def main():
    missing = [p for p in DATA_FILES if not os.path.exists(os.path.join(HERE, p))]
    if missing:
        print(GUARD.format(", ".join(missing)))
        return 1
    specs = load("specs.jsonl")
    exp = {e["key"]: e for e in load("expect.jsonl")}
    group = {s["key"]: s["group"] for s in specs}
    order = [s["key"] for s in specs]
    res = {r["key"]: r for r in load("runs/results.jsonl")}
    hdr = json.load(open(os.path.join(HERE, "runs/header.json")))
    drv = load("runs/driver.jsonl")
    rerun = {r["key"][len("m8a:"):]: r for r in load("inputs/m8-data__m8c1__rerun__results.jsonl")}
    m7 = {r["key"]: r for r in load("inputs/m7-data__final__results.jsonl")}
    s8c = {}
    for r in load("inputs/m8-data__m8c1__sizes_N5__results.jsonl"):
        if r.get("setting") == "r1r2":
            s8c[r["key"]] = r
    sz5 = {r["key"].rsplit("|", 1)[0]: r for r in load("sizes_N5/results.jsonl")}
    szl = {r["key"].rsplit("|", 1)[0]: r for r in load("sizes_last/results.jsonl")}
    rules = {r["key"]: r for r in load("rules.jsonl")}
    L = []
    w = L.append

    w("# Milestone 9a-3: evaluation of in-tactic rewriting (EVAL9A.md)")
    w("")
    w("Generated by `eval/m9a3/report.py` from the data files in `eval/m9a3/`. It states facts; reading them is for "
      "the claude.ai project. NOTES.md (\"9a-3: evaluation\") has the definitions and the explanations.")
    w("")

    # 1. inputs
    w("## 1. Inputs, sample and settings (M9_PLAN 4.1 to 4.3)")
    w("")
    w("- Inputs (`eval/m9a3/inputs/`, a file per tag and path; md5 sums in `inputs.md5`):")
    for l in open(os.path.join(HERE, "inputs.md5")):
        if l.strip():
            m, f = l.split()
            tag, path = f.split("__", 1)
            w(f"  - `{tag}:eval/{path.replace('__', '/')}`: `{m}`")
    w("- " + "; ".join(l.strip() for l in open(os.path.join(HERE, "setup.txt")) if l.strip()) + ".")
    w(f"- `specs.jsonl` md5 `{md5('specs.jsonl')}`, `sample.tsv` md5 `{md5('sample.tsv')}`, "
      f"`expect.jsonl` md5 `{md5('expect.jsonl')}`.")
    flags = sorted({",".join(r.get("enc_flags", [])) for r in res.values() if r.get("enc_flags")})
    eqt = sorted({str(r.get("eqTrans")) for r in res.values() if "eqTrans" in r})
    w(f"- Settings: flags `{'; '.join(flags)}`, eqTrans {', '.join(eqt)}; N from 1 to 10; solver "
      f"{hdr['solver_s']} s per call, N loop {hdr['loop_s']} s, watchdog {hdr['watchdog_s']} s, cap {hdr['cap_mb']} MB, "
      f"shards of {hdr['shard_size']}, one at a time. Code: `{hdr['git_commit']}`"
      f"{' (dirty)' if hdr.get('git_dirty') else ''}.")
    walls = [d["wall_s"] for d in drv if "wall_s" in d]
    w(f"- Results: {len(res)} of {len(order)} runs; driver wall time {sum(walls) / 3600:.2f} h over {len(walls)} "
      f"driver sessions.")
    w("")

    # 2. outcomes
    w("## 2. Outcomes per group (M9_PLAN 4.6)")
    w("")
    rows = []
    for g, gn in GROUPS:
        ks = [k for k in order if group[k] == g]
        c = {o: 0 for o in OUTCOMES}
        other = 0
        for k in ks:
            o = res.get(k, {}).get("outcome")
            if o in c:
                c[o] += 1
            else:
                other += 1
        rows.append([gn, len(ks)] + [c[o] for o in OUTCOMES] + [other])
    for line in table(["group", "runs"] + [OUTNAME[o] for o in OUTCOMES] + ["other or missing"], rows):
        w(line)
    w("")

    # 3. transitions
    w("### Transitions from the earlier outcome")
    w("")
    w("Group 1 against 8c-1's rerun of the same 8a specs (with the probe's rules as lemmas, R1 and R2 on); groups 2 and "
      "3 against milestone 7's main run. Rows: the earlier outcome; columns: 9a-3's.")
    w("")
    for g, gn in GROUPS:
        ks = [k for k in order if group[k] == g]
        tr = {}
        for k in ks:
            a = exp[k]["earlier_outcome"]
            b = res.get(k, {}).get("outcome", "missing")
            tr[(a, b)] = tr.get((a, b), 0) + 1
        cols = [o for o in OUTCOMES + ["missing"] if any(b == o for (_, b) in tr)]
        rws = [o for o in OUTCOMES if any(a == o for (a, _) in tr)]
        w(f"*{gn}* ({len(ks)} runs; earlier: {'8c-1' if g.startswith('g1_') else 'milestone 7'})")
        w("")
        for line in table(["earlier \\ 9a-3"] + [OUTNAME.get(o, o) for o in cols],
                          [[OUTNAME[a]] + [tr.get((a, b), 0) for b in cols] for a in rws]):
            w(line)
        w("")

    # 4. proved at N
    w("## 3. Proved at N")
    w("")
    rows = []
    for g, gn in GROUPS:
        ks = [k for k in order if group[k] == g]
        ns = [res[k]["N"] for k in ks if res.get(k, {}).get("outcome") == "proved"]
        rows.append([gn] + [sum(1 for n in ns if n == i) for i in range(1, 11)] + [len(ns)])
    for line in table(["group"] + [f"N={i}" for i in range(1, 11)] + ["proved"], rows):
        w(line)
    w("")
    w("Earlier proofs at N, for comparison (8c-1 for group 1, milestone 7 for groups 2 and 3):")
    w("")
    rows = []
    for g, gn in GROUPS:
        ks = [k for k in order if group[k] == g]
        ns = [exp[k]["earlier_N"] for k in ks if exp[k]["earlier_outcome"] == "proved"]
        rows.append([gn] + [sum(1 for n in ns if n == i) for i in range(1, 11)] + [len(ns)])
    for line in table(["group"] + [f"N={i}" for i in range(1, 11)] + ["proved"], rows):
        w(line)
    w("")

    # 5. rules used
    proofs = [k for k in order if res.get(k, {}).get("outcome") == "proved"]
    w("## 4. The rules the proofs use (M9_PLAN 4.6; amendment 6.2, decision 3)")
    w("")
    w("A proof's rule nodes, by kind and row (`rules_used_by`), and its nodes on a `propext` path of 9a-1 (`propext_used`, "
      "from a constant of H or a local hypothesis). A rule used at two nodes counts twice.")
    w("")
    rows = []
    for g, gn in GROUPS + [("all", "all groups")]:
        ks = [k for k in proofs if g == "all" or group[k] == g]
        tot = {(kk, rr): 0 for kk in KINDS for rr in ROWS}
        pe = [0, 0]
        for k in ks:
            for kk, rs in (res[k].get("rules_used_by") or {}).items():
                for rr, n in rs.items():
                    tot[(kk, rr)] += n
            pb = res[k].get("propext_used_by") or {}
            pe[0] += pb.get("H", 0)
            pe[1] += pb.get("local", 0)
        rows.append([gn, len(ks)] + [f"{sum(tot[(kk, rr)] for rr in ROWS)}" for kk in KINDS] +
                    [sum(tot[(kk, rr)] for kk in KINDS) for rr in ROWS] + [f"{pe[0]} / {pe[1]}"])
    for line in table(["group", "proofs"] + KINDS + [f"row {r}" for r in ROWS] + ["propext (H / local)"], rows):
        w(line)
    w("")
    w("**Proofs by the kinds of rule they use** (all groups):")
    w("")
    cls = {}
    for k in proofs:
        bk, _ = kr(res[k].get("rules_used_by"))
        used = [kk for kk in KINDS if bk[kk]] + (["propext"] if res[k].get("propext_used") else [])
        c = " + ".join(used) if used else "none (milestone 7's H only)"
        cls.setdefault(c, {}).setdefault(group[k], 0)
        cls[c][group[k]] += 1
    for line in table(["kinds used"] + [GNAME[g] for g, _ in GROUPS] + ["all"],
                      [[c] + [cls[c].get(g, 0) for g, _ in GROUPS] + [sum(cls[c].values())]
                       for c in sorted(cls, key=lambda c: (-sum(cls[c].values()), c))]):
        w(line)
    w("")
    w("**Every proof** (group, N, rule nodes by kind and row, propext nodes, and the rules by name):")
    w("")
    rows = []
    for k in proofs:
        r = res[k]
        bk, br = kr(r.get("rules_used_by"))
        rows.append([f"`{k}`", g_short(group[k]), r["N"]] + [bk[kk] for kk in KINDS] + [br[rr] for rr in ROWS] +
                    [r.get("propext_used", 0), ", ".join(f"`{u}`" for u in (r.get("rules_used") or [])) or "–"])
    for line in table(["goal", "group", "N"] + KINDS + ROWS + ["propext", "rules"], rows):
        w(line)
    w("")

    # rules made
    w("### The rules made")
    w("")
    w("Per run with a record that has them (the forest is compiled before the N loop): the rules made, by kind and row "
      "(totals, and the median per run with its quartiles).")
    w("")
    rows = []
    for g, gn in GROUPS + [("all", "all groups")]:
        ks = [k for k in order if (g == "all" or group[k] == g) and "rules_total" in res.get(k, {})]
        per = {kk: [] for kk in KINDS}
        rowt = {rr: 0 for rr in ROWS}
        for k in ks:
            bk, br = kr(res[k].get("rules"))
            for kk in KINDS:
                per[kk].append(bk[kk])
            for rr in ROWS:
                rowt[rr] += br[rr]
        tots = [res[k]["rules_total"] for k in ks]
        drop = sum(len(res[k].get("rules_dropped") or []) for k in ks)
        lib = sum(res[k].get("liberal_extra_total", 0) for k in ks)
        rows.append([gn, len(ks), f"{sum(tots)} ({quart(tots)})"] + [sum(per[kk]) for kk in KINDS] +
                    [rowt[rr] for rr in ROWS] + [drop, lib])
    for line in table(["group", "runs", "rules (median [quartiles])"] + KINDS + [f"row {r}" for r in ROWS] +
                      ["dropped", "liberal would add"], rows):
        w(line)
    w("")

    # 6. sizes
    w("## 5. CNF sizes (M9_PLAN 4.3, 4.6)")
    w("")
    w("`countOnly` counts in setting `rw` (iffEq and rewrite, eqTrans on, R1 and R2 on), in their own capped processes: "
      "at N = 5, and at each run's last N (the N of the proof, 10 for no proof, the last N attempted otherwise).")
    w("")
    rows = []
    for g, gn in GROUPS:
        ks = [k for k in order if group[k] == g]
        for tag, sz in (("N = 5", sz5), ("last N", szl)):
            st = {}
            for k in ks:
                s = sz.get(k, {}).get("status", "missing")
                st[s] = st.get(s, 0) + 1
            ok = [k for k in ks if sz.get(k, {}).get("status") == "ok"]
            cl = [sz[k]["clauses"] for k in ok]
            ee = sum(1 for k in ok if sz[k].get("early_exit"))
            rows.append([gn, tag, ", ".join(f"{s} {n}" for s, n in sorted(st.items())), ee, fmt(sum(cl)),
                         fmt(int(med(cl))) if cl else "–"])
    for line in table(["group", "at", "records", "early exit", "clauses (sum)", "clauses (median)"], rows):
        w(line)
    w("")

    # group 1 goal by goal
    w("### Group 1, goal by goal")
    w("")
    w("8c-1's outcome and N (8a's spec with the probe's rules as lemmas, R1 and R2 on) against 9a-3's, and the clauses at "
      "N = 5: 8c-1's (`eval/m8c1/sizes_N5/`, the point `m8b:rules:<key>`, setting r1r2) against 9a-3's. The ratio is "
      "9a-3 ÷ 8c-1.")
    w("")
    rows, ratios, pair = [], [], [0, 0]
    for k in order:
        if not group[k].startswith("g1_"):
            continue
        e, r = exp[k], res.get(k, {})
        a = s8c.get(f"m8b:rules:{k}|r1r2", {})
        b = sz5.get(k, {})
        ca = a.get("clauses") if a.get("status", "ok") == "ok" and "clauses" in a else None
        cb = b.get("clauses") if b.get("status") == "ok" else None
        rt = f"{cb / ca:.3f}" if ca and cb is not None else "–"
        if ca and cb is not None:
            ratios.append(cb / ca)
            pair[0] += ca
            pair[1] += cb
        rows.append([f"`{k}`", g_short(group[k]), out_n(e["earlier_outcome"], e["earlier_N"]),
                     out_n(r.get("outcome", "missing"), r.get("N") if r.get("outcome") == "proved" else None),
                     fmt(ca) if ca is not None else a.get("status", "–"),
                     fmt(cb) if cb is not None else b.get("status", "–"), rt])
    w(f"Over the {len(ratios)} goals with both counts: pooled clauses {fmt(pair[0])} (8c-1) and {fmt(pair[1])} (9a-3), "
      f"ratio {pair[1] / pair[0]:.3f}; per goal, the median ratio is {quart(ratios)}, and "
      f"{sum(1 for x in ratios if x < 1)} goals are smaller in 9a-3." if ratios else "No goal has both counts.")
    w("")
    for line in table(["goal", "group", "8c-1", "9a-3", "8c-1 clauses N=5", "9a-3 clauses N=5", "ratio"], rows):
        w(line)
    w("")

    # 7. group 2 shares
    w("## 6. Group 2: shares, applied to the populations")
    w("")
    w("The share of each fresh rewriting sample that is proved, and that is certified \"no proof ≤ 10\", with Wilson 95% "
      "intervals, and the share applied to the population (846 Tier B and 472 Tier A goals, M9_PLAN 4.1).")
    w("")
    rows = []
    for g in ("rewrite_B", "rewrite_A"):
        ks = [k for k in order if group[k] == g]
        n = len(ks)
        for what, o in (("proved", "proved"), ("no proof ≤ 10", "no_proof_le_Nmax")):
            c = sum(1 for k in ks if res.get(k, {}).get("outcome") == o)
            lo, hi = wilson(c, n)
            P = POPULATION[g]
            rows.append([GNAME[g], what, f"{c} / {n}", f"{c / n:.3f}" if n else "–", f"[{lo:.3f}, {hi:.3f}]",
                         f"{c / n * P:.0f} [{lo * P:.0f}, {hi * P:.0f}] of {P}" if n else "–"])
    for line in table(["group", "outcome", "count", "share", "Wilson 95%", "applied to the population"], rows):
        w(line)
    w("")

    # 8. the list of 4.4
    w("## 7. The stop rules and the list of 4.4")
    w("")
    stops = [d for d in drv if "stop" in d]
    w(f"- **Stops**: {len(stops)}." + ("".join(f" `{d.get('key')}`: {d.get('reason', d['stop'])}." for d in stops)))
    dec = [k for k in order if res.get(k, {}).get("outcome") in ("decoder_bug", "solver_error")]
    w(f"- **Decoder failures**: {len(dec)}.")
    lr = [k for k in order if exp[k]["lost_rule"]]
    lr_ok = [k for k in lr if res.get(k, {}).get("outcome") == "proved" and res[k]["N"] <= exp[k]["earlier_N"]]
    lr_lim = [k for k in lr if k not in lr_ok]
    w(f"- **Lost proofs**: {len(lr)} goals are under the rule (group 1 with an empty `probe_extra_used`: "
      f"{sum(1 for k in lr if group[k].startswith('g1_'))}; group 3: {sum(1 for k in lr if group[k] == 'control')}); "
      f"{len(lr_ok)} are proved at or below their earlier N; the others:"
      + (" none." if not lr_lim else ""))
    for k in lr_lim:
        r = res.get(k, {})
        w(f"  - `{k}` ({g_short(group[k])}): earlier N {exp[k]['earlier_N']}, 9a-3 "
          f"{out_n(r.get('outcome', 'missing'), r.get('N') if r.get('outcome') == 'proved' else None)}"
          f"{', last N ' + str(last_n(r)) if r else ''}{' (STOP: ' + r['stop'] + ')' if r.get('stop') else ''}.")
    ex = [k for k in proofs if group[k] in ("rewrite_B", "rewrite_A", "control") and res[k]["N"] in (exp[k].get("m7_unsat") or [])]
    ex_plain = [k for k in ex if not res[k].get("rules_used") and not res[k].get("propext_used")]
    w(f"- **Exactness** (groups 2 and 3): {len(ex)} proofs at an N where milestone 7 was UNSAT; "
      f"{len(ex) - len(ex_plain)} use a generated rule or a `propext` path, {len(ex_plain)} use neither.")
    w("")
    w("**Group 1 goals that 8c-1 proved with the probe's rules** (not a stop; amendment 6.2, decision 6). For each rule "
      "of 8a the 8c-1 proof used: whether 9a-3 makes a strict rule of the same kind, symbol and position (any row), for "
      "a substitution or congruence rule; whether the equality core has that kind (at any type), for `Eq.refl`, "
      "`Eq.symm`, `Eq.trans`; whether a `propext` path from H is compiled, for an `↔` rule. The class assigned: "
      "**selection** if a substitution or congruence rule is not made; else **equality core** if a core kind is "
      "missing; else **propext path** if no `propext` path from H is compiled; else **limit** if 9a-3 ended at a limit (timeout, memout or crash); else **context** (each rule is "
      "made, in some context).")
    w("")
    rows = []
    for k in order:
        e = exp[k]
        if not (group[k].startswith("g1_") and e["earlier_outcome"] == "proved" and e.get("probe_extra_used")):
            continue
        r = res.get(k, {})
        rr = rules.get(k, {})
        strict = {tuple(x[1][:3]) for x in rr.get("strict", [])}
        kinds = {x[1][0] for x in rr.get("strict", [])}
        marks, miss_sel, miss_core, miss_pe = [], False, False, False
        for u in e["probe_extra_used"]:
            p = probe_rule(u)
            if p[0] in ("subst", "congr"):
                ok = p in strict
                miss_sel |= not ok
            elif p[0] == "core":
                ok = p[1] in kinds
                miss_core |= not ok
            elif p[0] == "propext":
                ok = (r.get("iffeq_paths") or [0, 0])[0] > 0
                miss_pe |= not ok
            else:
                ok = False
            marks.append(f"`{u}` {'yes' if ok else '**no**'}")
        proved = r.get("outcome") == "proved"
        if proved:
            cl = "proved (not listed)"
        elif miss_sel:
            cl = "selection"
        elif miss_core:
            cl = "equality core"
        elif miss_pe:
            cl = "propext path"
        elif r.get("outcome") in ("timeout", "memout", "crash"):
            cl = "limit"
        else:
            cl = "context"
        rows.append([f"`{k}`", e["earlier_N"], out_n(r.get("outcome", "missing"), r.get("N") if proved else None),
                     "; ".join(marks), cl])
    for line in table(["goal", "8c-1 N", "9a-3", "8a's rules used, and made in 9a-3", "class"], rows):
        w(line)
    w("")
    cnt = {}
    for row in rows:
        cnt[row[-1]] = cnt.get(row[-1], 0) + 1
    w(f"{len(rows)} goals: " + ", ".join(f"{c} {n}" for c, n in sorted(cnt.items())) + ".")
    w("")

    text = "\n".join(L) + "\n"
    open(OUTFILE, "w").write(text)
    print(f"wrote {OUTFILE} ({len(L)} lines)")
    return 0


def g_short(g):
    return {"g1_rewrite_B": "1 B", "g1_rewrite_A": "1 A", "g1_control": "1 control", "rewrite_B": "2 B",
            "rewrite_A": "2 A", "control": "3"}[g]


def out_n(o, n):
    return f"{OUTNAME.get(o, o)}{' at ' + str(n) if n else ''}"


if __name__ == "__main__":
    sys.exit(main())
