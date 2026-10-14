/-!
# `Tptp.Lexer.quoted_body`, modelled byte for byte

The Elixir scanner reads the body of a `<single_quoted>` or `<distinct_object>`
token after its opening quote. As shipped in 0.2.0:

```elixir
defp quoted_body(<<?\\, c, rest::binary>>, quote_byte, taken)
     when c == ?\\ or c == quote_byte,
  do: quoted_body(rest, quote_byte, taken + 2)
defp quoted_body(<<c, rest::binary>>, c, taken), do: {:ok, taken, rest}
defp quoted_body(<<?\n, _::binary>> = tail, _quote_byte, taken), do: {:unterminated, taken, tail}
defp quoted_body(<<>>, _quote_byte, taken), do: {:unterminated, taken, ""}
defp quoted_body(<<_c, rest::binary>>, quote_byte, taken), do: quoted_body(rest, quote_byte, taken + 1)
```

The BNF admits only

```
<single_quoted>   ::- <single_quote><sq_char><sq_char>*<single_quote>
<sq_char>         ::: ([\40-\46\50-\133\135-\176]|([\\]['\\]))
<distinct_object> ::- <double_quote><do_char><do_char>*<double_quote>
<do_char>         ::: ([\40-\41\43-\133\135-\176]|([\\]["\\]))
```

that is, a printable ASCII byte other than the quote and the backslash, or a
backslash escaping the quote or itself. `Tptp.LexerOracleTest` states that
every token the lexer emits without a diagnostic satisfies its BNF pattern.
This file shows that the claim was false of the shipped scanner (`'a\b'`, a tab,
a control character or a non-ASCII byte between quotes all came back as a token
with nothing said about it) and proves it of the repaired scanner, which reports
such a body with `TPTP0112`.

The quote byte `q` is always `'` (`0x27`) or `"` (`0x22`); the theorems assume
only that it is not the backslash.
-/

namespace Tptp.Lexer.Quoted

/-- Bytes, as the Elixir scanner sees them. -/
abbrev Byte := UInt8

/-- What one call to `quoted_body/3` answers. -/
inductive Scan where
  /-- The closing quote was found after `taken` body bytes; `rest` follows it. -/
  | ok (taken : Nat) (rest : List Byte)
  /-- A line feed or the end of input came first. -/
  | unterminated (taken : Nat) (rest : List Byte)
deriving DecidableEq, Repr

/-- The shipped scanner, clause for clause. A backslash whose guard fails is
skipped on its own by the last clause, which is what the second branch of the
first equation spells out. -/
def quotedBody : List Byte → Byte → Nat → Scan
  | 0x5C :: c :: rest, q, taken =>
    if c = 0x5C ∨ c = q then quotedBody rest q (taken + 2)
    else quotedBody (c :: rest) q (taken + 1)
  | c :: rest, q, taken =>
    if c = q then .ok taken rest
    else if c = 0x0A then .unterminated taken (c :: rest)
    else quotedBody rest q (taken + 1)
  | [], _, taken => .unterminated taken []

/-- A byte the character class admits on its own: printable ASCII, not the
quote, not the backslash. For `q = '` this is `<sq_char>`'s first alternative
and for `q = "` it is `<do_char>`'s. -/
def plain (q c : Byte) : Bool :=
  0x20 ≤ c && c ≤ 0x7E && c ≠ q && c ≠ 0x5C

/-- `<sq_char>*` / `<do_char>*`: the bodies the BNF admits. -/
inductive Body (q : Byte) : List Byte → Prop
  | nil : Body q []
  | plain {c rest} : plain q c = true → Body q rest → Body q (c :: rest)
  | esc {c rest} : (c = 0x5C ∨ c = q) → Body q rest → Body q (0x5C :: c :: rest)

/-- The same, decidably. -/
def bodyOk (q : Byte) : List Byte → Bool
  | [] => true
  | 0x5C :: c :: rest => (c = 0x5C || c = q) && bodyOk q rest
  | c :: rest => plain q c && bodyOk q rest

/-- Strong induction on the length of a list, for scanners that step over
two bytes at a time. -/
theorem list_strong_induction {α : Type} {P : List α → Prop}
    (step : ∀ l, (∀ l', l'.length < l.length → P l') → P l) : ∀ l, P l := by
  have : ∀ k (l : List α), l.length ≤ k → P l := by
    intro k
    induction k with
    | zero => intro l hl; exact step l (fun l' h => by omega)
    | succ k ih => intro l hl; exact step l (fun l' h => ih l' (by omega))
  intro l
  exact this l.length l (Nat.le_refl _)

theorem plain_not_backslash {q c : Byte} (h : plain q c = true) : c ≠ 0x5C := by
  intro hc; subst hc; simp [plain] at h

theorem plain_not_quote {q c : Byte} (h : plain q c = true) : c ≠ q := by
  intro hc; subst hc; simp [plain] at h

theorem body_of_bodyOk (q : Byte) : ∀ l, bodyOk q l = true → Body q l := by
  apply list_strong_induction
  intro l ih
  match l with
  | [] => intro _; exact Body.nil
  | [c] =>
    intro h
    simp only [bodyOk, Bool.and_eq_true] at h
    exact Body.plain h.1 Body.nil
  | c :: d :: rest =>
    intro h
    by_cases hc : c = 0x5C
    · subst hc
      simp only [bodyOk, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at h
      exact Body.esc h.1 (ih rest (by simp <;> omega) h.2)
    · have : bodyOk q (c :: d :: rest) = (plain q c && bodyOk q (d :: rest)) := by
        simp [bodyOk, hc]
      rw [this] at h
      simp only [Bool.and_eq_true] at h
      exact Body.plain h.1 (ih (d :: rest) (by simp <;> omega) h.2)

theorem bodyOk_of_body (q : Byte) : ∀ {l}, Body q l → bodyOk q l = true := by
  intro l h
  induction h with
  | nil => rfl
  | @plain c rest hp _ ih =>
    have hc := plain_not_backslash hp
    cases rest with
    | nil => simp [bodyOk, hp]
    | cons d rest' =>
      have : bodyOk q (c :: d :: rest') = (plain q c && bodyOk q (d :: rest')) := by
        simp [bodyOk, hc]
      rw [this]; simp [hp, ih]
  | @esc c rest he _ ih => simp [bodyOk, he, ih]

theorem bodyOk_iff (q : Byte) (l : List Byte) : bodyOk q l = true ↔ Body q l :=
  ⟨body_of_bodyOk q l, bodyOk_of_body q⟩

/-- A body beginning with a backslash is an escape followed by a body. -/
theorem body_backslash {q : Byte} {l : List Byte} (h : Body q (0x5C :: l)) :
    ∃ c rest, l = c :: rest ∧ (c = 0x5C ∨ c = q) ∧ Body q rest := by
  generalize hs : (0x5C :: l) = s at h
  cases h with
  | nil => cases hs
  | plain hp _ => cases hs; exact absurd rfl (plain_not_backslash hp)
  | esc he hr => cases hs; exact ⟨_, _, rfl, he, hr⟩

/-- A body beginning with any other byte is a plain byte followed by a body. -/
theorem body_cons {q c : Byte} {l : List Byte} (hc : c ≠ 0x5C) (h : Body q (c :: l)) :
    plain q c = true ∧ Body q l := by
  generalize hs : (c :: l) = s at h
  cases h with
  | nil => cases hs
  | plain hp hr => cases hs; exact ⟨hp, hr⟩
  | esc _ _ => cases hs; exact absurd rfl hc

/-! ## The shipped scanner accepts bodies the BNF does not -/

/-- `'a\b'`: scanned as a three-byte body, which `<sq_char>*` rejects. -/
theorem counterexample_backslash :
    quotedBody [0x61, 0x5C, 0x62, 0x27] 0x27 0 = .ok 3 [] ∧
      bodyOk 0x27 [0x61, 0x5C, 0x62] = false := by decide

/-- `'a<TAB>b'` -/
theorem counterexample_tab :
    quotedBody [0x61, 0x09, 0x62, 0x27] 0x27 0 = .ok 3 [] ∧
      bodyOk 0x27 [0x61, 0x09, 0x62] = false := by decide

/-- `"a<0xC3><0xA9>"`: a UTF-8 `é` inside a distinct object. -/
theorem counterexample_utf8 :
    quotedBody [0x61, 0xC3, 0xA9, 0x22] 0x22 0 = .ok 3 [] ∧
      bodyOk 0x22 [0x61, 0xC3, 0xA9] = false := by decide

/-- So the backward property `Tptp.LexerOracleTest` states does not hold of the
shipped scanner: there is a body it accepts without complaint that is not in
the class. -/
theorem shipped_scanner_unsound :
    ¬ ∀ (s : List Byte) (q : Byte) (n : Nat) (rest : List Byte),
        quotedBody s q 0 = .ok n rest → Body q (s.take n) := by
  intro h
  have := h [0x61, 0x5C, 0x62, 0x27] 0x27 3 [] counterexample_backslash.1
  exact absurd (bodyOk_of_body _ this) (by decide)

/-! ## The repaired scanner -/

/-- What the repaired `quoted_body/4` answers: as before, plus whether every
byte of the body was admissible. -/
inductive Scan' where
  | ok (taken : Nat) (rest : List Byte) (clean : Bool)
  | unterminated (taken : Nat) (rest : List Byte)
deriving DecidableEq, Repr

/-- The repaired scanner. A byte outside the class is still consumed, so the
token and the statement survive, but `clean` records that it was seen. The
clause order is the Elixir clause order; the backslash's own case is written
first because the Elixir escape clause is. -/
def quotedBody' : List Byte → Byte → Nat → Bool → Scan'
  | 0x5C :: d :: rest', q, taken, clean =>
    if d = 0x5C ∨ d = q then quotedBody' rest' q (taken + 2) clean
    -- the guard failed: the backslash alone is skipped, and reported
    else quotedBody' (d :: rest') q (taken + 1) false
  | [0x5C], _, taken, _ => .unterminated (taken + 1) []
  | c :: rest, q, taken, clean =>
    if c = q then .ok taken rest clean
    else if c = 0x0A then .unterminated taken (c :: rest)
    else quotedBody' rest q (taken + 1) (clean && plain q c)
  | [], _, taken, _ => .unterminated taken []

/-! ### One lemma per clause -/

theorem qb_nil (q : Byte) (t : Nat) (c : Bool) : quotedBody' [] q t c = .unterminated t [] := by
  simp [quotedBody']

theorem qb_esc {q d : Byte} (h : d = 0x5C ∨ d = q) (rest : List Byte) (t : Nat) (c : Bool) :
    quotedBody' (0x5C :: d :: rest) q t c = quotedBody' rest q (t + 2) c := by
  simp [quotedBody', h]

theorem qb_lone {q d : Byte} (h : ¬ (d = 0x5C ∨ d = q)) (rest : List Byte) (t : Nat) (c : Bool) :
    quotedBody' (0x5C :: d :: rest) q t c = quotedBody' (d :: rest) q (t + 1) false := by
  simp [quotedBody', h]

theorem qb_lone_end (q : Byte) (t : Nat) (c : Bool) :
    quotedBody' [0x5C] q t c = .unterminated (t + 1) [] := by
  simp [quotedBody']

theorem qb_quote {q c : Byte} (h1 : c ≠ 0x5C) (h2 : c = q) (rest : List Byte) (t : Nat) (cl : Bool) :
    quotedBody' (c :: rest) q t cl = .ok t rest cl := by
  subst h2; simp [quotedBody', h1]

theorem qb_lf {q c : Byte} (h1 : c ≠ 0x5C) (h2 : c ≠ q) (h3 : c = 0x0A) (rest : List Byte) (t : Nat)
    (cl : Bool) : quotedBody' (c :: rest) q t cl = .unterminated t (c :: rest) := by
  subst h3; simp [quotedBody', h2]

theorem qb_step {q c : Byte} (h1 : c ≠ 0x5C) (h2 : c ≠ q) (h3 : c ≠ 0x0A) (rest : List Byte) (t : Nat)
    (cl : Bool) : quotedBody' (c :: rest) q t cl = quotedBody' rest q (t + 1) (cl && plain q c) := by
  simp [quotedBody', h1, h2, h3]

/-! ### The theorems -/

/-- Everything a successful scan establishes, in one statement so that one
induction proves it: the body is the input up to the quote, and it came back
`clean` exactly when the BNF admits it. -/
theorem quotedBody'_spec (q : Byte) (hq : q ≠ 0x5C) :
    ∀ (s : List Byte) (t : Nat) (c : Bool) (n : Nat) (rest : List Byte) (clean : Bool),
      quotedBody' s q t c = .ok n rest clean →
        (t ≤ n ∧ s = s.take (n - t) ++ q :: rest) ∧
          (clean = true ↔ (c = true ∧ Body q (s.take (n - t)))) := by
  apply list_strong_induction
  intro s ih t c n rest clean hs
  match s with
  | [] => simp [qb_nil] at hs
  | [x] =>
    by_cases hx : x = 0x5C
    · subst hx; simp [qb_lone_end] at hs
    · by_cases hxq : x = q
      · rw [qb_quote hx hxq] at hs
        cases hs
        subst hxq
        simp only [Nat.sub_self, List.take_zero, List.nil_append]
        exact ⟨⟨Nat.le_refl _, by simp⟩, fun h => ⟨h, Body.nil⟩, fun h => h.1⟩
      · by_cases hlf : x = 0x0A
        · rw [qb_lf hx hxq hlf] at hs; cases hs
        · rw [qb_step hx hxq hlf, qb_nil] at hs; cases hs
  | x :: y :: rest' =>
    by_cases hx : x = 0x5C
    · subst hx
      by_cases hy : y = 0x5C ∨ y = q
      · rw [qb_esc hy] at hs
        obtain ⟨⟨hle, heq⟩, hiff⟩ := ih rest' (by simp <;> omega) (t + 2) c n rest clean hs
        have hn : n - t = (n - (t + 2)) + 2 := by omega
        rw [hn]
        simp only [List.take_succ_cons, List.cons_append]
        refine ⟨⟨by omega, congrArg _ (congrArg _ heq)⟩, ?_⟩
        rw [hiff]
        constructor
        · rintro ⟨hc, hb⟩; exact ⟨hc, Body.esc hy hb⟩
        · rintro ⟨hc, hb⟩
          obtain ⟨c', rest'', heq', _, hb'⟩ := body_backslash hb
          cases heq'
          exact ⟨hc, hb'⟩
      · rw [qb_lone hy] at hs
        obtain ⟨⟨hle, heq⟩, hiff⟩ := ih (y :: rest') (by simp <;> omega) (t + 1) false n rest clean hs
        have hn : n - t = (n - (t + 1)) + 1 := by omega
        rw [hn]
        simp only [List.take_succ_cons, List.cons_append]
        refine ⟨⟨by omega, congrArg _ heq⟩, ?_⟩
        rw [hiff]
        constructor
        · rintro ⟨hc, _⟩; cases hc
        · rintro ⟨_, hb⟩
          exfalso
          obtain ⟨c', rest'', heq', he, _⟩ := body_backslash hb
          cases hk : n - (t + 1) with
          | zero => rw [hk] at heq'; simp at heq'
          | succ k =>
            rw [hk, List.take_succ_cons] at heq'
            cases heq'
            exact hy he
    · by_cases hxq : x = q
      · rw [qb_quote hx hxq] at hs
        cases hs
        subst hxq
        simp only [Nat.sub_self, List.take_zero, List.nil_append]
        exact ⟨⟨Nat.le_refl _, by simp⟩, fun h => ⟨h, Body.nil⟩, fun h => h.1⟩
      · by_cases hlf : x = 0x0A
        · rw [qb_lf hx hxq hlf] at hs; cases hs
        · rw [qb_step hx hxq hlf] at hs
          obtain ⟨⟨hle, heq⟩, hiff⟩ :=
            ih (y :: rest') (by simp <;> omega) (t + 1) (c && plain q x) n rest clean hs
          have hn : n - t = (n - (t + 1)) + 1 := by omega
          rw [hn]
          simp only [List.take_succ_cons, List.cons_append]
          refine ⟨⟨by omega, congrArg _ heq⟩, ?_⟩
          rw [hiff]
          constructor
          · rintro ⟨hc, hb⟩
            simp only [Bool.and_eq_true] at hc
            exact ⟨hc.1, Body.plain hc.2 hb⟩
          · rintro ⟨hc, hb⟩
            obtain ⟨hp, hb⟩ := body_cons hx hb
            exact ⟨by simp [hc, hp], hb⟩

/-- The statement the oracle test makes, as a theorem: a body the repaired
scanner returns clean is in the BNF class. -/
theorem repaired_scanner_sound (q : Byte) (hq : q ≠ 0x5C) (s : List Byte) (n : Nat)
    (rest : List Byte) : quotedBody' s q 0 true = .ok n rest true → Body q (s.take n) := by
  intro h
  have := ((quotedBody'_spec q hq s 0 true n rest true h).2).mp rfl
  simpa using this.2

/-- And the diagnostic is never spurious: a body reported is not in the class. -/
theorem repaired_scanner_precise (q : Byte) (hq : q ≠ 0x5C) (s : List Byte) (n : Nat)
    (rest : List Byte) : quotedBody' s q 0 true = .ok n rest false → ¬ Body q (s.take n) := by
  intro h hb
  have := ((quotedBody'_spec q hq s 0 true n rest false h).2).mpr ⟨rfl, by simpa using hb⟩
  cases this

/-- The repair changes nothing about where a token ends: on every input the two
scanners agree on how many bytes were taken, on what follows, and on whether
the quote was closed. -/
theorem quotedBody'_agrees (q : Byte) (hq : q ≠ 0x5C) :
    ∀ (s : List Byte) (t : Nat) (c : Bool),
      (∀ n rest clean, quotedBody' s q t c = .ok n rest clean → quotedBody s q t = .ok n rest) ∧
      (∀ n rest, quotedBody' s q t c = .unterminated n rest → quotedBody s q t = .unterminated n rest) := by
  apply list_strong_induction
  intro s ih t c
  match s with
  | [] => simp [qb_nil, quotedBody]
  | [x] =>
    by_cases hx : x = 0x5C
    · subst hx
      constructor
      · intro n r cl h; rw [qb_lone_end] at h; cases h
      · intro n r h
        rw [qb_lone_end] at h; cases h
        have : (0x5C : Byte) ≠ q := fun h => hq h.symm
        simp [quotedBody, this]
    · by_cases hxq : x = q
      · subst hxq
        constructor
        · intro n r cl h; rw [qb_quote hx rfl] at h; cases h; simp [quotedBody]
        · intro n r h; rw [qb_quote hx rfl] at h; cases h
      · by_cases hlf : x = 0x0A
        · constructor
          · intro n r cl h; rw [qb_lf hx hxq hlf] at h; cases h
          · intro n r h; rw [qb_lf hx hxq hlf] at h; cases h; subst hlf; simp [quotedBody, hxq]
        · constructor
          · intro n r cl h; rw [qb_step hx hxq hlf, qb_nil] at h; cases h
          · intro n r h; rw [qb_step hx hxq hlf, qb_nil] at h; cases h; simp [quotedBody, hxq, hlf]
  | x :: y :: rest' =>
    by_cases hx : x = 0x5C
    · subst hx
      by_cases hy : y = 0x5C ∨ y = q
      · have unfold : quotedBody (0x5C :: y :: rest') q t = quotedBody rest' q (t + 2) := by
          simp [quotedBody, hy]
        rw [unfold]
        constructor
        · intro n r cl h; rw [qb_esc hy] at h; exact (ih rest' (by simp <;> omega) (t + 2) c).1 n r cl h
        · intro n r h; rw [qb_esc hy] at h; exact (ih rest' (by simp <;> omega) (t + 2) c).2 n r h
      · have unfold : quotedBody (0x5C :: y :: rest') q t = quotedBody (y :: rest') q (t + 1) := by
          simp [quotedBody, hy]
        rw [unfold]
        constructor
        · intro n r cl h; rw [qb_lone hy] at h
          exact (ih (y :: rest') (by simp <;> omega) (t + 1) false).1 n r cl h
        · intro n r h; rw [qb_lone hy] at h
          exact (ih (y :: rest') (by simp <;> omega) (t + 1) false).2 n r h
    · by_cases hxq : x = q
      · subst hxq
        constructor
        · intro n r cl h; rw [qb_quote hx rfl] at h; cases h; simp [quotedBody, hx]
        · intro n r h; rw [qb_quote hx rfl] at h; cases h
      · by_cases hlf : x = 0x0A
        · constructor
          · intro n r cl h; rw [qb_lf hx hxq hlf] at h; cases h
          · intro n r h; rw [qb_lf hx hxq hlf] at h; cases h; subst hlf; simp [quotedBody, hxq]
        · have unfold : quotedBody (x :: y :: rest') q t = quotedBody (y :: rest') q (t + 1) := by
            simp [quotedBody, hx, hxq, hlf]
          rw [unfold]
          constructor
          · intro n r cl h; rw [qb_step hx hxq hlf] at h
            exact (ih (y :: rest') (by simp <;> omega) (t + 1) (c && plain q x)).1 n r cl h
          · intro n r h; rw [qb_step hx hxq hlf] at h
            exact (ih (y :: rest') (by simp <;> omega) (t + 1) (c && plain q x)).2 n r h

end Tptp.Lexer.Quoted
