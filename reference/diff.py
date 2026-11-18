"""Differential test: SAT encoding (groundness off) vs. a brute-force backchaining prover with real unification."""
import random, sys, time
from enc import *

def ref(P, N):
    uid = [0]; allowed = {}
    globals_ = [c for c in P.clauses if c.local_of is None]
    def walk(t, s):
        while is_var(t) and t[1] in s: t = s[t[1]]
        return t
    def occurs(v, t, s):
        t = walk(t, s)
        return t[1] == v if is_var(t) else any(occurs(v, a, s) for a in t[1:])
    def unify(a, b, s):
        a = walk(a, s); b = walk(b, s)
        if is_var(a) and is_var(b) and a[1] == b[1]: return s
        if is_var(a):
            if occurs(a[1], b, s): return None
            s2 = dict(s); s2[a[1]] = b; return s2
        if is_var(b): return unify(b, a, s)
        if a[0] != b[0] or len(a) != len(b): return None
        for x, z in zip(a[1:], b[1:]):
            s = unify(x, z, s)
            if s is None: return None
        return s
    def inst(t, env): return env[t[1]] if is_var(t) else (t[0],) + tuple(inst(a, env) for a in t[1:])
    def eigs_of(t, s):
        t = walk(t, s)
        if is_var(t): return set()
        r = {t[0]} if t[0].startswith('ev#') else set()
        for a in t[1:]: r |= eigs_of(a, s)
        return r
    def prove(g, env, ctx, scope, s, budget):
        if budget < 1: return
        env_g = dict(env); sc = set(scope)
        for b in g.eig: uid[0] += 1; e = ('ev#%d' % uid[0],); env_g[b] = e; sc.add(e[0])
        ctx2 = ctx + [(h, env_g) for h in g.hyps]
        goal = inst(g.tgt, env_g)
        for (c, envc) in ctx2 + [(c, {}) for c in globals_]:
            env_c = dict(envc)
            for v in c.vars: uid[0] += 1; env_c[v] = ('?', uid[0]); allowed[uid[0]] = frozenset(sc)
            s1 = unify(goal, inst(c.head, env_c), s)
            if s1 is None: continue
            def prems(i, s, used):
                if i == len(c.prems): yield s, used; return
                for s2, u2 in prove(c.prems[i], env_c, ctx2, sc, s, budget - used - (len(c.prems) - i - 1)):
                    yield from prems(i + 1, s2, used + u2)
            yield from prems(0, s1, 1)
    for s, used in prove(P.goals[0], {}, [], set(), {}, N):
        if all(eigs_of(('?', v), s) <= allowed[v] for v in allowed if v <= uid[0]): return True
    return False

def rnd_problem(rng):
    cnt = [0]
    def nm(p): cnt[0] += 1; return f"{p}{cnt[0]}"
    def term(vs, d=0):
        r = rng.random()
        if vs and r < 0.6: return V(rng.choice(sorted(vs)))
        if r < 0.85 or d >= 1: return (rng.choice(['k1', 'k1', 'k2']),)
        return ('f', term(vs, d + 1))
    def atom(vs):
        p = rng.choice(['P', 'P', 'Q'])
        return (p, term(vs), term(vs)) if p == 'Q' else (p, term(vs))
    def clause(env, depth):
        vs = [nm('v') for _ in range(rng.choice([0, 1, 1, 2]))]
        scope = set(env) | set(vs)
        prems = [goal(scope, depth + 1) for _ in range(rng.choice([0, 1, 1, 2]) if depth < 2 else 0)]
        return Clause(nm('c'), atom(scope), vars=vs, prems=prems)
    def goal(env, depth):
        eig = [nm('e')] if rng.random() < 0.35 else []
        scope = set(env) | set(eig)
        hyps = [clause(scope, depth + 1)] if (rng.random() < 0.35 and depth < 2) else []
        return Goal(atom(scope), eig=eig, hyps=hyps)
    return Problem(goal(set(), 0), [clause(set(), 0) for _ in range(rng.randint(3, 5))])

seeds = int(sys.argv[1]); maxN = int(sys.argv[2]); t0 = time.time()
mism = 0; nsat = 0; total = 0; minsizes = {}
for seed in range(seeds):
    P = rnd_problem(random.Random(seed))
    for N in range(1, maxN + 1):
        r = ref(P, N); t, F, info = solve(P, N, groundness=False)
        total += 1; nsat += bool(r)
        if r and seed not in minsizes: minsizes[seed] = N
        if bool(t) != r:
            mism += 1; print('MISMATCH seed', seed, 'N', N, 'ref', r, 'sat', t)
import collections
print(f"{total} comparisons, {nsat} provable instances, {mism} mismatches, min-size histogram {dict(collections.Counter(minsizes.values()))}, {time.time()-t0:.0f}s")
