# Defects in the TPTP sources

The TPTP is this library's ground truth. Where the parser and the library disagree,
the parser is wrong — it is generated from the published BNF, and correcting it by
hand would make it a parser for something else.

Sometimes the published sources disagree with *each other*: the grammar refuses a
file the TPTP itself ships, or one page contradicts another. Those are recorded here rather than
worked around, since a workaround would conceal the discrepancy. Each entry gives
the citation, the library's treatment of it, and a command reproducing the count.

Everything below was measured against **TPTP v9.3.1**, the BNF at
**v9.3.1.2** (`priv/bnf/SyntaxBNF-v9.3.1.2`) and the SZS ontology page as fetched on
**2026-08-31** (`priv/szs/SZSOntology-2026-08-31.html`). Line numbers are lines of the
vendored files.

Each entry was then checked against the TPTP's own published documentation at
<https://tptp.org/UserDocs/TPTPLanguage/TPTPLanguage.shtml>, so that "the BNF omits
this" is not mistaken for "the TPTP omits this". That check changed one entry
materially: the language page **does** define the `logic` role, which makes TPTP-1 a
contradiction between two TPTP sources rather than a gap, and means the library was
warning about 354 files that were right all along.

| | Defect | Severity | Affected |
|---|---|---|---:|
| [TPTP-1](#tptp-1) | The BNF's role list omits `logic`, which the language page defines | Contradiction | 354 files |
| [TPTP-2](#tptp-2) | `<source>` no longer derives `theory(...)` | **Files do not parse** | 4 files |
| [TPTP-3](#tptp-3) | `$modal_system_KB` is not among the modal systems | Files warn | 26 files |
| [TPTP-4](#tptp-4) | The SZS ontology page misspells one value | Cosmetic | 1 value |
| [TPTP-5](#tptp-5) | `''` is not a `<single_quoted>` where `""` is a `<distinct_object>` | Open question | — |

Three apparent defects that are not defects are recorded at the end, so that the
reasoning need not be reconstructed: [subtypes](#not-a-defect-subtypes),
[redundant leading zeros](#not-a-defect-leading-zeros) and
[arity overloading](#not-a-defect-arity-overloading). The last of those was in this
table as an unverified entry until the files were opened; it turned out to be a rule of
ours that was wrong about all eleven files it fired on.

---

## TPTP-1

**The `logic` role is defined by the TPTP language page and missing from the `:==`
role list quoted further down that same page.**

The prose lists fourteen roles:

> The `role` gives the user semantics of the `formula`, one of `axiom`, `hypothesis`,
> `definition`, `assumption`, `lemma`, `theorem`, `corollary`, `conjecture`,
> `negated_conjecture`, `plain`, `type`, `interpretation`, **`logic`**, and `unknown`.

and explains what it is for:

> `logic` formulae are used for defining the logic in non-classical logics.

The grammar on the same page, and in the vendored copy at lines 60–62, lists thirteen
and leaves `logic` out:

```
60: <formula_role>         :== axiom | hypothesis | definition | assumption | lemma | theorem |
61:                            corollary | conjecture | negated_conjecture | plain | type |
62:                            interpretation | unknown
```

So this is not the BNF lagging the library — it is one document disagreeing with
itself, and the corpus follows the prose: 354 problems carry the role, using it exactly
as described, to introduce a non-classical semantics specification.

```
PHI003^8.p:30   thf(simple_s5,logic,
SYO886_2.321.p  tff(spec,logic, $modal == [ ... ] ).
```

**Affected:** 354 problem and axiom files, across ten domains — SYO 170, SYP 108,
PHI 19, PUZ 13, GRA 12, LCL 12, PLA 10, DAT 4, SYN 4, MSC 2.

**What the library does:** accepts `logic` as a role, and reports nothing. This is the
one place a `:==` list is corrected rather than transcribed, and the correction is
narrow, cited and checked: `Tptp.Bnf.Generator`'s `@documented_values` carries the
entry with its source, and the build **fails** the moment the BNF starts listing the
value, so the correction cannot outlive the defect. `TPTP0401` fired on all 354 files
until this was found; it now fires on none of them.

The fix upstream is one word in the `:==` rule.

**Reproduce:**

```
grep -rlE '^\s*(thf|tff|tcf|fof|cnf|tpi)\([^,]+,\s*logic\s*,' $TPTP_ROOT/Problems $TPTP_ROOT/Axioms | wc -l
```

---

## TPTP-2

**`<source>` no longer derives `theory(...)`, and four TPTP demonstration files rely
on it. These are the only files in the library this parser cannot read.**

v9.3.1.2 replaced `<source> ::= <general_term>` with an explicit list of alternatives.
The superseded rule is still in the file, as a comment on the line above:

```
506: %----Expanded semantic rules for IDV. It was <source>               ::= <general_term>
507: <source>               ::= <dag_source> | <internal_source> | <external_source> | unknown |
508:                            [<sources>]
```

`theory(equality)` was a `<general_function>` and therefore a `<general_data>` and
therefore a `<general_term>`, so under the superseded rule it was a legal source. Under
the current rule it is not derivable at all: `<dag_source>` is a `<name>` or an
`<inference_record>`, `<internal_source>` must be `introduced(...)`, `<external_source>`
must be `file(...)`, and the remaining alternatives are the literal `unknown` and a
bracketed list.

The TPTP's own demonstration of the annotated-formula syntax uses it, once per dialect:

```
SYN000+2.p:86   inference(magic,[status(thm),assumptions([source_introduced_assumption])],
                          [theory(equality),source_unknown]) ).
SYN000+2.p:90   inference(magic,[status(thm)],
                          [theory(equality),source_unknown:[bind(X,$fot(a))]]) ).
```

Note that `theory` survives elsewhere in the same section, as an `<intro_type>`:

```
521: <intro_type>           :== definition | tautology | assumption | theory
```

so `introduced(theory, ...)` remains legal while `theory(...)` does not.

The TPTP language page states the same five alternatives and shows no example of
`theory(...)` in a source or parent position, so both published sources agree and it is
the four files that stand apart. Which end to fix is the maintainers' call: the files
are the TPTP's own syntax reference, which is an argument that the grammar dropped a
case, but nothing in the documentation says so and this register does not guess.

**Affected:** `SYN000-2.p`, `SYN000+2.p`, `SYN000_2.p`, `SYN000^2.p` — the same two
statements in each. Both fail with `TPTP0301`.

**What the library does:** nothing. The grammar is generated from the BNF and is not
patched to accept more than the BNF describes. The four files are listed in
`Mix.Tasks.Tptp.Corpus.known_failures/0`, explained once in `CORPUS.md`, and
`Tptp.CorpusTest` asserts that each of them *still* fails, so the exception cannot
outlive the defect.

**Reproduce:**

```
mix run -e '{:ok, _f, d} = Tptp.from_string(File.read!("#{System.get_env("TPTP_ROOT")}/Problems/SYN/SYN000+2.p")); IO.inspect(Enum.map(d, & &1.code))'
```

---

## TPTP-3

**`$modal_system_KB` is not among the modal systems `<ntf_modal_system>` names, and 26
library files specify it.**

```
345: <ntf_modal_system>     :== $modal_system_K | $modal_system_M | $modal_system_B | $modal_system_D |
346:                            $modal_system_S4 | $modal_system_S5
```

`KB` is the standard name for **K** plus the **B** axiom, and the list already contains
both `$modal_system_K` and `$modal_system_B` separately. The library uses the combined
name:

```
PHI005^10.p     $modalities == $modal_system_KB ]
```

Unlike TPTP-1, there is no second source against which to correct this.
`$modal_system_KB` appears nowhere on the TPTP language page, which names the same
six systems, so the two published sources agree with each other and disagree with
the corpus. The library therefore reports it rather than correcting it.

**Affected:** 26 problems — SYP 18, PHI 8.

**What the library does:** reports `TPTP0402` at warning severity. `$modal_system_KB` is
the only `$`-word flagged in any of the 26 files. See `Tptp.Lint.Rules.DefinedWord`.

**Reproduce:**

```
grep -rl 'modal_system_KB' $TPTP_ROOT/Problems $TPTP_ROOT/Axioms | wc -l
```

---

## TPTP-4

**The SZS ontology page spells `CounterTautologyyPreserving`, with a doubled `y`.**

```
196: <LI> <TT>CounterTautologyyPreserving</TT> (<TT>CTP</TT>):<BR>
```

One occurrence, on <https://tptp.org/UserDocs/SZSOntology>. Every neighbouring value —
`TautologyPreserving`, `CounterTautologous` — spells it with one.

**What the library does:** keeps the page's spelling as the *name* and does not
propagate it into the *atom*. `Tptp.Szs.Ontology.name(:counter_tautology_preserving)`
answers `"CounterTautologyyPreserving"` and `from_string/1` admits that spelling and no
other, because the name quotes the source; the atom is the library's own identifier and
is `:counter_tautology_preserving`. The override lives in
`Tptp.Szs.Generator`'s `@name_atom_overrides` and the generator **fails the build** if
the page ever stops needing it, so a correction upstream will be noticed rather than
silently ignored. Note that dropping the override is a breaking change to a public atom.

---

## TPTP-5

**`''` is not a `<single_quoted>`, but `""` is a `<distinct_object>`.**

```
638: <single_quoted>        ::- <single_quote><sq_char><sq_char>*<single_quote>
644: <distinct_object>      ::- <double_quote><do_char>*<double_quote>
```

One or more characters against zero or more. This is recorded as an open question
rather than as a defect, because it may well be intended: an atomic word with no
characters is arguably meaningless in a way that an empty distinct object is not. The
asymmetry is worth confirming either way, since a tool that emits `''` is producing
something no TPTP grammar has ever admitted.

**What the library does:** scans the token, reports `TPTP0107` at warning severity, and
lets the statement parse. That is the right behaviour under either reading, which is why
this needs no decision from us. See `Tptp.Lexer`.

---

---

## Not a defect: subtypes

`<atomic_type> ::= <typeable_atom>` reaches `<distinct_object>`, so
`tff(a, type, "x" << "y").` parses and declares a subtype relation between two
strings. The BNF says as much about itself:

```
453: <typeable_atom>        ::= <constant> | <distinct_object>
454: <atomic_type>          ::= <typeable_atom> | <defined_constant> | <system_type>
455: %----I wish I could use ...
456: <atomic_type>          :== <type_constant> | <defined_type> | <system_type>
457: %----... but that gives reduce conflicts because ...
460: %----Allowing <distinct_object> as an <atomic_type> is plain wrong.
```

This looks like a reportable `:==` gap and is not one, because of where
`<atomic_type>` can be reached from. There are exactly two places, and the BNF
labels both:

```
182: %----Subtypes are not approved by the whiny community
183: <thf_subtype>          ::= <atomic_type> <subtype_sign> <atomic_type>

277: %----Subtypes are not approved by the whiny community
278: <tff_subtype>          ::= <atomic_type> <subtype_sign> <atomic_type>
```

Subtypes were proposed and never adopted. Nothing else in the grammar reaches
`<atomic_type>` — every dialect writes types through its own nonterminal, and
`<tff_top_level_type>` reaches `<tff_atomic_type>`, which admits a `<type_constant>`,
a `<defined_type>`, a `<variable>` or an application and never a
`<distinct_object>`. So `tff(a, type, f: "s" > $o).` does not parse at all, and the
widening the comment complains about is confined to a construct that is not part of
the language.

The corpus agrees: `<<` does not appear outside a comment in any of the 29,358
problem and axiom files.

**What the library does:** nothing. An earlier revision of this register listed it
as `TPTP-5` and shipped a lint rule for it; both were incorrect. `Tptp.Lint` does
not carry a rule that cannot apply to real input, and a warning concerning the
operands of an unimplemented construct is a finding about a proposal rather than
about a file. `TPTP0403` is unassigned.

**Reproduce:**

```
grep -rlE '^[^%]*<<' $TPTP_ROOT/Problems $TPTP_ROOT/Axioms | wc -l
```

---

## Not a defect: leading zeros

`TPTP0110` and `TPTP0111` fire on `00`, `-007`, `1/02` and `1/0`. The grammar is
explicit that these are not numbers — `<unsigned_integer>` is `0` or a digit sequence
starting `1`-`9`, and a rational's denominator is a `<positive_integer>`, which may
not begin with `0` at all. A file containing one is malformed; the sources do not
disagree with each other about anything. The library scans the token anyway and warns,
so the statement can still parse.

---

## Not a defect: arity overloading

An earlier version of this file carried the eleven files `TPTP0505` fired on —
`SWX075_1.p`, `SWX076_1.p`, `SWX091_1.p`–`SWX098_1.p` and `SYN000_4.p` — as an
unverified entry, on an inherited note saying they really did declare one symbol at two
arities and that the rule was right about all of them.

The files were opened on 2026-09-09. The rule was wrong about every one of them, in two
different ways, and it has been withdrawn.

**Ten of them do exactly what the TPTP permits.** `SWX091_1.p` declares `sqrt` twice
and uses both:

```
39: tff(predicate_1,type,
40:     sqrt: general > $o ).
47: tff(predicate_4,type,
48:     sqrt: ( general * general ) > $o ).

119:      ( sqrt(V1_g)
236:      ( sqrt(f__integer__(I_i),f__integer__(N_i))
```

The TPTP language page settles it, in the section on logical formulae that governs
every dialect:

> Symbols may be overloaded with different arity signatures, and are treated as
> different symbols.

So `sqrt/1` and `sqrt/2` are two symbols, each declared once, each used consistently.
`SWX075_1.p` and `SWX076_1.p` do the same thing with `color`. Nothing is wrong with any
of them.

**The eleventh was this library's own bug.** `SYN000_4.p` is the TPTP's TXF syntax
demonstration, and the finding was `"ff" is applied at 0 and 2 arguments`:

```
164:      ff: ( $int * $int ) > $rat,
165:      ff(X,Y):= fl2(X,X,Y,Y),
166:      pl2(ff(il2,jl2)) ) ).
```

That is a `$let`. The bare `ff` in its type section was being recorded as an application
at arity 0. A `type`-role statement's subject is recognised and never counted, but a let
binding is nested and was not — the same blind spot that produced the 39 false
undeclared-symbol findings corrected previously, in a second location that had not
been examined.
`Tptp.Lint.Collect` now claims the binding's position, and the file is clean.

**What the library does:** nothing. `TPTP0505` is unassigned, the rule is deleted, and
the exclusion list went with it. Swept over all 29,358 files, it had fired on those
eleven and nothing else — so it never once reported something true.

**There is a real rule here that the library does not yet implement.** The same page
states:

> If a symbol's type is declared more than once, and the types are not the same, that's
> an error.

Since a symbol is name *and* arity, that is a question about two declarations at the
same arity, and `Tptp.Lint.Table` keys on the name alone. Implementing it means giving
the table the identity the TPTP uses. That is worth doing and is not done.

---

## Reporting these

The TPTP is maintained by Geoff Sutcliffe; see <https://tptp.org> for current contact
details. TPTP-2 is the one worth leading with: it makes four of the TPTP's own
demonstration files unparseable by the TPTP's own published grammar, and the fix is one
alternative.

When a release resolves any of these, the check that will notice is `mix tptp.gen`,
which regenerates every derived file from the vendored sources and cross-checks the two
against each other. For TPTP-4 specifically the generator raises rather than writes. For
TPTP-2, `Tptp.CorpusTest` fails when the four files start parsing, which is the signal to
delete the entry from `known_failures/0` and from this file.
