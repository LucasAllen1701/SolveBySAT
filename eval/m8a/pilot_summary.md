| group | goal | outcome | N (crash: last N reached) | rules | accepted rules | time s | clauses at last N | clauses at N = 5 | uses rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| rewrite_B | `B/String.Pos.startPos_lt_iff/6` | crash | 9 | 9 | 7 | 65.6 | 10478341 | 2633562 | – |
| rewrite_B | `B/Nat.add_max_add_right/11` | crash | 7 | 10 | 8 | 61.1 | 11943391 | 5502573 | – |
| rewrite_B | `B/Int.Internal.Linear.cooper_dvd_left_split_dvd2/37` | crash | 6 | 16 | 16 | 60.1 | 14953558 | 10077478 | – |
| rewrite_B | `B/Std.DTreeMap.Raw.mem_of_mem_union_of_not_mem_left/0` | crash | 3 | 19 | 17 | 34.0 | 13844135 | 42831618 | – |
| rewrite_B | `B/List.mergeSort_pair/30` | crash | 3 | 13 | 13 | 32.0 | 12771261 | 41263378 | – |
| rewrite_B | `B/Int.ediv_gcd_ne_zero_of_ne_zero_right/5` | proved | 2 | 5 | 5 | 0.5 | 98993 | 677043 | True |
| rewrite_B | `B/Std.Internal.List.length_insertListIfNewUnit_le/7` | crash | 5 | 11 | 9 | 42.3 | 12060983 | 12060983 | – |
| rewrite_B | `B/String.Slice.Pattern.Model.Char.isLongestRevMatchAtChain_iff/9` | crash | 6 | 10 | 8 | 45.6 | 9666682 | 6512298 | – |
| rewrite_B | `B/Std.DTreeMap.Raw.mem_of_mem_union_of_not_mem_left/5` | crash | 6 | 10 | 8 | 52.9 | 13346227 | 8962633 | – |
| rewrite_B | `B/List.isEmpty_eq_false_iff/2` | crash | 10 | 5 | 3 | 69.1 | 11819466 | 2336003 | – |
| rewrite_A | `A/Lean.Grind.CommRing.Poly.denote_mul` | crash | 5 | 14 | 14 | 53.6 | 16677643 | 16677643 | – |
| rewrite_A | `A/List.append_right_le_iff_of_length_eq` | crash | 3 | 12 | 10 | 45.6 | 26361570 | 85192581 | – |
| rewrite_A | `A/Lean.Grind.Field.NormNum.sub_eq` | crash | 6 | 10 | 8 | 65.1 | 15670345 | 10556853 | – |
| rewrite_A | `A/Std.TreeSet.max?_eq_back?_toArray` | crash | 6 | 9 | 9 | 55.1 | 13627666 | 8806388 | – |
| rewrite_A | `A/Vector.getElem?_setIfInBounds_ne` | crash | 3 | 12 | 12 | 30.7 | 12622143 | 39083563 | – |
| control | `B/Array.getElem?_toList/1` | proved | 1 | 6 | 6 | 0.3 | 42094 | 1285353 | False |
| control | `B/Std.DHashMap.Raw.getD_alter_self/2` | crash | 4 | 8 | 7 | 40.6 | 12015436 | 19438391 | – |
| control | `B/UInt16.sizeOf/18` | proved | 2 | 3 | 3 | 0.4 | 39282 | 231788 | False |
| control | `A/Int64.ofIntLE_sub` | proved | 5 | 8 | 8 | 12.7 | 2981513 | 2981513 | False |
| control | `B/Std.ExtDTreeMap.getKeyD_minKeyD/3` | proved | 2 | 7 | 5 | 7.4 | 2489298 | 20863061 | False |

- `B/Int.ediv_gcd_ne_zero_of_ne_zero_right/5` N = 2: `fun b#0 a#1 h => _probe.Nat.cast.congr.«2»(Int.gcd_comm)`
- `B/Array.getElem?_toList/1` N = 1: `fun α#0 xs#1 i#2 h => h`
- `B/UInt16.sizeOf/18` N = 2: `fun a#0 toBitVec#1 h2@g0 => Eq.symm(h2@g0)`
- `A/Int64.ofIntLE_sub` N = 5: `fun a#0 b#1 hab₁ hab₂ => Eq.trans(Int64.ofIntLE_eq_ofInt(hab₁, hab₂), Int64.ofInt_sub)`
- `B/Std.ExtDTreeMap.getKeyD_minKeyD/3` N = 2: `fun α#0 β#1 cmp#2 t#3 fallback#4 fallback'#5 x#6 inst4@g0 he he => Std.ExtDTreeMap.isEmpty_eq_false_iff(inst4@g0)`

| control goal | original N | outcome | N | clauses at original N, 8a | milestone 7 | ratio |
| --- | --- | --- | --- | --- | --- | --- |
| `B/Array.getElem?_toList/1` | 1 | proved | 1 | 42094 | 1,079 | 39.0× |
| `B/Std.DHashMap.Raw.getD_alter_self/2` | 6 | crash | 4 | 28946553 | 8,053,878 | 3.6× |
| `B/UInt16.sizeOf/18` | 2 | proved | 2 | 39282 | 3,234 | 12.1× |
| `A/Int64.ofIntLE_sub` | 5 | proved | 5 | 2981513 | 246,708 | 12.1× |
| `B/Std.ExtDTreeMap.getKeyD_minKeyD/3` | 2 | proved | 2 | 2489298 | 1,284,012 | 1.9× |

| group | pilot runs | mean s per run (with overhead) | mean s of sizes per run | projected runs | projected h |
| --- | --- | --- | --- | --- | --- |
| rewrite_B | 10 | 47.1 | 17.0 | 100 | 1.78 |
| rewrite_A | 5 | 50.8 | 33.0 | 50 | 1.17 |
| control | 5 | 13.1 | 13.0 | 50 | 0.36 |

Pilot wall time: runs 13.2 min, sizes 6.7 min. Projection for the 200 runs: 3.3 h (the 20 pilot runs included).
