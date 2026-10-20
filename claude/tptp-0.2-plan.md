# tptp 0.2.0 — implementation plan

Status (2026-10-13): plan, against tptp 0.1.3 (`10d3f67`, `mix.exs` `@version
"0.1.3"`). Derived from the AtpClient requirements document "tptp 0.2 —
requirements from AtpClient 0.8" (R1–R6), after checking each requirement against
the source. Section 1 lists where that document is wrong or silent and what was
decided; sections 3–8 are the specification to implement; section 9 is the order
of work and the gates. The AtpClient side is
`claude/structured-results-and-discovery-plan.md` in that repository and must be
told of the deviations in 1.2.

Scope rule, unchanged: tptp reads and writes the formats of the TPTP World and
attaches no semantics. Everything here is structure — a graph over `source`
annotations, a file header, a comment prefix. Nothing evaluates a formula or
decides what a prover meant; what a *system* prints stays in AtpClient.

## 1 Decisions and corrections

### 1.1 Corrections to the requirements, verified against the code

| # | Requirement said | Code says | Resolution |
|---|---|---|---|
| C1 | R3: `status(X)` resolves through `Tptp.Szs.Ontology.from_mnemonic/1`; an ambiguous mnemonic leaves `status: nil`. | `from_mnemonic/1` is the upper-case page table; `from_mnemonic("thm")` is `:error` (doctest, `lib/tptp/szs/page.ex:69`). The lower-case `status(thm)` words are `Ontology.from_status_value/1` (`page.ex:189–`), which returns `{:ok, t} \| :error` only. | Resolve through `from_status_value/1`. There is no ambiguous case; an unknown word leaves `status: nil` and emits no diagnostic (the word is still in `info`). |
| C2 | R5: three places read `role.text`. | Five: `Lint.Rules.Role.visit/3` (`lint/rules/role.ex:43`), `Lint.Context.role/1` (`lint/context.ex:58`), `Lint.Collect.typing?/1` (`lint/collect.ex:389`), `Tptp.Query.roles/1` (`query.ex:294`, produces a `nil` key for a sub-role) and the `Inspect` implementation in `Tptp.Statement.Annotated` (`statement/annotated.ex:55`, passes `nil` to `Inspect.Algebra.concat/1`, which raises `FunctionClauseError` — `inspect/1` of a Mace4 interpretation statement crashes today). | Route all five through `Annotated.role_word/1` (section 7). |
| C3 | R3 `origin` has four alternatives. | `<dag_source> ::= <name> \| <inference_record>`, so a statement's whole source may be a bare `<name>`; the literal `unknown` parses as a `<name>` too (`Tptp.Bnf.Generator` departure 1, `lint/rules/parent.ex` moduledoc). A statement may also have no annotations at all. | Add `{:name, binary}` (a bare name, the literal `unknown` included — it is a `<name>` to the grammar) and `:none` (no `source`). `{:unknown, node}` remains for anything else. |
| C4 | R3 `Step.parents :: [binary \| :previous]`, `:previous` = the step before in the same list. | `inference(sr, [], [inference(a, …), inference(b, …)])` flattens to `[a…, b…, sr]` and `sr` has two inner-record parents; `:previous` names only one. | `{:step, index}`: the zero-based position in the same step list. The `:previous` of the requirement is `{:step, length(steps_so_far) - 1}`. |
| C5 | R3: `leaves` = "no inference step". | A node whose source is a bare `<name>` has a parent and no step, and `introduced(_, _, [p])` likewise. | `leaves` = nodes with `parents == []`; `roots` = nodes that are a parent of no node. Both are graph facts, independent of how the edge was written. |
| C6 | Fixtures "captured on 2026-10-13, to be committed". | Not in the repository (`test/fixtures/` holds `census/`, `regression/`, `szs/` only) and the author does not have them. | Section 8: obtain them from tptp.org during implementation; fall back to synthetic fixtures, marked as such, and list the replacement as a release blocker. |

### 1.2 Decisions (taken; AtpClient to be told of C1, C3, C4, C5, D1, D3)

- **D1** Diagnostic codes for `Tptp.Derivation` reuse the lint rules: a parent naming no statement is `Tptp.Lint.Rules.Parent.code()` (`TPTP0504`), a duplicate name is `Tptp.Lint.Rules.DuplicateName.code()` (`TPTP0503`). A cycle has no lint counterpart and gets **`TPTP0507`**, the next free number in the cross-statement tier (`TPTP0505` withdrawn, `TPTP0506` is `Conjecture`). `Tptp.Diagnostic`'s tier table gains the line "`TPTP05xx` — also raised by `Tptp.Derivation`". Call the rule modules' `code/0` rather than repeating the strings.
- **D2** `cone/2` returns a `%Tptp.File{}` with `id`, `path`, `source`, `bnf_version` copied from the input (sub-binaries point into `source`, so it is kept whole), `statements` = the retained statements in their original order, `comments` = the input's comments whose `{offset, length}` lies within a retained statement's `[off, off + len)`, `diagnostics` = `[]`.
- **D3** R2 `prefix:` accepts a `Regex.t()` or a list of them, applied in the given order to every body line; the block records the normalised list: `prefix: [Regex.t()]`, `[]` when nothing was stripped.
- **D4** `Tptp.Tstp.from_string/2` returns `{:error, :not_tstp}` for input that is not a TSTP solution file. No diagnostic code; the caller's fallback is `Tptp.Szs`.
- **D5** `Tptp.Derivation.order` holds each name once, at the position of the statement that won (the last one); `nodes` is keyed by `Tptp.Node.value/1` of the `<name>`, so `'c_0_7'` and `c_0_7` are one node.
- **D6** Fixtures for R3 whose source is SystemOnTPTP are stored as the raw reply body under `test/fixtures/tstp/`; a fixture that is a TSTP solution file goes under the same directory with its TSTP name.

## 2 Current state (what the implementation builds on)

- `Tptp.Szs` (`lib/tptp/szs.ex`): `@status`, `@start`, `@stop` at lines 91–93, all `^[^\r\n]*?[%#][ \t]*SZS …`, flags `im`. `blocks/1` slices `body` between markers and `String.trim/1`s it (`body/3`, line 274). `@type block :: %{dataform, problem, body}` at line 87.
- `Tptp.Szs.Ontology`: `from_string/1` (CamelCase names), `from_mnemonic/1` (page mnemonics, may be `{:ambiguous, _}`), `from_status_value/1` (lower-case `status(…)` words), `name/1`, `mnemonic/1`.
- Grammar (`src/tptp_parser.yrl`, generated; do not edit by hand, `mix tptp.gen` regenerates it and the grammar does not change in this release):
  - `formula_role -> lower_word` (line 90) and `formula_role -> lower_word minus general_term` (line 91). `formula_role` is in `Tptp.Bnf.Generator.significant/0`, so the one-child form collapses to a leaf `%Node{kind: :formula_role, text: "axiom"}` and the two-child form is `%Node{kind: :formula_role, text: nil, children: [%Node{kind: :lower_word, text: w}, general_term]}`. `Tptp.Printer.Shapes.shape(:formula_role, 2)` is `[:slot, "-", :slot]`. `test/tptp/parser_test.exs:102` already parses `assumption-[1]`.
  - `source -> dag_source | internal_source | external_source | '[' sources ']'` (lines 435–438). Only the bracketed form builds a node, `kind: :source`, one child: either a single source or a right-nested `:sources` node with two children.
  - `dag_source -> name | inference_record`; `inference_record` children `[inference_rule, useful_info, parents]` (line 443); `inference_rule` and `intro_type` are significant, so they arrive as leaves of that kind with `text`.
  - `internal_source` (`introduced(...)`) children `[intro_type, useful_info, parents]` (line 445).
  - `file_source` children `[file_name, file_info]` or `[file_name]` (`file_info` is `nil` when absent and `Tptp.Parser.build/2` drops `nil` children); `file_info` has one child, a `:name`.
  - `parents` children `[]` or `[parent_list]`; `parent_list` children are `parent_info` nodes; `parent_info` children `[source]` or `[source, parent_details]`; `parent_details` has one child, a `general_term`.
  - `useful_info -> general_list`, a chain rule, so `info` and the second child of an inference record are `:general_list` nodes: children `[]` or `[general_terms]`, whose children are the items. `status(thm)` is a `:general_function` with children `[%Node{kind: :lower_word, text: "status"}, %Node{kind: :general_terms, children: [%Node{text: "thm"}]}]`.
  - `name` is significant: a leaf `%Node{kind: :name, text: …}`; `Tptp.Node.value/1` strips single quotes.
- `Tptp.Statement.Annotated` fields: `language, name, role, formula, source, info, off, len`; `source`/`info` are `Tptp.Node.t() | nil`.
- `Tptp.File` fields: `id, path, source, bnf_version, statements, comments, diagnostics`; `comments :: [{offset, length, :line | :block, :plain | :defined | :system}]`.
- `Tptp.Diagnostic.new(code, severity, %Span{}, message, hint: …, related: [%Span{}])`; `Tptp.Span.new(file_id, off, len)`.
- `Tptp.Lint.Collect.note_parent/3` (`collect.ex:374`) already collects every `:name` node under the `:source` slot as a parent — the model for the names `Tptp.Derivation` must find.
- Project gates: `mix check` = `format --check-formatted`, `compile --warnings-as-errors`, `credo --strict` (including `checks/no_dynamic_atoms.ex`: no `String.to_atom`, `List.to_atom`, `:erlang.binary_to_atom`, `:erlang.list_to_atom`, `:erlang.binary_to_term`), `test`, `dialyzer`. `test/tptp/documentation_test.exs` fails on any public function without `@doc`, any type without `@typedoc`, any module without `@moduledoc`. Elixir `~> 1.20`, OTP 28; the committed PLTs under `priv/plts/` are for `erlang-28.5.0.6_elixir-1.20.4`.
- Style: moduledocs explain the design and cite the BNF; definitions are stated without motivating prose; doctests on every reader function; `Regex` literals as module attributes with `[ \t]` for horizontal white space (never `\s` or `\h`, see the comment at `szs.ex:89`).

## 3 R1 — SZS lines without a comment character

Paradox 4.0 prints `SZS status Satisfiable for /tmp/…/SOT_KBdUKq.tptp:short` and `SZS output start FiniteModel for …` bare, at the start of the line. `Tptp.Szs.status/1` returns `:none` and `blocks/1` `[]`.

Change (`lib/tptp/szs.ex`), all three patterns:

```elixir
# before
~r{^[^\r\n]*?[%#][ \t]*SZS[ \t]+status …}im
# after
~r{^(?:[^\r\n]*?[%#][ \t]*|[ \t]*)SZS[ \t]+status …}im
```

- The second alternative admits only horizontal white space before `SZS`, so prose with "SZS status" mid-sentence does not match (the end anchor is unchanged).
- The `for` value is `(\S+)`, greedy, so `…/SOT_KBdUKq.tptp:short` is the problem, `:short` included, and the `: <free text>` group stays empty. Add this as a doctest on `status/1` so the behaviour is pinned.
- Moduledoc "What the reader accepts": add a fourth bullet, "No comment character at all, as Paradox prints it", with a doctest.
- Writers unchanged.

Tests (`test/tptp/szs_test.exs`, in "reading prover output as AtpClient receives it"): the fixture `test/fixtures/szs/paradox_finite_model.txt` (section 8); `status/1` is `{:ok, :satisfiable, "/tmp/…tptp:short", nil}`; `blocks/1` yields one `:finite_model` block whose body starts with `% domain size is 2`; a negative case — `"The line SZS status Theorem is not a status line\n"` is `:none`; `"   SZS status Theorem\n"` is `{:ok, :theorem, nil, nil}`.

## 4 R2 — per-line prefixes in output blocks

Two prefixes occur, neither uniform across a block: StarExec's elapsed times `0.20/0.43\t` (the numbers change between lines) and the `% ` of a TSTP solution file's ORIGINAL SYSTEM OUTPUT section. Both may stack: `% 0.12/0.45  % SZS status Theorem`.

API (`lib/tptp/szs.ex`):

```elixir
@typedoc "…the lines between the markers; `prefix` is the list of patterns removed from every body line, `[]` when none."
@type block :: %{dataform: Ontology.t(), problem: binary() | nil, body: binary(), prefix: [Regex.t()]}

@type prefix :: :starexec | :line_comment

@spec blocks(binary(), [{:prefix, Regex.t() | [Regex.t()]}]) :: [block()]
def blocks(output, options \\ [])

@doc "A named per-line prefix, for `blocks/2`'s `:prefix`."
@spec prefix(prefix()) :: Regex.t()
def prefix(:starexec), do: ~r/^\d+\.\d+\/\d+\.\d+[ \t]+/m
def prefix(:line_comment), do: ~r/^%[ \t]?/m
```

- `blocks/2`: `prefixes = options |> Keyword.get(:prefix, []) |> List.wrap()`. In `body/3`, before `String.trim/1`, `Enum.reduce(prefixes, raw, &Regex.replace(&1, &2, ""))`. The slice begins at the line feed after the start marker, so `^` with `m` sees every body line.
- The block carries `prefix: prefixes`.
- `status/1` and the start/end markers need nothing: `^[^\r\n]*?[%#]` (and R1's alternative) already skip any prefix.
- Patterns are returned from function clauses, not module attributes, so AtpClient does not spell them; both are documented with the line they are for.

Tests: `blocks(starexec_e_theorem_fixture_with_a_proof_block, prefix: Szs.prefix(:starexec))` body lexes — assert `Tptp.from_string(body)` yields statements and no error diagnostics (the existing `starexec_e_theorem.txt` has no output block; use the E CNFRefutation capture from section 8 run through StarExec, or synthesise one by prefixing every line of a known-good block with varying `0.0N/0.0M\t`); `prefix: [Szs.prefix(:line_comment), Szs.prefix(:starexec)]` on a `% 0.12/0.45  fof(…)` body; the default strips nothing and `prefix: []`; a block's `prefix` echoes the list given.

## 5 R3 — `Tptp.Derivation`

A derivation is a `Tptp.File` whose annotated statements' `source` fields form a graph. The module walks the grammar's `<source>` tree (section 2) and builds an index; it interprets nothing beyond that structure.

### 5.1 Types

```elixir
defmodule Tptp.Derivation do
  @type t :: %__MODULE__{
    file:   Tptp.File.t(),
    nodes:  %{binary() => Tptp.Derivation.Node.t()},   # key: Tptp.Node.value/1 of <name>
    order:  [binary()],                                  # one entry per name, at the winning statement's position (D5)
    roots:  [binary()],                                  # parent of no node, in `order`
    leaves: [binary()]                                   # parents == [], in `order` (C5)
  }
end

defmodule Tptp.Derivation.Node do
  @type origin ::
          {:file, file_name :: binary(), formula :: binary() | nil}      # file('x.p') / file('x.p', ax1)
        | {:introduced, intro_type :: binary(), info :: Tptp.Node.t()}    # introduced(definition, [...], [...])
        | {:name, binary()}                                               # a bare <name>, `unknown` included (C3)
        | :inference                                                      # one or more inference records
        | :none                                                           # no annotations (C3)
        | {:unknown, Tptp.Node.t()}                                       # any other shape

  @type t :: %__MODULE__{
    name:      binary(),
    statement: Tptp.Statement.Annotated.t(),
    origin:    origin(),
    steps:     [[Tptp.Derivation.Step.t()]],   # one list per alternative source; [] when origin is not :inference
    parents:   [binary()]                      # union of named parents over all steps and the origin, source order, no duplicates
  }
end

defmodule Tptp.Derivation.Step do
  @type parent :: binary() | {:step, non_neg_integer()}   # C4

  @type t :: %__MODULE__{
    rule:    binary(),                         # Tptp.Node.value/1 of <inference_rule>
    status:  Tptp.Szs.Ontology.t() | nil,      # status(<word>) via Ontology.from_status_value/1 (C1)
    info:    Tptp.Node.t(),                    # the whole <useful_info> general_list, uninterpreted
    parents: [parent()],                       # in source order
    details: %{binary() => Tptp.Node.t()}      # <parent_details> general_term by parent name; named parents only
  }
end
```

Every struct has `@enforce_keys` for every field, `@typedoc` on every type, and an `Inspect` implementation on `Tptp.Derivation` that prints the counts (`#Tptp.Derivation<54 nodes, 11 leaves, 1 root>`), following `Tptp.File`'s — the derived one would print the file.

### 5.2 Classifying a statement's `source`

Let `s = statement.source`.

| `s` | origin | steps | parents |
|---|---|---|---|
| `nil` | `:none` | `[]` | `[]` |
| `%Node{kind: :name}` | `{:name, value}` | `[]` | `[value]` |
| `%Node{kind: :file_source, children: [file_name]}` | `{:file, value(file_name), nil}` | `[]` | `[]` |
| `%Node{kind: :file_source, children: [file_name, %{kind: :file_info, children: [name]}]}` | `{:file, value(file_name), value(name)}` | `[]` | `[]` |
| `%Node{kind: :internal_source, children: [intro_type, info, parents]}` | `{:introduced, value(intro_type), info}` | `[]` | named parents of `parents` (5.3, names only) |
| `%Node{kind: :inference_record}` | `:inference` | `[flatten(s)]` | names in the step list |
| `%Node{kind: :source, children: [c]}` (bracketed) | see below | one list per alternative | union |
| anything else | `{:unknown, s}` | `[]` | `[]` |

Bracketed source: alternatives are the members of `c` in order (`c` is one source, or a `:sources` node whose right spine is unrolled: `[a, b, c]` arrives as `sources(a, sources(b, c))`). If every alternative is an inference record, origin is `:inference` and `steps` has one list per alternative. Otherwise origin is `{:unknown, s}`, `steps` has a list for each inference-record alternative, and `parents` is still the union of every name found in any alternative. `parents` is deduplicated keeping first occurrence.

### 5.3 Flattening an inference record

`flatten(record)` returns a step list; inner records come first (inside-out), the record itself last.

```
flatten(%Node{kind: :inference_record, children: [rule, info, parents]}):
  acc = []
  step_parents = []; details = %{}
  for parent_info <- items(parents):            # parents children [] | [parent_list]; parent_list children are parent_info
    [source | rest] = parent_info.children
    detail = case rest do [%{kind: :parent_details, children: [term]}] -> term; [] -> nil end
    case source do
      %{kind: :name} ->
        n = value(source); step_parents ++ [n]; if detail, details[n] = detail
      %{kind: :inference_record} ->
        inner = flatten(source); acc = acc ++ inner
        step_parents ++ [{:step, length(acc) - 1}]        # the inner record's own step is last in `inner`
      %{kind: :source} (bracketed, in parent position) ->
        treat each member in order as above               # alternatives are not modelled below the top level
      other ->
        ignore for parents; the node is still reachable through `info`/`statement.source`
    end
  acc ++ [%Step{rule: value(rule), status: status(info), info: info, parents: step_parents, details: details}]
```

`status(info)`: the first `:general_function` among the items of `info` whose first child's `value/1` is `"status"` and whose `general_terms` has exactly one leaf child; `Ontology.from_status_value(value(leaf))` → `{:ok, v}` gives `v`, anything else `nil`. Only direct items of the list are inspected, not nested lists.

No synthetic names are created; the anonymous intermediate formulae are not in the file and get no node. E's `inference(sr,[status(thm)],[inference(cn,[status(thm)],[inference(rw,[status(thm)],[c_0_7,c_0_8])]),c_0_9])` becomes `[rw{parents: ["c_0_7", "c_0_8"]}, cn{parents: [{:step, 0}]}, sr{parents: [{:step, 1}, "c_0_9"]}]`.

### 5.4 Building

```elixir
@spec from_file(Tptp.File.t()) :: {:ok, t(), [Tptp.Diagnostic.t()]}
@spec from_string(binary(), [Tptp.option()]) :: {:ok, t(), [Tptp.Diagnostic.t()]}   # Tptp.from_string/2 first; its diagnostics are prepended
```

Never `{:error, _}`: the graph is always returned. Diagnostics, each with a span in `file.id`:

- **Duplicate name** — `DuplicateName.code()`, `:warning`, span of the later statement's `name` node, `related: [span of the earlier]`, message as the lint rule's ("`"c_0_7"` names 2 statements" — reuse its wording). The later statement wins in `nodes` (D5).
- **Parent names no statement** — `Parent.code()`, `:warning`, span of the `:name` node in the source slot, one per occurrence. Not raised for `"unknown"` (the lint rule excludes it too) and not raised when the file has no annotated statement at all.
- **Cycle** — `"TPTP0507"`, `:warning`, span of the `name` node of the first node in `order` that lies on a cycle, `related:` the names of the other nodes on that cycle, message "`"a"` is derived from itself through `b`, `c`", hint "a derivation is a DAG; `Tptp.Derivation.acyclic?/1` is false". One diagnostic per strongly connected component of size > 1 or self-loop.

`roots`/`order` stay the textual facts when there is a cycle.

### 5.5 Queries

All operate on `nodes` and ignore `{:step, _}` references (those are intra-node).

```elixir
@spec ancestors(t(), binary()) :: [binary()]      # transitive parents, in `order`, the node itself excluded; [] for an unknown name
@spec descendants(t(), binary()) :: [binary()]    # transitive children, in `order`
@spec cone(t(), binary()) :: t()                   # sub-derivation ending in the node: it and its ancestors; a new t whose file is per D2
@spec acyclic?(t()) :: boolean()
@spec topological(t()) :: {:ok, [binary()]} | :error   # parents before children; ties broken by `order`; :error on a cycle
```

`cone/2`'s `nodes` are the retained ones with `parents` filtered to retained names (a parent that named no statement is dropped there, as the diagnostic already said). `Tptp.Printer.Canonical.to_string(cone.file)` prints it and `Tptp.Statement.text/2` slices it; no new printer.

### 5.6 Tests (`test/tptp/derivation_test.exs`)

- Doctests for every public function on a 4-statement inline derivation.
- The E `CNFRefutation` fixture: the nested record above flattens as stated; every `status` resolves; `roots == ["c_0_N"]` with the `$false` statement; `leaves` are the `file(…)` nodes; `acyclic?/1`; `topological/1` puts every parent before its child (property over the result).
- The Vampire `Proof` fixture: `introduced(…)` nodes are leaves; `file('…', name)` origin carries the formula name.
- The TSTP `PUZ001+1/E---3.5.1.THM-CRf.s` solution, read through `Tptp.Tstp` (section 6): `from_file(solution.solution)` has `length(order) == 54` (the header's "Number of formulae"); the number of leaves equals the header's "Number of leaves".
- The E `Saturation` fixture: no `$false`, several roots, `['final']` in `info` leaves `status: nil`.
- Hand-written: a duplicate name (later wins, `TPTP0503`), a missing parent (`TPTP0504`, not for `unknown`), a 2-cycle (`TPTP0507`, `topological/1 == :error`), a bare-name source (`{:name, _}`, listed in `parents`, not a leaf), a statement without annotations (`:none`, a leaf and a root), a bracketed alternative source (two step lists, union parents), `'quoted'` and unquoted names unify.
- `cone/2` round trip: `cone |> Map.get(:file) |> Tptp.Printer.Canonical.to_string() |> Tptp.from_string()` yields the same statement names; comments inside retained statements survive, others do not.
- Atom count unchanged across reading a fixture with an unknown `status(xyz)` and an unknown rule name (pattern: `szs_test.exs` "no atom is created from an unknown word").

## 6 R4 — `Tptp.Tstp` — solution files

The TSTP library's solution files and SystemOnTPTP's `X2TPTP` replies share one shape:

```
%------------------------------------------------------------------------------   rule
% File     : E---3.5.1                                                              header: `% Key : value`
% Problem  : PUZ001+1 : TPTP v9.3.1. Released v2.0.0.
…
% Result   : Theorem 0.12s 0.45s
% Output   : CNFRefutation 0.12s
% SZS Type : Refutation
%            Derivation depth      :    8                                           continuation: `%` + ≥ 2 spaces
…
% Comments :
%------------------------------------------------------------------------------   rule
fof(…).                                                                             solution, TPTP
…
%------------------------------------------------------------------------------   rule
%----ORIGINAL SYSTEM OUTPUT                                                         marker
% 0.12/0.45  % SZS status Theorem                                                  every original line behind `% `
…
%------------------------------------------------------------------------------   rule
```

### 6.1 Types and API

```elixir
defmodule Tptp.Tstp.Solution do
  @type t :: %__MODULE__{
    header:   %{binary() => binary()},       # "Result" => "Theorem 0.12s 0.45s"; continuation lines joined with "\n"; keys in file order are not kept — use `keys`
    keys:     [binary()],                    # header keys in file order
    result:   Tptp.Szs.Ontology.t() | nil,   # first word of "Result", via Ontology.from_string/1; nil if absent or unknown
    output:   Tptp.Szs.Ontology.t() | nil,   # first word of "Output"
    solution: Tptp.File.t() | nil,           # the statements between rules 2 and 3, parsed; nil when that region has no statement
    original: binary() | nil,                # the ORIGINAL SYSTEM OUTPUT section with Szs.prefix(:line_comment) removed from every line; nil when absent
    span:     %{solution: {non_neg_integer(), non_neg_integer()} | nil,
                original: {non_neg_integer(), non_neg_integer()} | nil}   # {off, len} into the input
  }
end

defmodule Tptp.Tstp do
  @spec from_string(binary(), [Tptp.option()]) ::
          {:ok, Tptp.Tstp.Solution.t(), [Tptp.Diagnostic.t()]} | {:error, :not_tstp}
  @spec from_file(Path.t(), [Tptp.option()]) ::
          {:ok, Tptp.Tstp.Solution.t(), [Tptp.Diagnostic.t()]} | {:error, :not_tstp} | {:error, [Tptp.Diagnostic.t()]}
end
```

`keys` is an addition to the requirement's struct: a map loses the header's order and a writer or a renderer wants it.

### 6.2 Reading

Patterns (module attributes, `m` flag, `[ \t]` for horizontal space):

- rule: `~r/^%-{4,}[ \t]*\r?$/m`
- key line: `~r/^%[ \t](\S(?:[^:\r\n]*?\S)?)[ \t]*:[ \t]?([^\r\n]*?)[ \t]*\r?$/m` — the key is from column 3 to the first ` :`; "SZS Type" and "CPULimit" are both keys; "Problem  : PUZ001+1 : TPTP v9.3.1" has key `Problem` and value `PUZ001+1 : TPTP v9.3.1. Released v2.0.0.` (only the first `:` after the key splits).
- continuation: `~r/^%[ \t]{2,}([^\r\n]*?)[ \t]*\r?$/m` — appended to the previous key's value with `"\n"`; a continuation before any key, or a bare `%` line, is skipped.
- original marker: `~r/^%----ORIGINAL SYSTEM OUTPUT[ \t]*\r?$/m`

Algorithm:

1. Find the first rule at offset 0 (leading white space allowed, nothing else). Absent → `{:error, :not_tstp}`.
2. Read header lines until the next rule. If there is no `File` key → `{:error, :not_tstp}`. (A SystemOnTPTP reply without `X2TPTP`, a raw prover log, an empty string all fall here.)
3. The region after the second rule up to the third rule (or end of input) is the solution region: `span.solution = {off, len}` of that region with surrounding blank lines trimmed; `solution = Tptp.from_string(binary_part(input, off, len), options)` — a sub-binary, nothing copied. If the region holds no statement (`statements == []`), `solution` is `nil` and `span.solution` is still the region. Its diagnostics are returned with their spans shifted by `off` so they index the whole file.
4. After the third rule, if the next line is the original marker, the region to the next rule (or end) is `span.original`; `original = Regex.replace(Szs.prefix(:line_comment), region, "")`. Absent → `original: nil`.
5. `result`/`output`: `header["Result"] |> String.split(" ", parts: 2) |> hd() |> Ontology.from_string()`.

`original` is what `Tptp.Szs.status/1` and `blocks/2` read next; in the `X2TPTP` reply the proof block there is `% See solution above`, which is why `solution` is the derivation and `original` is everything else. For a StarExec-stamped original, the caller passes `prefix: Szs.prefix(:starexec)` to `blocks/2`.

Not in scope: writing TSTP files.

### 6.3 Tests (`test/tptp/tstp_test.exs`)

- The `PUZ001+1/E---3.5.1.THM-CRf.s` fixture: `header["File"] == "E---3.5.1"`, `header["Problem"]` starts with `"PUZ001+1 : TPTP"`, `header["SZS Type"]` has a `"\n"` (continuations), `result == :theorem`, `output == :cnf_refutation`, `solution` has 54 statements and no error diagnostics, `Szs.status(original) == {:ok, :theorem, nil, nil}` (or with the problem, as the capture has it), `binary_part(input, span.solution…)` starts with `fof(`.
- The live `X2TPTP` reply fixture: same shape; `original` contains `% See solution above`.
- `from_string("")`, a raw E log, `starexec_e_theorem.txt` → `{:error, :not_tstp}`.
- A hand-written minimal file: rule, `% File : x`, rule, one `fof`, rule, marker, two lines, rule — every field; `\r\n` line ends; no original section; empty solution region.
- `from_file/2` on a missing path → `{:error, [diagnostic]}` with `TPTP0001`, as `Tptp.from_file/2`.

## 7 R5 — sub-roles

Parsing and printing already work (section 2). Missing: tests and the five readers of `role.text` (C2).

### 7.1 `Tptp.Statement.Annotated`

```elixir
@doc "The role's `<lower_word>`: the role itself, or the word before `-` in a sub-role such as `interpretation-domains`."
@spec role_word(t()) :: binary()
def role_word(%__MODULE__{role: %Node{text: word}}) when is_binary(word), do: word
def role_word(%__MODULE__{role: %Node{children: [%Node{text: word} | _rest]}}), do: word

@doc "The `<general_term>` of a sub-role, or `nil` for a plain role."
@spec subrole(t()) :: Node.t() | nil
def subrole(%__MODULE__{role: %Node{children: [_word, term]}}), do: term
def subrole(%__MODULE__{}), do: nil
```

Moduledoc, one sentence in "Uninterpreted fields": a sub-role `<lower_word>-<general_term>` is a two-child `:formula_role` node with `text: nil`; `role_word/1` and `subrole/1` read either form. The `Inspect` implementation prints `Annotated.role_word(statement)` (and, for a sub-role, `-…` is not reconstructed — the word suffices there).

### 7.2 Routing

| Site | Change |
|---|---|
| `Tptp.Lint.Rules.Role.visit/3` | Match `%Node{kind: :formula_role} = node` in slot `:role` without the `is_binary` guard; take the word from `Context.role(context)`; report the span of the whole role node. The `lower_word` of a sub-role is thereby checked (`wibble-[1]` warns, `interpretation-domains` does not). |
| `Tptp.Lint.Context.role/1` | `Annotated.role_word(statement)`. |
| `Tptp.Lint.Collect.typing?/1` | `Annotated.role_word(statement) == "type" and …`, so `tff(d, type-datatype, …)` is collected as a declaration. Check `Lint.Rules.Declaration`/`AtomTyping` still hold on that input. |
| `Tptp.Query.roles/1` | Count `Annotated.role_word/1`. Document that sub-roles are counted under their word. |
| `Tptp.Statement.Annotated` `Inspect` | `role_word/1`. |

`Tptp.Query.conjectures/1` matches `%{text: text}` with `text in [...]` and is unaffected (a sub-role never equals those words); leave it.

### 7.3 Tests

- `parser_test.exs`: `fof(interp_domain, interpretation-domains, p).` and `tff(m, interpretation-mappings(f,$i), p).` parse; `role.children` is `[%Node{kind: :lower_word, text: "interpretation"}, %Node{kind: :lower_word, text: "domains"}]` for the first and `[lower_word, %Node{kind: :general_function}]` for the second; `role_word/1` and `subrole/1`.
- `printer_test.exs`: canonical print of both is `interpretation-domains` / `interpretation-mappings(f,$i)` and round-trips by `Node.shape/1`.
- `lint_test.exs`: `wibble-[1]` raises `TPTP0401` at the role span; `interpretation-domains` raises nothing; `tff(d, type-datatype, nat: $tType).` is collected as a declaration (no `TPTP0501` for a later use of `nat`).
- `inspect_test.exs`: `inspect/1` of a sub-role statement returns `"#Tptp.Statement.Annotated<fof \"interp_domain\": interpretation, 0..N>"` and does not raise.
- `query_test.exs`: `roles/1` on a file with `interpretation-domains` and `interpretation-mappings(…)` is `%{"interpretation" => 2}`.

## 8 Fixtures

None of the fixtures named in the requirements exist, and the author does not have them. Every fixture below is to be committed under `test/fixtures/`, with a `test/fixtures/tstp/README.md` recording for each: where it came from, the command or form submission, the date, and whether it is a live capture or synthetic.

| Path | Content | Source | Used by |
|---|---|---|---|
| `szs/paradox_finite_model.txt` | Paradox 4.0 raw output, bare `SZS` lines | SystemOnTPTP, `Paradox---4.0`, a satisfiable FOF problem (e.g. `SYN000+1` negated or any `SAT` problem such as `PUZ001+1` with the conjecture dropped); raw reply, no `X2TPTP` | R1 |
| `tstp/E---3.5.1.THM-CRf.s` | TSTP library solution file | `https://www.tptp.org/cgi-bin/SeeTPTP?Category=Solutions&Domain=PUZ&File=PUZ001+1&System=E---3.5.1.THM-CRf.s` (verify the current System name on the problem's Solutions page; take the raw file, not the HTML view) | R2, R3, R4 |
| `tstp/e_cnfrefutation_x2tptp.txt` | Live SystemOnTPTP reply for `PUZ001+1` with E and `X2TPTP` on | `https://www.tptp.org/cgi-bin/SystemOnTPTPFormReply` (parameters as AtpClient's SystemOnTPTP backend sends them; the form at `https://www.tptp.org/cgi-bin/SystemOnTPTP` shows the field names) | R3, R4 |
| `tstp/e_cnfrefutation_raw.txt` | Same problem, E, raw reply (no `X2TPTP`) — nested `inference(sr,[…],[inference(cn,…)])` records | SystemOnTPTP | R3 |
| `tstp/vampire_proof_raw.txt` | Same problem, Vampire, raw reply | SystemOnTPTP | R3 |
| `tstp/e_saturation_raw.txt` | E on a satisfiable problem with `--print-saturated`-style output: statements with `['final']` info, no `$false` | SystemOnTPTP, E on a `CSA`/`SAT` problem | R3 |
| `szs/starexec_e_proof.txt` | A StarExec-stamped E output containing a `Proof` block | AtpClient's `test/fixtures/starexec_stdout_thm.txt` if it holds a block; else synthetic (below) | R2 |

If the sandbox cannot reach tptp.org: write synthetic fixtures from the excerpts in the requirements (the Paradox lines, the TSTP header, the E nested record) and from derivations composed by hand, name them `*_synthetic.*`, say so in the README, and list "replace synthetic fixtures with live captures" in the CHANGELOG's Unreleased section and in the release checklist (section 9). Synthetic fixtures must not claim counts the real file has (the 54 / 11 assertions in 5.6 and 6.3 are for the real `E---3.5.1.THM-CRf.s` only; guard them with `@tag :live_fixture` and skip when the README marks the file synthetic).

The requirement's `starexec_stdout_thm.txt` (AtpClient) is already here as `szs/starexec_e_theorem.txt` and contains no output block.

## 9 Order of work, gates, release

Work in this order; each step ends with `mix check` green (format, compile with warnings as errors, credo strict, test, dialyzer) and a commit.

1. **R5** — `role_word/1`, `subrole/1`, the five sites, tests. Smallest, self-contained, fixes a crash.
2. **R1** — the three regexes, doctests, Paradox fixture (or synthetic).
3. **R2** — `blocks/2`, `prefix/1`, the `block` type, tests. Public type change: CHANGELOG under Changed.
4. **Fixtures** — fetch what section 8 lists; README.
5. **R4** — `Tptp.Tstp`, `Tptp.Tstp.Solution`, tests. Before R3 so the TSTP fixture's solution can feed R3.
6. **R3** — `Tptp.Derivation` and its two structs, `TPTP0507`, tests.
7. **R6** — housekeeping:
   - `mix.exs`: `@version "0.2.0"`; `groups_for_modules` gains `TSTP: [Tptp.Derivation, Tptp.Derivation.Node, Tptp.Derivation.Step, Tptp.Tstp, Tptp.Tstp.Solution]`.
   - `Tptp.Diagnostic` tier table: `TPTP05xx` line mentions `Tptp.Derivation`; `TPTP0507` is no longer free.
   - `README.md`: a short "Derivations and TSTP files" section with one example each.
   - `CHANGELOG.md`: section 10. `bnf_version/0` unchanged (no regeneration).
   - `CITATION.cff` / `.zenodo.json`: version and date, if they carry them.
   - Run `mix docs` once and open `Tptp.Derivation` and `Tptp.Tstp` to check the moduledocs render; `mix tptp.corpus`/`census` are unaffected.
8. Tag `v0.2.0` only after the live fixtures are in place (or the synthetic ones are consciously accepted and recorded).

Rules that bite in this codebase:
- No `String.to_atom` or relatives anywhere (`checks/no_dynamic_atoms.ex`, Credo). Rule names, intro types, header keys and words stay binaries; only `Ontology.from_string/1` and `from_status_value/1` reach atoms.
- Every public function `@doc`, every type `@typedoc`, every module `@moduledoc` (`test/tptp/documentation_test.exs`).
- `@spec` on every public function (Credo `Readability.Specs`); Dialyzer runs with `:extra_return` and `:unknown`.
- Regexes: `[ \t]`, never `\s`/`\h` (`szs.ex:89`); `\r?$` before the end anchor.
- Sub-binaries over copies: `binary_part/3` for slices, no `String.slice/3`.

## 10 CHANGELOG draft

```markdown
## [0.2.0] - YYYY-MM-DD

Derivations and TSTP solution files are read as structure, and the SZS reader
accepts two more shapes systems print in practice.

### Added

- `Tptp.Derivation`: a `Tptp.File` indexed as a graph over its statements' `source`
  annotations — `nodes`, `order`, `roots`, `leaves`; `ancestors/2`, `descendants/2`,
  `cone/2`, `acyclic?/1`, `topological/1`. Nested inference records are flattened
  inside-out into `Tptp.Derivation.Step` lists; `[sources]` alternatives give one
  list each. `status(thm)` resolves through `Tptp.Szs.Ontology.from_status_value/1`.
  A parent naming no statement is reported as `TPTP0504`, a duplicate name as
  `TPTP0503` (the later statement wins), and a cycle as the new `TPTP0507`; the
  graph is always returned.
- `Tptp.Tstp`: reads a TSTP solution file or SystemOnTPTP `X2TPTP` reply into a
  `Tptp.Tstp.Solution` — the `% Key : value` header, `result` and `output` through
  the ontology, the solution parsed as a `Tptp.File` (a sub-binary of the input),
  and the ORIGINAL SYSTEM OUTPUT with its `% ` prefix removed, for `Tptp.Szs` to
  read. Anything not a TSTP file is `{:error, :not_tstp}`.
- `Tptp.Szs.blocks/2` takes `prefix: regex | [regex]`, removed from every body
  line in order; `Tptp.Szs.prefix/1` names the two that occur (`:starexec`,
  `:line_comment`). The block records what was removed.
- `Tptp.Statement.Annotated.role_word/1` and `subrole/1`, for the sub-role form
  `<lower_word>-<general_term>` (`interpretation-domains`, `type-datatype`).

### Changed

- `t:Tptp.Szs.block/0` gains `prefix: [Regex.t()]` (`[]` when nothing was
  stripped). Code matching the map exhaustively needs the key.
- The SZS readers accept `SZS status` and `SZS output start|end` at the start of a
  line with no comment character before them, as Paradox prints them. The `for`
  value may be a path with a `:suffix`; it is taken whole.
- `Tptp.Lint.Rules.Role` checks the `<lower_word>` of a sub-role; `Tptp.Lint`
  collects `type-datatype` typings as declarations; `Tptp.Query.roles/1` counts a
  sub-role under its word.

### Fixed

- `inspect/1` of an annotated formula with a sub-role raised `FunctionClauseError`.
```

## 11 Open items for AtpClient

- C1 (`from_status_value`, no ambiguous case), C3 (`{:name, _}`, `:none`), C4 (`{:step, i}` for `:previous`), C5 (`leaves` = no parents), D3 (`prefix` is a list), D4 (`{:error, :not_tstp}`), the `keys` field on `Tptp.Tstp.Solution`.
- `Result.proof/1` reads `block.body` after `blocks(output, prefix: Tptp.Szs.prefix(:starexec))`; the `@type` for a block gains `prefix: [Regex.t()]`.
