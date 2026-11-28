# 9a-3 pilot: projection of the full run (M9_PLAN 4.5)

| group | pilot runs | mean s per run (a crash counted as the 300 s watchdog) | runs in the full run | projected h |
| --- | --- | --- | --- | --- |
| group 1 | 10 | 74.8 | 200 | 4.16 |
| rewrite_B | 5 | 17.8 | 100 | 0.49 |
| rewrite_A | 5 | 187.5 | 50 | 2.60 |
| control | 5 | 6.1 | 50 | 0.08 |

- Runs: 7.34 h projected (the driver adds a few seconds per shard).
- Sizes (N = 5 and the last N): 179 s for the pilot's 25 runs, 7.2 s per run: 0.79 h projected.
- **Total: 8.1 h** (the bound of 4.5 is about 24 h).
