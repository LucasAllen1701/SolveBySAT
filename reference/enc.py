"""Reference prototype for the Solve By SAT specification (milestone 1: clause forests without Lean).

It is the executable form of spec sections 5 and 6.1-6.8 for untyped first-order clause forests:
node assignment, tree shape, context, matching, decomposition, links, eigenvariables / occurs
check / scope, and groundness. Not covered: typing in the groundness rule, connectives, universe
levels, binders inside terms (the "open" bit), data nodes, pruning.

Terms: ('?', name) is a variable; (sym, arg, ...) is a rigid term; (sym,) is a constant.
Binder names must be unique across the whole problem.
Slots are ('S', node, side, name) with side 'g' (goal frame) or 'c' (clause frame).
Run tests.py for the fixed tests and `python3 diff.py 1500 5` for the differential test.
The solver is the small CDCL in cdcl.c (gcc -O2 -o cdcl cdcl.c); any DIMACS solver can be substituted.
"""
import math, subprocess, collections

V = lambda n: ('?', n)
def is_var(t): return t[0] == '?'
def vars_of(t):
    if is_var(t): return {t[1]}
    s = set()
    for a in t[1:]: s |= vars_of(a)
    return s
def height(t): return 0 if len(t) == 1 else 1 + max(height(a) for a in t[1:])

class Goal:
    def __init__(s, tgt, eig=(), hyps=()): s.tgt = tgt; s.eig = list(eig); s.hyps = list(hyps)
class Clause:
    def __init__(s, name, head, vars=(), prems=()): s.name = name; s.head = head; s.vars = list(vars); s.prems = list(prems)

class Problem:
    def __init__(s, goal, clauses):
        s.goals = []; s.clauses = []
        def rg(g, env):
            g.id = len(s.goals); s.goals.append(g); g.env = frozenset(env)
            assert vars_of(g.tgt) <= set(env) | set(g.eig), g.tgt
            for h in g.hyps: rc(h, set(env) | set(g.eig), g)
        def rc(c, env, loc):
            c.id = len(s.clauses); s.clauses.append(c); c.env = frozenset(env); c.local_of = loc
            assert vars_of(c.head) <= set(env) | set(c.vars), c.head
            for p in c.prems: rg(p, set(env) | set(c.vars))
        rg(goal, set())
        for c in clauses: rc(c, set(), None)
        B = [b for g in s.goals for b in g.eig] + [b for c in s.clauses for b in c.vars]
        assert len(set(B)) == len(B), "binder names must be unique"

class CNF:
    def __init__(s): s.n = 0; s.cl = []; s.fam = 'misc'; s.count = collections.Counter()
    def new(s): s.n += 1; return s.n
    def add(s, *lits):
        out = set()
        for l in lits:
            if l is True: return
            if l is False: continue
            if -l in out: return
            out.add(l)
        s.cl.append(tuple(out)); s.count[s.fam] += 1
def neg(l): return (not l) if isinstance(l, bool) else -l
def bits(x, w): return [bool((x >> (w - 1 - i)) & 1) for i in range(w)]

def encode(P, N, groundness=True, scope=True, occurs=True):
    F = CNF(); C = P.clauses; G = P.goals
    A = max([len(c.prems) for c in C] + [0])
    cl = [[F.new() for _ in C] for _ in range(N)]
    gp = [[F.new() for _ in G] for _ in range(N)]
    act = [F.new() for _ in range(N)]
    y = {(a, b, k): F.new() for a in range(N) for b in range(a + 1, N) for k in range(A)}
    anc = {(g, b): F.new() for g in range(N) for b in range(g + 1, N)}
    u = {(b, g): F.new() for b in range(N) for g in range(b + 1)}
    def eq(cond, X, Y):
        nc = [neg(c) for c in cond]
        for a, b in zip(X, Y):
            ab, bb = isinstance(a, bool), isinstance(b, bool)
            if ab and bb:
                if a != b: F.add(*nc); return
            elif ab: F.add(*nc, b if a else neg(b))
            elif bb: F.add(*nc, a if b else neg(a))
            elif a != b: F.add(*nc, neg(a), b); F.add(*nc, a, neg(b))
    def lt(cond, X, Y):
        w = len(X); L = [F.new() for _ in range(w)] + [False]
        F.add(*[neg(c) for c in cond], L[0])
        for i in range(w):
            F.add(neg(L[i]), neg(X[i]), Y[i]); F.add(neg(L[i]), neg(X[i]), L[i + 1]); F.add(neg(L[i]), Y[i], L[i + 1])
    def amo(ls):
        for i in range(len(ls)):
            for j in range(i + 1, len(ls)): F.add(-ls[i], -ls[j])

    # ---- static tables: symbols, ground terms, widths
    syms = {('EV', 0): 0}; ground = {}; ground_values = set(); nrig = 0; maxh = 0
    def scan(t, root):
        nonlocal nrig, maxh
        if is_var(t): return
        syms.setdefault((t[0], len(t) - 1), len(syms))
        if not vars_of(t):
            ground.setdefault(t, len(ground))
            if not root: ground_values.add(t)
        else: nrig += 1
        for a in t[1:]: scan(a, False)
    for t in [g.tgt for g in G] + [c.head for c in C]:
        maxh = max(maxh, height(t))
        for x in t[1:]: scan(x, False)
    eigs = [(g, b) for g in G for b in g.eig]
    SB = max(1, math.ceil(math.log2(len(syms) + 1)))
    K = N * nrig + len(ground) + N * len(eigs) + 1
    IB = max(1, math.ceil(math.log2(K + 1)))
    RB = max(1, math.ceil(math.log2(N * (maxh + 1) + 2)))
    W = SB + IB + RB + N
    rank = lambda L: L[SB + IB:SB + IB + RB]
    Eset = lambda L: L[SB + IB + RB:]
    evcode = {}
    labs = {}
    def lab(o):
        if o not in labs:
            if o[0] == 'G':
                t = o[1]; labs[o] = bits(syms[(t[0], len(t) - 1)], SB) + bits(ground[t], IB) + bits(height(t), RB) + [False] * N
            elif o[0] == 'R': labs[o] = bits(syms[o[4]], SB) + [F.new() for _ in range(IB + RB + N)]
            else: labs[o] = [F.new() for _ in range(W)]
        return labs[o]
    children = {}; actlit = {}; rigid = []
    def build(a, tid, t, path, al):
        if is_var(t): return ('S', a, tid[0], t[1])
        if not vars_of(t):
            o = ('G', t)
            if o not in children:
                children[o] = [build(a, tid, x, path + (i,), al) for i, x in enumerate(t[1:])]; actlit[o] = True
            return o
        o = ('R', a, tid, path, (t[0], len(t) - 1))
        children[o] = [build(a, tid, x, path + (i,), al) for i, x in enumerate(t[1:])]
        actlit[o] = al; rigid.append(o); return o
    root = {}
    for a in range(N):
        for g in G: root[(a, 'g', g.id)] = [build(a, ('g', g.id), x, (i,), gp[a][g.id]) for i, x in enumerate(g.tgt[1:])]
        for c in C: root[(a, 'c', c.id)] = [build(a, ('c', c.id), x, (i,), cl[a][c.id]) for i, x in enumerate(c.head[1:])]

    F.fam = '1 node assignment'
    for a in range(N):
        amo(cl[a]); F.add(-act[a], *cl[a])
        for c in C: F.add(-cl[a][c.id], act[a])
        amo(gp[a]); F.add(-act[a], *gp[a])
        for g in G: F.add(-gp[a][g.id], act[a])
        if a: F.add(-act[a], act[a - 1])
    F.add(act[0]); F.add(gp[0][0])
    F.fam = '2 tree shape'
    for b in range(1, N):
        ps = [y[(a, b, k)] for a in range(b) for k in range(A)]
        F.add(-act[b], *ps); amo(ps)
        for a in range(b):
            for k in range(A):
                F.add(-y[(a, b, k)], act[b]); F.add(-y[(a, b, k)], act[a])
    for a in range(N):
        for k in range(A):
            amo([y[(a, b, k)] for b in range(a + 1, N)])
            for c in C:
                if k < len(c.prems):
                    F.add(-cl[a][c.id], *[y[(a, b, k)] for b in range(a + 1, N)])
                    for b in range(a + 1, N): F.add(-cl[a][c.id], -y[(a, b, k)], gp[b][c.prems[k].id])
                else:
                    for b in range(a + 1, N): F.add(-cl[a][c.id], -y[(a, b, k)])
    F.fam = '3 context (local hypotheses, ancestors)'
    for b in range(N):
        amo([u[(b, g)] for g in range(b + 1)])
        for c in C:
            if c.local_of is None:
                for g in range(b + 1): F.add(-cl[b][c.id], -u[(b, g)])
            else:
                F.add(-cl[b][c.id], *[u[(b, g)] for g in range(b + 1)])
                for g in range(b + 1): F.add(-u[(b, g)], -cl[b][c.id], gp[g][c.local_of.id])
        for g in range(b): F.add(-u[(b, g)], anc[(g, b)])
    for (g, b) in anc:
        F.add(-anc[(g, b)], act[b])
        for a in range(b):
            for k in range(A):
                if a < g: F.add(-anc[(g, b)], -y[(a, b, k)])
                elif a > g: F.add(-anc[(g, b)], -y[(a, b, k)], anc[(g, a)])
    F.fam = '4 matching'
    for a in range(N):
        for g in G:
            for c in C:
                if (g.tgt[0], len(g.tgt)) != (c.head[0], len(c.head)): F.add(-gp[a][g.id], -cl[a][c.id])
                else:
                    for o1, o2 in zip(root[(a, 'g', g.id)], root[(a, 'c', c.id)]): eq([gp[a][g.id], cl[a][c.id]], lab(o1), lab(o2))
    F.fam = '5 decomposition'
    bysym = collections.defaultdict(list)
    for o in rigid: bysym[o[4]].append(o)
    for o in children:
        if o[0] == 'G' and children[o]: bysym[(o[1][0], len(o[1]) - 1)].append(o)
    npairs = 0
    for s, os_ in bysym.items():
        for i in range(len(os_)):
            for j in range(i + 1, len(os_)):
                o1, o2 = os_[i], os_[j]
                if o1[0] == 'G' and o2[0] == 'G': continue
                ds = []; ok = True
                for x, z in zip(lab(o1), lab(o2)):
                    xb, zb = isinstance(x, bool), isinstance(z, bool)
                    if xb and zb:
                        if x != z: ok = False; break
                    elif xb: ds.append(neg(z) if x else z)
                    elif zb: ds.append(neg(x) if z else x)
                    else:
                        d = F.new(); F.add(-d, x, z); F.add(-d, -x, -z); ds.append(d)
                if not ok: continue
                npairs += 1
                m = F.new(); F.add(neg(actlit[o1]), neg(actlit[o2]), *ds, m)
                for c1, c2 in zip(children[o1], children[o2]): eq([m], lab(c1), lab(c2))
    F.fam = '6 links (environment copies)'
    for a in range(N):
        for b in range(a + 1, N):
            for c in C:
                for k in range(len(c.prems)):
                    for v in sorted(c.env | set(c.vars)):
                        eq([cl[a][c.id], y[(a, b, k)]], lab(('S', b, 'g', v)), lab(('S', a, 'c', v)))
    for b in range(N):
        for g in range(b + 1):
            for c in C:
                if c.local_of is not None:
                    for v in sorted(c.env): eq([u[(b, g)], cl[b][c.id]], lab(('S', b, 'c', v)), lab(('S', g, 'g', v)))
    F.fam = '7 eigenvariables, occurs check, scope'
    for a in range(N):
        for i, (g, b) in enumerate(eigs):
            code = 1 + a * len(eigs) + i
            const = bits(0, SB) + bits(code, IB) + bits(0, RB) + [x == a for x in range(N)]
            eq([gp[a][g.id]], lab(('S', a, 'g', b)), const)
    for o in rigid:
        al = actlit[o]
        for ch in children[o]:
            if occurs: lt([al], rank(lab(ch)), rank(lab(o)))
            for g in range(N): F.add(neg(al), neg(Eset(lab(ch))[g]), Eset(lab(o))[g])
    if scope:
        for a in range(N):
            for c in C:
                for b in c.vars:
                    E = Eset(lab(('S', a, 'c', b)))
                    for g in range(N):
                        if g > a: F.add(-cl[a][c.id], neg(E[g]))
                        elif g < a: F.add(-cl[a][c.id], neg(E[g]), anc[(g, a)])
    F.fam = '8 groundness'
    if groundness:
        cands = [(o, actlit[o]) for o in rigid] + [(('G', t), True) for t in ground_values] + \
                [(('S', a, 'g', b), gp[a][g.id]) for a in range(N) for (g, b) in eigs]
        for a in range(N):
            for c in C:
                for b in c.vars:
                    svs = []
                    for o, al in cands:
                        sv = F.new(); F.add(-sv, al); eq([sv], lab(('S', a, 'c', b)), lab(o)); svs.append(sv)
                    F.add(-cl[a][c.id], *svs)
    info = dict(W=W, SB=SB, IB=IB, RB=RB, pairs=npairs, rigid=len(rigid), ground=len(ground))
    return F, dict(cl=cl, gp=gp, act=act, y=y, u=u, A=A), info

def solve(P, N, **kw):
    F, vs, info = encode(P, N, **kw)
    with open('/tmp/p.cnf', 'w') as f:
        f.write(f"p cnf {F.n} {len(F.cl)}\n"); f.writelines(" ".join(map(str, c)) + " 0\n" for c in F.cl)
    r = subprocess.run(['./cdcl', '/tmp/p.cnf'], capture_output=True, text=True)
    if 'UNSAT' in r.stdout: return None, F, info
    m = {abs(int(x)): int(x) > 0 for x in r.stdout.split('\n')[1].split()[1:-1]}
    assert all(any((l > 0) == m[abs(l)] for l in c) for c in F.cl)
    def term(a):
        c = next(c for c in P.clauses if m[vs['cl'][a][c.id]])
        kids = []
        for k in range(len(c.prems)):
            b = next(b for b in range(a + 1, N) if m[vs['y'][(a, b, k)]]); kids.append(term(b))
        g = next(g for g in P.goals if m[vs['gp'][a][g.id]])
        s = c.name + ("(" + ", ".join(kids) + ")" if kids else "")
        bs = g.eig + [h.name for h in g.hyps]
        return ("fun " + " ".join(bs) + " => " if bs else "") + s
    return term(0), F, info
