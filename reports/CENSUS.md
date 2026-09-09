# Type application census

Where a local TPTP library applies a type constructor, and in which dialects.
Every problem and axiom file is read with `Tptp.from_string/2` and nothing
else, under the same 20 MB size cap as `mix tptp.corpus`.

The TFF count is exact — a `<tff_atomic_type>` node is only ever built for an
application. The THF count is a heuristic, an apply spine in a `type`-role
statement, because THF does not separate a type from a term. "Outside the base
languages" means a dialect other than `cnf`, `fof`, `tf0` or `th0`.

Each `—` row refines the row above it. The TFF rows are taken over the exact
set and do not describe the heuristic's; the heuristic's files are instead divided
by dialect, which indicates whether it is identifying types.

A constructor applied at arity ≥ 2 over a type variable is the one shape an
elaborator cannot monomorphise into a fresh sort: `list($i)` is a sort,
`fun(A, B)` is a constructor that has to enter type unification. It is counted
for a variable as a direct argument and again for a variable anywhere beneath
one, since `fun(list(A), $i)` is no more monomorphisable than `fun(A, B)`.

Regenerate with `mix tptp.census`; `mix tptp.census --check` fails if the
results below have gone stale against the library on this machine.

<!-- results -->

## Results

| | Files |
|---|---:|
| Scanned | 29358 |
| With an applied type constructor (TFF, exact) | 885 |
| — of those, outside the base languages | 885 |
| — of those, at arity ≥ 2 over a type variable | 884 |
| — of those, at arity ≥ 2 over a nested type variable | 884 |
| With an apply spine in a THF type (heuristic) | 939 |
| — of those, TH1 | 939 |
| Using `!>` | 2092 |

## Constructors (TFF)

From the exact TFF walk alone. `record_thf/3` sets a boolean and never
populates `constructors`, so the files the THF heuristic found contribute no
names, no arities and no domains here — this is a census of the constructors
TFF spells unambiguously, not of the library's constructors. `Var` counts the
files where the constructor took a type variable as a direct argument at
arity ≥ 2, `Var nested` where one appeared anywhere beneath an argument.

| Constructor | Arities | Files | Var | Var nested | Domains |
|---|---|---:|---:|---:|---|
| `fun` | 2 | 617 | 617 | 617 | COM, ITP, LCL, NUM, NUN, SCT, SWV, SWW |
| `list` | 1 | 449 | 0 | 0 | COM, ITP, LCL, SCT, SWV, SWW |
| `product_prod` | 2 | 362 | 339 | 339 | COM, ITP, LCL, NUM, SCT, SWW |
| `option` | 1 | 208 | 0 | 0 | COM, ITP, SCT, SWW |
| `tyop_2Emin_2Efun` | 2 | 196 | 196 | 196 | ITP |
| `set` | 1 | 176 | 0 | 0 | ITP |
| `filter` | 1 | 170 | 0 | 0 | ITP |
| `itself` | 1 | 134 | 0 | 0 | ITP |
| `tyop_2Epair_2Eprod` | 2 | 131 | 130 | 130 | ITP |
| `array` | 1 | 102 | 0 | 0 | ITP, SWW |
| `sum_sum` | 2 | 96 | 96 | 96 | ITP, SWW |
| `ref` | 1 | 88 | 0 | 0 | ITP, SWW |
| `tyop_2Elist_2Elist` | 1 | 71 | 0 | 0 | ITP |
| `map` | 2 | 61 | 61 | 61 | SWW, SYN |
| `heap_ext` | 1 | 48 | 0 | 0 | ITP |
| `heap_Time_Heap` | 1 | 46 | 0 | 0 | ITP |
| `multiset` | 1 | 46 | 0 | 0 | ITP |
| `tyop_2Eoption_2Eoption` | 1 | 44 | 0 | 0 | ITP |
| `word` | 1 | 28 | 0 | 0 | ITP |
| `tyop_2Esum_2Esum` | 2 | 27 | 27 | 27 | ITP |
| `numeral_bit0` | 1 | 26 | 0 | 0 | ITP |
| `numeral_bit1` | 1 | 26 | 0 | 0 | ITP |
| `exp` | 1 | 25 | 0 | 0 | SWW |
| `huffma1450048681e_tree` | 1 | 25 | 0 | 0 | SWW |
| `hoare_28830079triple` | 1 | 24 | 0 | 0 | SWW |
| `fm` | 1 | 22 | 0 | 0 | COM |
| `tyop_2Efcp_2Ecart` | 2 | 19 | 19 | 19 | ITP |
| `tyop_2Eind__type_2Erecspace` | 1 | 19 | 0 | 0 | ITP |
| `old_node` | 2 | 18 | 18 | 18 | ITP |
| `tyop_2Ebool_2Eitself` | 1 | 18 | 0 | 0 | ITP |
| `pred` | 1 | 15 | 0 | 0 | ITP, SWW |
| `seq` | 1 | 14 | 0 | 0 | ITP |
| `tyop_2Etopology_2Etopology` | 1 | 9 | 0 | 0 | ITP |
| `tuple_isomorphism` | 3 | 8 | 8 | 8 | ITP |
| `fun1` | 2 | 7 | 7 | 7 | LCL |
| `tyop_2Efinite__map_2Efmap` | 2 | 7 | 7 | 7 | ITP |
| `tyop_2Equote_2Evarmap` | 1 | 6 | 0 | 0 | ITP |
| `poly` | 1 | 5 | 0 | 0 | SWW |
| `tyop_2Ebinary__ieee_2Efloat` | 2 | 5 | 5 | 5 | ITP |
| `tyop_2Ecanonical_2Ecanonical__sum` | 1 | 5 | 0 | 0 | ITP |
| `tyop_2Ecanonical_2Espolynom` | 1 | 5 | 0 | 0 | ITP |
| `tyop_2Efcp_2Ebit0` | 1 | 5 | 0 | 0 | ITP |
| `tyop_2Emetric_2Emetric` | 1 | 5 | 0 | 0 | ITP |
| `tyop_2Esemi__ring_2Esemi__ring` | 1 | 5 | 0 | 0 | ITP |
| `tyop_2Etoto_2Etoto` | 1 | 5 | 0 | 0 | ITP |
| `tyop_2Efcp_2Ebit1` | 1 | 4 | 0 | 0 | ITP |
| `tyop_2Ering_2Ering` | 1 | 4 | 0 | 0 | ITP |
| `tyop_2Ewellorder_2Ewellorder` | 1 | 4 | 0 | 0 | ITP |
| `lazy_lazy_sequence` | 1 | 3 | 0 | 0 | COM, SWW |
| `node` | 2 | 3 | 0 | 3 | SWW |
| `poly1` | 1 | 3 | 0 | 0 | SWW |
| `tyop_2EEncode_2Etree` | 1 | 3 | 0 | 0 | ITP |
| `tyop_2Ellist_2Ellist` | 1 | 3 | 0 | 0 | ITP |
| `tyop_2Eordinal_2Eordinal` | 1 | 3 | 0 | 0 | ITP |
| `tyop_2Ereal__topology_2Enet` | 1 | 3 | 0 | 0 | ITP |
| `tyop_2EringNorm_2Epolynom` | 1 | 3 | 0 | 0 | ITP |
| `fun_box` | 2 | 2 | 2 | 2 | ITP |
| `heap_Heap` | 1 | 2 | 0 | 0 | ITP |
| `tyop_2Ebinary__ieee_2Efp__op` | 2 | 2 | 2 | 2 | ITP |
| `tyop_2Eenumeral_2Ebl` | 1 | 2 | 0 | 0 | ITP |
| `tyop_2Eenumeral_2Ebt` | 1 | 2 | 0 | 0 | ITP |
| `tyop_2Epatricia_2Eptree` | 1 | 2 | 0 | 0 | ITP |
| `tyop_2Esptree_2Espt` | 1 | 2 | 0 | 0 | ITP |
| `cup_of` | 1 | 1 | 0 | 0 | SYN |
| `tyop_2Efcp_2Efinite__image` | 1 | 1 | 0 | 0 | ITP |
| `tyop_2Efmaptree_2Efmaptree` | 2 | 1 | 1 | 1 | ITP |
| `tyop_2Einftree_2Einftree` | 3 | 1 | 1 | 1 | ITP |
| `tyop_2Elbtree_2Elbtree` | 1 | 1 | 0 | 0 | ITP |
| `tyop_2Epath_2Epath` | 2 | 1 | 1 | 1 | ITP |
| `tyop_2Epatricia__casts_2Eword__ptree` | 2 | 1 | 1 | 1 | ITP |

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
| Workers | 4 on 28125, 2 on 913, 1 on 320 |
| Thinning | none — every file |
| Wall clock | 2756.3 s |
