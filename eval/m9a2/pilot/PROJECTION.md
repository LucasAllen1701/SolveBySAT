# 9a-2 measurement: pilot and projection (M9_PLAN 3.3)

Pilot: the first 20 points of `eval/m9a2/specs_points.jsonl` (10 goals, each with 8a's rules and without), at N = 5
and N = 10, settings `none` (all 20), `rw` and `rwnt` (the 10 points without rules), under the 2.5 GB cap, one
process at a time (`sizes_N5/`, `sizes_N10/` here). The recount `none` equals 8c-1's r1r2 counts at all 20 points
at both N.

Work time (encode + forest, s), and the projection to the 400 points by two scalings of each setting's pilot time:
by 8c-1's r1r2 time on the same points without rules (all 200 / pilot 10), and on the same points with 8a's rules.
The larger is used.

| N | setting | pilot s | scaled by points without rules | scaled by points with 8a's rules | projected s |
| --- | --- | --- | --- | --- | --- |
| 5 | none (400 points) | 53 | – | – | 1,207 (8c-1's own) |
| 5 | rw | 44 | 1,500 | 920 | 1,500 |
| 5 | rwnt | 38 | 1,290 | 790 | 1,290 |
| 10 | none (400 points) | 335 | – | – | 7,965 (8c-1's own) |
| 10 | rw | 264 | 10,500 | 5,140 | 10,500 |
| 10 | rwnt | 223 | 8,860 | 4,330 | 8,860 |

Diagnostics (M3 split by rule) at N = 5 for `rw` and `rwnt`: 8c-1's diag at N = 5 took 2,561 s for 400 points;
about 2,000 s each is assumed. Total about 35,000 s (about 10 h), below the 24 h of M9_PLAN 3.3: the run goes ahead
without a reduction.
