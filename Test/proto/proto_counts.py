"""Print the prototype's CNF size (vars, clauses) for each forest test T1-T9 and N = 1..6.

Used to generate the expected-size table in Test/M1.lean. Runs reference/enc.py unchanged
except for one patch: `height` is replaced by the intended template height (a variable
leaf counts 1, a constant 0). The prototype's own `height` recurses into Python strings,
so a variable named with two or more characters (T6's `cc`) counts 2 instead of 1; see
NOTES.md, milestone 1.

Usage: python3 Test/proto/proto_counts.py   (from the repository root)
"""
import os, re, sys
REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'reference')
sys.path.insert(0, REF)
import enc

def height(t):
    if enc.is_var(t): return 1
    return 0 if len(t) == 1 else 1 + max(height(a) for a in t[1:])
enc.height = height

src = open(os.path.join(REF, 'tests.py')).read()
body = src[src.index('# T1'):src.index("print('all pass'")]
body = "\n".join(l for l in body.splitlines() if not re.match(r'^(check\(|F1, i1 =)', l))
ns = dict(vars(enc)); ns['c'] = lambda s: (s,); ns['le'] = lambda a, b: ('le', a, b)
exec(body, ns)
tests = [('T1', ns['t1']), ('T2', ns['t2']), ('T2b', lambda: ns['t2'](True)), ('T3', ns['t3']),
         ('T3b', lambda: ns['t3'](True)), ('T4', ns['t4']), ('T4b', lambda: ns['t4'](True)),
         ('T5', ns['t5']), ('T6', ns['t6']), ('T6b', lambda: ns['t6'](True)), ('T7', ns['t7']),
         ('T8', ns['t8']), ('T9', ns['t9'])]
for name, mk in tests:
    row = []
    for N in range(1, 7):
        F, _, _ = enc.encode(mk(), N)
        row.append(f"({F.n}, {len(F.cl)})")
    print(f'  ("{name}", #[{", ".join(row)}]),')
