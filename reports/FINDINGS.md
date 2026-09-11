# Findings: what the parse failures were hiding

Four files in TPTP v9.3.1 failed to parse, so every stage after the parser had never
seen the statements that failed, and every corpus sweep skipped the four files
outright through `Mix.Tasks.Tptp.Corpus.known_failures/0`. On 2026-09-10 the fix
announced in
[BuggedProblems-v9.3.1.txt](https://tptp.org/TPTP/Distribution/BuggedProblems-v9.3.1.txt)
was applied to copies of the four, and everything downstream was run over them, and
then over the library, looking for what else a skipped file or an unchecked stage
could conceal.

Measured against TPTP v9.3.1 at `/opt/TPTP`, BNF v9.3.1.3
(`priv/bnf/SyntaxBNF-v9.3.1.3`) and the TPTP language page at
<https://tptp.org/UserDocs/TPTPLanguage/TPTPLanguage.shtml>. Line numbers are lines of
those files.

| | Finding | Whose | Status |
|---|---|---|---|
| [1](#1-syn000_2p-writes-introduced2) | `SYN000_2.p` writes `introduced/2` | TPTP | Reported 2026-09-11 |
| [2](#2-syn0002p-uses-an-undeclared-symbol) | `SYN000^2.p` uses the undeclared `qll` | TPTP | Reported 2026-09-11 |
| [3](#3-the-literal-unknown-source-is-also-a-name) | `unknown` is both a `<source>` literal and a `<name>` | TPTP, cosmetic | Reported 2026-09-11 |
| [4](#4-tptp0501-reported-legal-default-typed-symbols) | `TPTP0501` reported legal default-typed symbols | This library | Fixed in 0.1.0 |
| [5](#5-tptp0504-reported-the-literal-unknown-as-a-parent) | `TPTP0504` reported the literal `unknown` as a parent | This library | Fixed in 0.1.0 |
| [6](#6-tptpquery-read-most-txf-files-as-tf0) | `Tptp.Query` read most TXF files as TF0 | This library | Fixed in 0.1.0 |
| [7](#7-the-pages-txf-paragraph-omits-distinct) | The language page's TXF paragraph omits `$distinct` | TPTP, cosmetic | Reported 2026-09-11 |
| [8](#8-a-miscounted-number-of-x-terms-header) | `SYO561_1.p`'s `Number of X terms` header miscounts | TPTP | Reported 2026-09-11 |

The five TPTP-side findings were reported upstream on 2026-09-11.

The checks that found nothing are [at the end](#checked-and-clean), so they need not be
repeated.

## The patch

Two edits, to copies. The first is the announced one; the second is finding 1.

```
sed -e 's/\[theory(equality),source_unknown/[source_unknown/g' \
    -e 's/introduced(assumption,\[from,the,world,\[\]\])/introduced(assumption,[from,the,world],[])/' \
    $TPTP_ROOT/Problems/SYN/SYN000_2.p > SYN000_2.p        # and likewise for -2, +2, ^2
```

With both, all four files parse with no diagnostic, print identically through the
canonical, pretty and format-preserving printers after a re-parse, and lint clean at
the file and the unit level, apart from `TPTP0506` (no conjecture, at `:info`) and
finding 2.

## 1. `SYN000_2.p` writes `introduced/2`

```
104:    introduced(assumption,[from,the,world,[]]) ).
```

The closing bracket of the `<useful_info>` list sits one place to the right, so the
term has two arguments. Both published sources require three:

```
539: <internal_source>      ::= introduced(<intro_type>,<useful_info>,<parents>)
```

and the other three dialects' copies of the file write it that way:

```
SYN000-2.p:71   introduced(assumption,[from,the,world],[]) ).
SYN000+2.p:82   introduced(assumption,[from,the,world],[]) ).
SYN000^2.p:294  introduced(assumption,[from,the,world],[]) ).
```

The `theory(equality)` fix leaves this in place, so `SYN000_2.p` is the one of the
four that still fails once the corrected tarball is published. It stays in
`known_failures/0`, where `@introduced` gives this reason.

**Reproduce:**

```
grep -n 'introduced(' $TPTP_ROOT/Problems/SYN/SYN000?2.p
```

## 2. `SYN000^2.p` uses an undeclared symbol

```
216: thf(let_tuple_4,axiom,
217:     $let(
218:       [ a: $int,
219:         b: $int ],
220:       [a,b]:=
221:         [27,28],
222:       qll @ a @ b ) ).
```

Nothing declares `qll`. THF has no default typing — "THF does not admit default
typing - all symbol types must be declared before use", in the language page's
section on types — so this is an error rather than a style point. The file declares
`ql` with exactly the type the use needs:

```
132:    ql: $int > $int > $o ).
```

so it is presumably a typo for `ql`. `TPTP0501` reports it.

The statement parses, but the file did not, so no sweep ever linted it. Swept as
units with includes resolved, it is the only undeclared symbol in any of the 5,275
THF problems checked: the 4,918 THF-named ones under 1 MB, and 357 of the 361 between
1 and 20 MB whose `SPC` names TH0 or TH1, the remaining four having exceeded the
sweep's heap share. No THF problem exceeds 20 MB. It is listed in the lint corpus test's
`@known_undeclared`, so that gate does not fail when the file leaves
`known_failures/0`.

**Reproduce:**

```
grep -nE '\bqll?\b' "$TPTP_ROOT/Problems/SYN/SYN000^2.p"
```

## 3. The literal `unknown` source is also a name

```
527: <source>               ::= <dag_source> | <internal_source> | <external_source> | unknown |
```

`unknown` is also a `<lower_word>`, hence a `<name>`, hence a `<dag_source>`, so the
literal alternative is ambiguous with the first one: an LALR generator reports a
reduce/reduce conflict. The meaning is not in doubt — the language page describes
`unknown` as the unknown source — but a tool cannot distinguish that from a parent
formula named `unknown`. `Tptp.Bnf.Generator` resolves it by dropping the literal
alternative (the first of its departures), and finding 5 is what that cost.

Cosmetic. The four `SYN000*2.p` files are the only library files that use the
literal; see [finding 5](#5-tptp0504-reported-the-literal-unknown-as-a-parent).

## 4. `TPTP0501` reported legal default-typed symbols

The rule reported every undeclared symbol in every typed dialect. The language page:

> A useful feature of TFF is default typing for symbols that are not explicitly
> declared: predicates default to `($i,...,$i) > $o`, and functions default to
> `($i,...,$i) > $i`. This allows TFF to effectively degenerate to untyped FOF.
> […]
> THF does not admit default typing - all symbol types must be declared before use.

and, in its section on the TF0 type system, "If a symbol is used and its type has not
been declared, then default types are assumed."

So in TFF, TXF, TCF and NXF an undeclared symbol has a type. The rule fired on 517
occurrences across seventeen such files, and the lint corpus test carried all of
them as true findings:

| Files | Dialect | Occurrences |
|---|---|---:|
| `SWX216+1.p`, `SWX228_1.p`–`SWX239_1.p` (13) | TF0 | 494 |
| `SYN000-3.p` | TCF | 18 |
| `MSC034_1.p`, `MSC035_1.p` | NXF | 4 |
| `LCL977_1.p` | TF0 | 1 |

None of them is ill-typed under the defaults. These files declare almost nothing, so
the only values other than `$i` are `$o`, and the one place a default could clash is
an axiom binding a `$o` variable; every such axiom in the fourteen first-order `SWX`
and `LCL` files was read. Where an undeclared symbol is applied to a cons that carries
a `$o`, it is used as a predicate — `head6(cons6((X),X2)) <=> (X)` in `SWX229_1.p`,
so `head6` defaults to `($i) > $o` — and where one is compared with `=`, it is the
`$i` tail: `tail6(cons6((X),X2)) = X2`. `LCL977_1.p` applies `f` only to untyped
variables, and the `MSC` atoms are propositions, which default to `$o`.

The rule now applies only where a `thf` statement is present — TH0, TH1, DH0, DH1
and NHF — and `README.md` no longer says the typed dialects require a declaration for
every symbol. Default typing does make two things an error — a later declaration that
differs from the assumed type, and a default-typed symbol applied to an argument
other than `$i` — but both are questions about types, which this library does not
answer.

Found because finding 2's neighbour, `SYN000_2.p`, drew `TPTP0501` for `ia1` and
`ia3`: its selective `include('Axioms/SYN000_0.ax',[ia1,ia3])` omits the two formulae
that declare them. In TFF that is legal, and reading the page to confirm it is what
showed the rule's premise to be wrong.

## 5. `TPTP0504` reported the literal `unknown` as a parent

Because of finding 3's departure, the literal `unknown` in source position reaches the
lint table as a parent named `unknown`, and `Tptp.Lint.Rules.Parent` reported it as
missing: twice in each `SYN000*2.p` file, once for the source of `source_unknown`
and once for that of `useful_info` (`SYN000+2.p:66` and `:95`). The
rule now never reports `unknown`.

**Reproduce** (the files that use the literal):

```
grep -rlE '^\s*unknown\s*(\)\s*\.|,)|,\s*unknown\s*(\)\s*\.|,\s*\[)' $TPTP_ROOT/Problems $TPTP_ROOT/Axioms
```

## 6. `Tptp.Query` read most TXF files as TF0

TXF was recognised by three constructs that have a node kind of their own — a tuple,
a `$let` and a sequent — and by nothing else. But most of what TXF adds to TFF is
FOOL, and no FOOL form has a node kind, because each is an ordinary TFF node standing
where the grammar also admits it in TF0. The language page:

> The typed extended first-order form (TXF) augments TFF with FOOL constructs:
> formulae of type `$o` as terms; variables of type `$o` as formulae; tuples;
> conditional (if-then-else) expressions; and let (let-defn-in) expressions.

Measured against TPTP's own `SPC` headers over the 2,977 problems under 1 MB whose
header names a TF or TX dialect, 252 are TX0 and 51 of them read as `:tx0`. The other
201 read as `:tf0`.

Five shapes now carry the feature. A `$o` variable and a formula in a term position
are the first two of the page's list; `$ite` is its fourth, which the BNF writes as a
defined functor rather than as a form of its own (`<txf_conditional> :== $ite(...)`).
A declared `$o` argument type is the other half of the page's rule, "The argument
types must be atomic, and cannot be `$o` in TFF, but can be `$o` in TXF". And
`$distinct` is TXF's and THF's, per the BNF:

```
501: %----$distinct is part of the TXF and THF languages. $distinct is always written in functional
502: %----form, even in THF. It takes one or more terms of the same type as arguments, and indicates
503: %----that the arguments are pairwise !=.
```

A formula in a term position needs the whole `<tff_term> ::= <tff_logic_formula>`
family, including `tff_unitary_term` — an equation's parenthesised side is a term
node and not a formula node, so `f(a) = (p | q)` was read as TF0 until it was added —
and `$true` and `$false`, which are terms of type `$o` and reach the same position as
`defined_constant` leaves.

With all five, every one of the 252 is read correctly, and nothing else moves: no
false positive among the 2,060 TF0, 590 TF1 and 60 TX1 problems in the same sweep.

Repeating the sweep over the 821 problems between 1 and 20 MB whose `SPC` names a TF,
TX or TH dialect carries that across the rest of the library: all 88 TX0 and all 88
TX1 there are read correctly, as are 191 TF0, 89 TF1, 180 TH1 and 177 TH0, with no
mismatch of any kind. Every one of the library's 340 TX0 problems is therefore read
correctly, against 2,251 TF0, 679 TF1 and 148 TX1 that are not. Nothing above 20 MB is
TXF or THF — those 62 files are 30 TF0, 19 CNF and 13 FOF — so this covers the TX
population exactly rather than merely widely. Twenty-three units exceed their sweep's
heap share and were not classified, nineteen TF0 and four TH0.

`SYO561_1.p` was the last of the 252 to be read correctly. It uses no FOOL at all —
`$distinct(apple,microsoft)` is its only construct above TF0, and it is the library's
one live use of `$distinct` — which is what led to finding 7.

**Reproduce:** `Tptp.QueryTest` pins each shape. For one file:

```
mix run -e 'root = System.fetch_env!("TPTP_ROOT")
{:ok, unit, _} = Tptp.Unit.from_file(root <> "/Problems/SYO/SYO561_1.p", resolver: {Tptp.Resolver.Fs, root: root})
IO.inspect(Tptp.Query.dialect(unit))'
```

## 7. The page's TXF paragraph omits `$distinct`

Finding 6's quotation lists five constructs, and `$distinct` is not among them, nor
is it mentioned anywhere else on the page as belonging to a particular dialect. Two
other sources say it does belong to one. The BNF, at line 501, says it "is part of
the TXF and THF languages". And TPTP's own tooling agrees twice over: it counts
`$distinct` among a problem's extended terms —

```
21: %            Number of X terms     :    1 (   0  [];   0 ite;   1 let;   1 dis)
```

— and gives `SYO561_1.p`, whose only construct above TF0 is that one `$distinct`, an
`SPC` of `TX0`. The v9.3.1 bugfix to the 32 `MGT` problems, "$distinct expanded to
inequalities", reads as the same judgement applied to FOF.

So the meaning is settled and only the page is silent. A clause in the TXF paragraph
would close it. That same header line is [finding 8](#8-a-miscounted-number-of-x-terms-header).

## 8. A miscounted `Number of X terms` header

```
21: %            Number of X terms     :    1 (   0  [];   0 ite;   1 let;   1 dis)
```

`SYO561_1.p` contains no `$let`. Its five statements are three type declarations, the
`$distinct` axiom and an `apple != microsoft` conjecture. The parts also sum to two
where the line states one, which is the same miscount seen from the other side.

Of the 448 `Number of X terms` headers in `Problems/` and `Axioms/`, this is the only
one whose parts do not sum to its total, and the only one whose `dis` is not zero.
Since this file is the library's one live `$distinct`, the `dis` column has had no
other occasion to be exercised — so the fault is likely in whatever counts a
`$distinct`, rather than in this file.

**Reproduce:**

```
grep -rH 'Number of X terms' $TPTP_ROOT/Problems $TPTP_ROOT/Axioms |
  perl -ne 'if (m{^(.*?):%\s+Number of X terms\s*:\s*(\d+)\s*\(\s*(\d+)\s*\[\];\s*(\d+) ite;\s*(\d+) let;\s*(\d+) dis\)}) {
    $s = $3 + $4 + $5 + $6;
    print "$1 total=$2 parts=$s\n" if $2 != $s;
  }'
```

## Checked and clean

- **The other thirteen SYN000 demonstration files** — `SYN000+1`, `-1`, `-3`, `^1`,
  `^3`, `^6`, `^7`, `_1`, `_3`–`_7`. All parse, round-trip through all three
  printers, and lint clean at file and unit level apart from `TPTP0506` at `:info`
  (and `SYN000-3.p` under the old `TPTP0501`, finding 4).
- **Every `include` directive**, 216,891 across `Problems/` and `Axioms/`. Every
  target exists. Four use a selection — the four `SYN000*2.p` files — and every name
  they select exists in its target. The corpus gates build units and discard the
  unit diagnostics, so this is the first check of it.
- **Every THF problem in the library**, 5,275 of the 5,279, linted as a unit with
  includes resolved and `TPTP0501` alone: 5,274 clean and finding 2. That is the
  4,918 THF-named problems under 1 MB — thirteen ITP units among them exceed a 1.5 GB
  heap and were rerun one at a time under 6 GB, all clean — together with the 361
  between 1 and 20 MB whose `SPC` names TH0 or TH1, four of which exceeded the heap
  share and went unchecked. No THF problem exceeds 20 MB.
- **The new `<distinct_object>` rule.** v9.3.1.3 requires at least one `<do_char>`.
  No library file contains an empty `""`: the four lines a search for `""` finds
  outside comments are `"A \"Microsoft \\ escape\""` in the `SYN000*2.p` files, an
  escaped quote followed by the closing one.
- **`TPTP0503`**, duplicate formula names, which fires on the ITP axiom sets. Not a
  defect: the BNF requires unique names "in derivations, … so that parent references
  are unambiguous", and a problem is not a derivation.

The first and fourth are repeatable with `mix test --include corpus`, which runs the
gates, and with `TPTP_CORPUS_FULL=1`, which runs them over every file rather than a
sample.
