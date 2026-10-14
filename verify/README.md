# Proofs

A Lean 4 project that models the hand-written parts of this library byte for
byte and proves, with the kernel, what the test suite can only sample. Each file
carries the Elixir it models and records what the proof found.

| File | Models | Finding |
|---|---|---|
| `Tptp/Lexer/Quoted.lean` | `Tptp.Lexer.quoted_body` | The 0.2.0 scanner accepted `'a\b'`, a tab, a control character and a non-ASCII byte between quotes as clean tokens, which `<sq_char>` and `<do_char>` forbid. The repaired scanner reports a body exactly when it leaves the class, and cuts the token at the same place as before. |
| `Tptp/Lexer/Number.lean` | `Tptp.Lexer.number` and its two diagnostics | `007e1` is a `<real>`, since `<decimal_exponent>` begins with `<integer_digits>`, and the 0.2.0 rule reported it. With the exponent-only form exempt, a number carries a diagnostic exactly when it is outside `<integer>`, `<rational>` or `<real>`. |
| `Tptp/Span.lean` | `Tptp.Span.line_index/1`, `line_column/2`, `offset/3` | Nothing. The two lookups are inverse on every index the first can build. |
| `Tptp/Derivation.lean` | the set `Tptp.Derivation.cone/2` retains | Every edge into a retained node comes from a retained node, so the 0.2.0 filter on a cone's `parents` could only drop names that resolved to nothing. Removing it makes a node a leaf of its cone exactly when it is a leaf of the derivation. |

The models are transcriptions, not translations: a reader has to compare each
Lean definition with the Elixir quoted above it, which is why every file keeps
the Elixir in view. The theorems rely on no axiom beyond Lean's three standard
ones; `#print axioms` on any of them says so.

## Running

```
cd verify
lake build
```

`lean-toolchain` names the release. No package beyond Lean's own library is
used, so the build needs no network access once the toolchain is installed.

## Why not translate the Elixir automatically

[Lynx](https://github.com/josevalim/lynx) translates Core Erlang to Lean and
would remove the transcription step. At the time of writing its runtime models
integers, atoms, lists, tuples, maps, bitstrings and a handful of BIFs; its
translator has no case for binary construction or binary pattern matching and
no `binary_part/3` or `element/2`, and every function modelled here is built
from those. The models are written so
that a future translation can be checked against them.
