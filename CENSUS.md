# Type application census

Where a local TPTP library applies a type constructor, and in which dialects.
Every problem and axiom file is read with `Tptp.from_string/2` and nothing
else, under the same 20 MB size cap as `mix tptp.corpus`.

The TFF count is exact — a `<tff_atomic_type>` node is only ever built for an
application. The THF count is a heuristic, an apply spine in a `type`-role
statement, because THF does not separate a type from a term. "Outside the base
languages" means a dialect other than `cnf`, `fof`, `tf0` or `th0`.

Regenerate with `mix tptp.census`; `mix tptp.census --check` fails if the
results below have gone stale against the library on this machine.

<!-- results -->

## Results

| | Files |
|---|---:|
| Scanned | 29358 |
| With an applied type constructor (TFF, exact) | 885 |
| With an apply spine in a THF type (heuristic) | 939 |
| — of the applied files, outside the base languages | 885 |
| Using `!>` | 2092 |

## Constructors

| Constructor | Arities | Files | Domains |
|---|---|---:|---|
| `fun` | 2 | 617 | COM, ITP, LCL, NUM, NUN, SCT, SWV, SWW |
| `list` | 1 | 449 | COM, ITP, LCL, SCT, SWV, SWW |
| `product_prod` | 2 | 362 | COM, ITP, LCL, NUM, SCT, SWW |
| `option` | 1 | 208 | COM, ITP, SCT, SWW |
| `tyop_2Emin_2Efun` | 2 | 196 | ITP |
| `set` | 1 | 176 | ITP |
| `filter` | 1 | 170 | ITP |
| `itself` | 1 | 134 | ITP |
| `tyop_2Epair_2Eprod` | 2 | 131 | ITP |
| `array` | 1 | 102 | ITP, SWW |
| `sum_sum` | 2 | 96 | ITP, SWW |
| `ref` | 1 | 88 | ITP, SWW |
| `tyop_2Elist_2Elist` | 1 | 71 | ITP |
| `map` | 2 | 61 | SWW, SYN |
| `heap_ext` | 1 | 48 | ITP |
| `heap_Time_Heap` | 1 | 46 | ITP |
| `multiset` | 1 | 46 | ITP |
| `tyop_2Eoption_2Eoption` | 1 | 44 | ITP |
| `word` | 1 | 28 | ITP |
| `tyop_2Esum_2Esum` | 2 | 27 | ITP |
| `numeral_bit0` | 1 | 26 | ITP |
| `numeral_bit1` | 1 | 26 | ITP |
| `exp` | 1 | 25 | SWW |
| `huffma1450048681e_tree` | 1 | 25 | SWW |
| `hoare_28830079triple` | 1 | 24 | SWW |
| `fm` | 1 | 22 | COM |
| `tyop_2Efcp_2Ecart` | 2 | 19 | ITP |
| `tyop_2Eind__type_2Erecspace` | 1 | 19 | ITP |
| `old_node` | 2 | 18 | ITP |
| `tyop_2Ebool_2Eitself` | 1 | 18 | ITP |
| `pred` | 1 | 15 | ITP, SWW |
| `seq` | 1 | 14 | ITP |
| `tyop_2Etopology_2Etopology` | 1 | 9 | ITP |
| `tuple_isomorphism` | 3 | 8 | ITP |
| `fun1` | 2 | 7 | LCL |
| `tyop_2Efinite__map_2Efmap` | 2 | 7 | ITP |
| `tyop_2Equote_2Evarmap` | 1 | 6 | ITP |
| `poly` | 1 | 5 | SWW |
| `tyop_2Ebinary__ieee_2Efloat` | 2 | 5 | ITP |
| `tyop_2Ecanonical_2Ecanonical__sum` | 1 | 5 | ITP |
| `tyop_2Ecanonical_2Espolynom` | 1 | 5 | ITP |
| `tyop_2Efcp_2Ebit0` | 1 | 5 | ITP |
| `tyop_2Emetric_2Emetric` | 1 | 5 | ITP |
| `tyop_2Esemi__ring_2Esemi__ring` | 1 | 5 | ITP |
| `tyop_2Etoto_2Etoto` | 1 | 5 | ITP |
| `tyop_2Efcp_2Ebit1` | 1 | 4 | ITP |
| `tyop_2Ering_2Ering` | 1 | 4 | ITP |
| `tyop_2Ewellorder_2Ewellorder` | 1 | 4 | ITP |
| `lazy_lazy_sequence` | 1 | 3 | COM, SWW |
| `node` | 2 | 3 | SWW |
| `poly1` | 1 | 3 | SWW |
| `tyop_2EEncode_2Etree` | 1 | 3 | ITP |
| `tyop_2Ellist_2Ellist` | 1 | 3 | ITP |
| `tyop_2Eordinal_2Eordinal` | 1 | 3 | ITP |
| `tyop_2Ereal__topology_2Enet` | 1 | 3 | ITP |
| `tyop_2EringNorm_2Epolynom` | 1 | 3 | ITP |
| `fun_box` | 2 | 2 | ITP |
| `heap_Heap` | 1 | 2 | ITP |
| `tyop_2Ebinary__ieee_2Efp__op` | 2 | 2 | ITP |
| `tyop_2Eenumeral_2Ebl` | 1 | 2 | ITP |
| `tyop_2Eenumeral_2Ebt` | 1 | 2 | ITP |
| `tyop_2Epatricia_2Eptree` | 1 | 2 | ITP |
| `tyop_2Esptree_2Espt` | 1 | 2 | ITP |
| `cup_of` | 1 | 1 | SYN |
| `tyop_2Efcp_2Efinite__image` | 1 | 1 | ITP |
| `tyop_2Efmaptree_2Efmaptree` | 2 | 1 | ITP |
| `tyop_2Einftree_2Einftree` | 3 | 1 | ITP |
| `tyop_2Elbtree_2Elbtree` | 1 | 1 | ITP |
| `tyop_2Epath_2Epath` | 2 | 1 | ITP |
| `tyop_2Epatricia__casts_2Eword__ptree` | 2 | 1 | ITP |

## Provenance

| | |
|---|---|
| BNF | 9.3.1.2 |

<!-- end results -->

## This run

| | |
|---|---|
| Library | `/opt/TPTP` |
| Elixir | 1.20.4 |
| OTP | 28 |
| Schedulers | 8 |
| Thinning | none — every file |
| Wall clock | 1490.5 s |
