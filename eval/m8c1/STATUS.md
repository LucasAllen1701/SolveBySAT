# eval/m8c1: status

Updated 2026-11-25 22:11:28.

- sizes_N5: 1200 of 1200 (point, setting) records: ok 1200
  - checks of 4.4 (flags-off equal to 8b, bound check, excluded pairs): all pass
- sizes_N10: 1080 of 1200 (point, setting) records: ok 1080
- diag_N5 (M6 to M8, R1 and R2 on): 400 of 400 points
- rerun of 8a: 200 of 200 runs: crash 64, no_proof_le_Nmax 6, proved 71, timeout 59
  - stops: 0
  - rerun sizes: 372 records
