#!/usr/bin/env python3
"""EVAL_PLAN §10.7: merge the type-template rerun into the full 7b run.

  python3 eval/merge.py             write eval/final/results.jsonl and eval/final/merge_report.txt

Pre-registered in NOTES.md ("10.7: merge rule") before any rerun result existed.

Inputs: eval/full/results.jsonl (the full 7b run), eval/specs_rerun.jsonl (the rerun set:
`rerun_set` = `changed` or `spot`), eval/rerun/results.jsonl and eval/rerun/header.json.

Rule:
1. Every one of the 6,300 keys of eval/specs_full.jsonl gets exactly one final line.
2. `changed` (the goal's compiled forest changed with the fix): the final line is the rerun line,
   with the original line's baseline fields (`baselines`, `rss_before_baselines_mb`,
   `rss_after_baselines_mb`, `hwm_after_baselines_mb`) put back. The rerun ran the SAT phase
   only, so it has no baselines of its own; every solve_by_sat field (outcome, N, H_accepted,
   H_rejected, per_N, families, sizes, times, skeleton, reason, and the crash fields cause,
   last_N, phase, elapsed_s) comes from the rerun. A changed key without a rerun line is an error.
3. `spot` (forest unchanged): the original line stands. The rerun line is used only for the spot
   check of decision 5. It must have the same outcome, and when proved the same N, unless either
   run's outcome is a resource limit (`crash`, `timeout`, `memout`). A failure is reported and
   the script exits with status 1 (stop and investigate).
4. Every other key: the original line stands.
5. Each final line gets `code_version`: {"source": "full"|"rerun", "commit": …}. For original
   lines, the commit is the one that wrote it (NOTES.md, "7b: full run, final record"):
   lines 1–773 of eval/full/results.jsonl: c3a3ec8 (the start commit, recorded in the header
   as 6ef9ea2); lines 774–4245: 2394acf (first decoder fix); lines 4246–6300: f35c182 (second
   decoder fix). Rerun lines: the commit in eval/rerun/header.json. The line numbers are
   checked by the two recomputed decoder-bug goals, which open the second and third segments.
6. Lines are written in the order of eval/specs_full.jsonl, so the file is deterministic.
"""
import json, os, sys

E = os.path.dirname(os.path.abspath(__file__))
BASELINE_FIELDS = ("baselines", "rss_before_baselines_mb", "rss_after_baselines_mb", "hwm_after_baselines_mb")
LIMITS = ("crash", "timeout", "memout")
SEGMENTS = [(1, 773, "c3a3ec8"), (774, 4245, "2394acf"), (4246, 6300, "f35c182")]


def load(p):
    return [json.loads(l) for l in open(p) if l.strip()]


def main():
    specs = load(os.path.join(E, "specs_full.jsonl"))
    full_lines = load(os.path.join(E, "full", "results.jsonl"))
    keys = [r["key"] for r in full_lines]
    assert keys[773] == "main:A/List.getLast_eq_head_reverse", "segment 2 does not start at line 774"
    assert keys[4245] == "main:B/Nat.pred_eq_self_iff/22", "segment 3 does not start at line 4246"
    full = {}
    for i, r in enumerate(full_lines, 1):
        commit = next(c for lo, hi, c in SEGMENTS if lo <= i <= hi)
        full[r["key"]] = (r, commit)
    rerun_specs = {s["key"]: s["rerun_set"] for s in load(os.path.join(E, "specs_rerun.jsonl"))}
    rr_path = os.path.join(E, "rerun", "results.jsonl")
    rerun = {r["key"]: r for r in load(rr_path)} if os.path.exists(rr_path) else {}
    hdr_path = os.path.join(E, "rerun", "header.json")
    rerun_commit = json.load(open(hdr_path)).get("git_commit", "?")[:7] if os.path.exists(hdr_path) else None
    out, report, errors = [], [], []
    spot_ok = spot_bad = 0
    for s in specs:
        k = s["key"]
        orig, commit = full[k]
        kind = rerun_specs.get(k)
        if kind == "changed":
            if k not in rerun:
                errors.append(f"changed key without a rerun result: {k}")
                continue
            r = dict(rerun[k])
            for f in BASELINE_FIELDS:
                if f in orig:
                    r[f] = orig[f]
                else:
                    r.pop(f, None)
            r["code_version"] = {"source": "rerun", "commit": rerun_commit}
            out.append(r)
        else:
            r = dict(orig)
            r["code_version"] = {"source": "full", "commit": commit}
            out.append(r)
            if kind == "spot":
                if k not in rerun:
                    errors.append(f"spot-check key without a rerun result: {k}")
                    continue
                a, b = orig["outcome"], rerun[k]["outcome"]
                same = a == b and (a != "proved" or orig.get("N") == rerun[k].get("N"))
                if same or a in LIMITS or b in LIMITS:
                    spot_ok += 1
                    if not same:
                        report.append(f"spot {k}: {a} → {b} (a resource limit, allowed)")
                else:
                    spot_bad += 1
                    report.append(f"SPOT MISMATCH {k}: {a} (N {orig.get('N')}) → {b} (N {rerun[k].get('N')})")
    os.makedirs(os.path.join(E, "final"), exist_ok=True)
    with open(os.path.join(E, "final", "results.jsonl"), "w") as f:
        for r in out:
            f.write(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n")
    lines = [f"final lines: {len(out)} (specs {len(specs)})",
             f"changed: {sum(1 for v in rerun_specs.values() if v == 'changed')}, spot: {sum(1 for v in rerun_specs.values() if v == 'spot')}",
             f"spot check: {spot_ok} pass, {spot_bad} fail", *report, *errors]
    open(os.path.join(E, "final", "merge_report.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines[:3] + errors[:5]))
    return 1 if errors or spot_bad else 0


if __name__ == "__main__":
    sys.exit(main())
