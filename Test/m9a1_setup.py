#!/usr/bin/env python3
"""9a-1 (M9_PLAN 2.2): the spec files of the 8a checks, from a worktree of tag m8-data.

  python3 Test/m9a1_setup.py M8DATA_WORKTREE

writes
  eval/m9a1/specs_count.jsonl  milestone 7's spec of each of the 200 goals of eval/m8a/specs.jsonl,
                               in 8a's order (for `eval_run iffeq-count`)
  eval/m9a1/specs_8.jsonl      milestone 7's spec of the 8 goals of the table in M9_PLAN 2.2, in the
                               table's order, with the baselines off (for `Test/eval_driver.py run`)
  eval/m9a1/inputs.md5         the md5 sums of the inputs read

Milestone 7's specs are `eval/m8a/inputs/specs_full.jsonl` on m8-data (a copy of m7-data's
`eval/specs_full.jsonl`; its md5 is checked against `eval/m8a/inputs/MD5SUMS`).
"""
import hashlib, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "eval", "m9a1")

# M9_PLAN 2.2: the 8 goals whose 8a proof used only a `propext` equation, with 8a's N and the N expected
EIGHT = [
    ("B/Std.DTreeMap.Raw.mem_of_mem_union_of_not_mem_left/5", 1, 1),
    ("B/BitVec.not_self_ne/2", 1, 1),
    ("B/Std.TreeMap.inter_equiv_empty_comm/14", 2, 1),
    ("B/Std.DHashMap.getKey?_eq_some_getKeyD/3", 2, 1),
    ("B/String.Slice.Pos.next_eq_iff/21", 3, 3),
    ("B/UInt64.lt_add_one/7", 1, 1),
    ("B/UInt64.toUInt8_le/11", 1, 1),
    ("B/Std.TreeMap.inter_equiv_empty_comm/13", 2, 1),
]


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def main():
    w = sys.argv[1]
    s8a = os.path.join(w, "eval/m8a/specs.jsonl")
    sfull = os.path.join(w, "eval/m8a/inputs/specs_full.jsonl")
    sums = dict(reversed(l.split()) for l in open(os.path.join(w, "eval/m8a/inputs/MD5SUMS")) if l.strip())
    if sums.get("specs_full.jsonl") != md5(sfull):
        print("STOP: specs_full.jsonl does not match eval/m8a/inputs/MD5SUMS"); return 5
    m7 = {j["key"]: j for j in map(json.loads, open(sfull))}
    a8 = [json.loads(l) for l in open(s8a) if l.strip()]
    if len(a8) != 200:
        print(f"STOP: {len(a8)} specs in eval/m8a/specs.jsonl, not 200"); return 5
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "specs_count.jsonl"), "w") as f:
        for s in a8:
            k = s["key"][len("m8a:"):]
            f.write(json.dumps(dict(m7[k], baselines=False), sort_keys=True) + "\n")
    with open(os.path.join(OUT, "specs_8.jsonl"), "w") as f:
        for gid, _, _ in EIGHT:
            f.write(json.dumps(dict(m7["main:" + gid], baselines=False), sort_keys=True) + "\n")
    with open(os.path.join(OUT, "inputs.md5"), "w") as f:
        f.write(f"{md5(s8a)}  m8-data:eval/m8a/specs.jsonl\n{md5(sfull)}  m8-data:eval/m8a/inputs/specs_full.jsonl\n")
    print(f"wrote {len(a8)} count specs and {len(EIGHT)} run specs to eval/m9a1/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
