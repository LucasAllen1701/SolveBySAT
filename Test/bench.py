#!/usr/bin/env python3
"""Milestone 6 benchmark (requirement 6): SPEC §7.3's instances (1, 5 and 9 lemmas at
N = 5, 8, 12), L1 (N = 5) and D3 (N = 3), before (all refinements off) and after (all on).

Encode time is measured inside the encoder (`bench`, Test/Bench.lean). Wall time and peak
memory (ru_maxrss of the process, via os.wait4) are measured here for the encoder process
and for CaDiCaL on the written DIMACS file.

Usage: python3 Test/bench.py   (from the repository root, after `lake build bench`)
"""
import os, subprocess, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
toolchain = open(os.path.join(ROOT, 'lean-toolchain')).read().strip().replace('leanprover/lean4:', 'leanprover--lean4---')
SOLVER = os.environ.get('SOLVE_BY_SAT_SOLVER') or os.path.expanduser(f'~/.elan/toolchains/{toolchain}/bin/cadical')
BENCH = os.path.join(ROOT, '.lake/build/bin/bench')

def run(cmd):
    """Run cmd; return (exit code, stdout, wall seconds, peak RSS in MB)."""
    t0 = time.monotonic()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    out = p.stdout.read()
    _, status, ru = os.wait4(p.pid, 0)
    return os.waitstatus_to_exitcode(status), out, time.monotonic() - t0, ru.ru_maxrss / 1024

def main():
    tmp = tempfile.mkdtemp()
    cnf = os.path.join(tmp, 'p.cnf')
    print('| instance | N | | vars | clauses | encode ms | encoder peak MB | solve s | solver peak MB | answer |')
    print('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
    cases = [('forest', str(l), n, f'§7.3, {l} lemma' + ('s' if l > 1 else '')) for l in (1, 5, 9) for n in (5, 8, 12)]
    cases += [('lean', 'L1', 5, 'L1'), ('lean', 'D3', 3, 'D3')]
    for kind, what, n, label in cases:
        for cfg, when in (('none', 'before'), ('all', 'after')):
            code, out, _, encmb = run([BENCH, kind, what, str(n), cfg, cnf])
            assert code == 0, (kind, what, n, cfg, out)
            nv, ncl, ms = out.split()
            scode, _, secs, solmb = run([SOLVER, '-q', cnf])
            ans = {10: 'SAT', 20: 'UNSAT'}.get(scode, f'exit {scode}')
            print(f'| {label} | {n} | {when} | {int(nv):,} | {int(ncl):,} | {ms} | {encmb:.0f} | {secs:.2f} | {solmb:.0f} | {ans} |', flush=True)
    os.remove(cnf); os.rmdir(tmp)

main()
