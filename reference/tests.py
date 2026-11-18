from enc import *
import time
c = lambda s: (s,)
def le(a, b): return ('le', a, b)
def first_sat(mk, lo, hi, **kw):
    for n in range(lo, hi + 1):
        t, F, info = solve(mk(), n, **kw)
        if t: return n, t, F, info
    return None, None, F, info

results = []
def check(name, mk, expect, hi=6, **kw):
    t0 = time.time(); n, t, F, info = first_sat(mk, 1, hi, **kw)
    ok = (n == expect)
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {name}: min N = {n} (expected {expect}) {t or ''}  [{time.time()-t0:.1f}s, last CNF {F.n} vars {len(F.cl)} clauses]")
    return F, info

# T1 two uses of le_trans with different middle terms
def t1():
    x, y, z, w = V('x'), V('y'), V('z'), V('w')
    g = Goal(le(x, w), eig=['x', 'y', 'z', 'w'], hyps=[Clause('h1', le(x, y)), Clause('h2', le(y, z)), Clause('h3', le(z, w))])
    tr = Clause('le_trans', le(V('a'), V('c')), vars=['a', 'b', 'c'], prems=[Goal(le(V('a'), V('b'))), Goal(le(V('b'), V('c')))])
    return Problem(g, [tr])
F1, i1 = check('T1 le_trans chain', t1, 5)

# T2 hypothesis used outside its branch must be rejected
def t2(extra=False):
    m = Clause('m', c('C'), prems=[Goal(c('B'), hyps=[Clause('ha', c('A'))]), Goal(c('A'))])
    bb = Clause('bb', c('B'), prems=[Goal(c('A'))])
    return Problem(Goal(c('C')), [m, bb] + ([Clause('a', c('A'))] if extra else []))
check('T2 out-of-scope hypothesis', t2, None)
check('T2b with A available', lambda: t2(True), 4)

# T3 eigenvariable escaping its scope: exists x, forall y, x = y
def t3(legit=False):
    inner = Goal(('Eq', V('y'), V('y')) if legit else ('Eq', V('x'), V('y')), eig=['y'])
    ex = Clause('ex', c('Goal'), vars=[] if legit else ['x'], prems=[inner])
    refl = Clause('refl', ('Eq', V('z'), V('z')), vars=['z'])
    return Problem(Goal(c('Goal')), [ex, refl])
check('T3 eigenvariable escape', t3, None)
check('T3b forall y, y = y', lambda: t3(True), 2)

# T4 an argument left undetermined
def t4(fixed=False):
    h = Clause('h', c('P0'), vars=['y'], prems=[Goal(('Q', V('y')))])
    q = Clause('q', ('Q', c('k'))) if fixed else Clause('q', ('Q', V('z')), vars=['z'])
    return Problem(Goal(c('P0')), [h, q])
check('T4 undetermined argument', t4, None)
check('T4b determined argument', lambda: t4(True), 2)

# T5 occurs check
def t5():
    r = Clause('r', ('R', V('x'), ('f', V('x'))), vars=['x'])
    g = Clause('g', c('G0'), vars=['y'], prems=[Goal(('R', V('y'), V('y')))])
    return Problem(Goal(c('G0')), [r, g])
check('T5 occurs check', t5, None)

# T6 constraints that are pairwise fine but jointly inconsistent
def t6(consistent=False):
    k = Clause('k', c('G0'), vars=['b', 'cc'], prems=[Goal(('A1', V('b'), V('cc'))), Goal(('A2', V('cc'))), Goal(('A3', V('b')))])
    f1 = Clause('f1', ('A1', ('f', V('u')), V('u')), vars=['u'])
    f2 = Clause('f2', ('A2', c('zero')))
    f3 = Clause('f3', ('A3', ('f', c('zero') if consistent else c('one'))))
    return Problem(Goal(c('G0')), [k, f1, f2, f3])
check('T6 jointly inconsistent', t6, None)
check('T6b consistent', lambda: t6(True), 4)

# T7 nested intro: local hypothesis mentioning an ancestor's metavariable
def t7():
    m = Clause('m', ('R', V('x')), vars=['x'], prems=[Goal(('Q', V('x'), V('y')), eig=['y'], hyps=[Clause('hp', ('P', V('x'), V('y')))])])
    pq = Clause('pq', ('Q', V('s'), V('t')), vars=['s', 't'], prems=[Goal(('P', V('s'), V('t')))])
    return Problem(Goal(('R', V('a')), eig=['a']), [m, pq])
check('T7 nested intro', t7, 3)

# T8 same local hypothesis used twice with different instantiations
def t8():
    hf = Clause('hf', ('P', ('s', V('n'))), vars=['n'], prems=[Goal(('P', V('n')))])
    g = Goal(('P', ('s', ('s', V('o')))), eig=['o'], hyps=[Clause('h0', ('P', V('o'))), hf])
    return Problem(g, [])
check('T8 local hypothesis reused', t8, 3)

# T9 two live instances of the same local hypothesis; the outer one is needed inside the inner scope
def t9():
    L = Clause('L', ('F', V('x')), vars=['x'], prems=[Goal(('B', V('x')), hyps=[Clause('hP', ('P', V('x')))])])
    r1 = Clause('r1', ('B', c('ka')), prems=[Goal(('F', c('kb')))])
    r2 = Clause('r2', ('B', c('kb')), prems=[Goal(('P', c('ka'))), Goal(('P', c('kb')))])
    return Problem(Goal(('F', c('ka'))), [L, r1, r2])
check('T9 outer instance of a re-introduced hypothesis', t9, 6)
print('all pass' if all(results) else 'FAILURES')
print('T1 at N=5:', i1, dict(F1.count), 'vars', F1.n, 'clauses', len(F1.cl))
