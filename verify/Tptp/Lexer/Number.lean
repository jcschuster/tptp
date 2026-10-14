/-!
# `Tptp.Lexer.number/1`, modelled byte for byte

The lexer scans a number from its leading digit (or sign and digit) and
classifies it as an `<integer>`, a `<rational>` or a `<real>`:

```elixir
defp number(<<s, rest::binary>>) when is_sign(s) do
  {length, category, tail} = unsigned(rest)
  {length + 1, category, tail}
end
defp number(bin), do: unsigned(bin)

defp unsigned(bin) do
  {whole, after_whole} = digits(bin, 0)
  case after_whole do
    <<?/, c, _::binary>> when is_digit(c) ->
      <<?/, rest::binary>> = after_whole
      {denominator, tail} = digits(rest, 0)
      {whole + 1 + denominator, :rational, tail}
    <<?., c, _::binary>> when is_digit(c) ->
      <<?., rest::binary>> = after_whole
      {fraction, after_fraction} = digits(rest, 0)
      {exponent, tail} = exponent(after_fraction)
      {whole + 1 + fraction + exponent, :real, tail}
    _no_fraction ->
      case exponent(after_whole) do
        {0, tail} -> {whole, :integer, tail}
        {exponent, tail} -> {whole + exponent, :real, tail}
      end
  end
end

defp exponent(<<e, s, c, _::binary>> = bin) when is_exponent(e) and is_sign(s) and is_digit(c) do
  <<_e, _s, rest::binary>> = bin
  {length, tail} = digits(rest, 0)
  {length + 2, tail}
end
defp exponent(<<e, c, _::binary>> = bin) when is_exponent(e) and is_digit(c) do
  <<_e, rest::binary>> = bin
  {length, tail} = digits(rest, 0)
  {length + 1, tail}
end
defp exponent(bin), do: {0, bin}

defp digits(<<c, rest::binary>>, taken) when is_digit(c), do: digits(rest, taken + 1)
defp digits(rest, taken), do: {taken, rest}
```

and then reports a redundant leading zero (`TPTP0110`) and a denominator
beginning with zero (`TPTP0111`), these being the two ways such a token can
fail the BNF:

```
<real>               ::- (<signed_real>|<unsigned_real>)
<signed_real>        ::: <sign><unsigned_real>
<unsigned_real>      ::: (<decimal_fraction>|<decimal_exponent>)
<decimal_exponent>   ::: (<integer_digits>|<decimal_fraction>)<exponent><exp_integer>
<decimal_fraction>   ::: <unsigned_integer><dot><integer_digits>
<exp_integer>        ::: (<signed_exp_integer>|<integer_digits>)
<signed_exp_integer> ::: <sign><integer_digits>
<rational>           ::- (<signed_rational>|<unsigned_rational>)
<signed_rational>    ::: <sign><unsigned_rational>
<unsigned_rational>  ::: <unsigned_integer><slash><positive_integer>
<integer>            ::- (<signed_integer>|<unsigned_integer>)
<signed_integer>     ::: <sign><unsigned_integer>
<unsigned_integer>   ::: (<zero_numeric>|<positive_integer>)
<positive_integer>   ::: <non_zero_numeric><numeric>*
<integer_digits>     ::: <numeric><numeric>*
```

The BNF rules are transcribed here a second time, independently of the
scanner, as recognisers over a whole token. The main theorem says that the
token the scanner cuts is in its category's language exactly when the scanner
raises no diagnostic on it — that is, that the two diagnostics are sound and
complete for the BNF. Writing that down is what showed the shipped rule to be
too eager in one place: `<decimal_exponent>` begins with `<integer_digits>`,
which admits a leading zero, so `007e1` is a `<real>` the lexer used to report.
The repaired rule exempts the exponent-only form, and the theorem holds of it.
-/

namespace Tptp.Lexer.Number

abbrev Byte := UInt8

/-! ## Character classes, on the byte's value -/

def isDigit (c : Byte) : Bool := 48 ≤ c.toNat && c.toNat ≤ 57
def isNonZero (c : Byte) : Bool := 49 ≤ c.toNat && c.toNat ≤ 57
def isZero (c : Byte) : Bool := c.toNat = 48
def isSign (c : Byte) : Bool := c.toNat = 43 || c.toNat = 45
def isExp (c : Byte) : Bool := c.toNat = 69 || c.toNat = 101
def isSlash (c : Byte) : Bool := c.toNat = 47
def isDot (c : Byte) : Bool := c.toNat = 46

theorem digit_not_sign {c : Byte} (h : isDigit c = true) : isSign c = false := by
  simp [isDigit, isSign] at *; omega
theorem digit_not_exp {c : Byte} (h : isDigit c = true) : isExp c = false := by
  simp [isDigit, isExp] at *; omega
theorem digit_not_slash {c : Byte} (h : isDigit c = true) : isSlash c = false := by
  simp [isDigit, isSlash] at *; omega
theorem digit_not_dot {c : Byte} (h : isDigit c = true) : isDot c = false := by
  simp [isDigit, isDot] at *; omega
theorem sign_not_exp {c : Byte} (h : isSign c = true) : isExp c = false := by
  simp [isSign, isExp] at *; omega
theorem sign_not_dot {c : Byte} (h : isSign c = true) : isDot c = false := by
  simp [isSign, isDot] at *; omega
theorem slash_not_exp {c : Byte} (h : isSlash c = true) : isExp c = false := by
  simp [isSlash, isExp] at *; omega
theorem dot_not_exp {c : Byte} (h : isDot c = true) : isExp c = false := by
  simp [isDot, isExp] at *; omega
theorem slash_not_digit {c : Byte} (h : isSlash c = true) : isDigit c = false := by
  simp [isSlash, isDigit] at *; omega
theorem dot_not_digit {c : Byte} (h : isDot c = true) : isDigit c = false := by
  simp [isDot, isDigit] at *; omega
theorem exp_not_dot {c : Byte} (h : isExp c = true) : isDot c = false := by
  simp [isExp, isDot] at *; omega
theorem digit_zero_or_nonzero {c : Byte} (h : isDigit c = true) :
    isNonZero c = (!isZero c) := by
  simp only [isDigit, isNonZero, isZero, Bool.and_eq_true, decide_eq_true_eq] at *
  by_cases hz : c.toNat = 48
  · simp [hz]
  · simp [hz]; omega

/-! ## The scanner -/

inductive Category where
  | integer | rational | real
deriving DecidableEq, Repr

/-- `digits/2` -/
def digits : List Byte → Nat → Nat × List Byte
  | c :: rest, taken => if isDigit c then digits rest (taken + 1) else (taken, c :: rest)
  | [], taken => (taken, [])

/-- `exponent/1` -/
def exponent : List Byte → Nat × List Byte
  | e :: s :: c :: rest =>
    if isExp e && isSign s && isDigit c then
      ((digits (c :: rest) 0).1 + 2, (digits (c :: rest) 0).2)
    else if isExp e && isDigit s then
      ((digits (s :: c :: rest) 0).1 + 1, (digits (s :: c :: rest) 0).2)
    else (0, e :: s :: c :: rest)
  | [e, c] =>
    if isExp e && isDigit c then ((digits [c] 0).1 + 1, (digits [c] 0).2) else (0, [e, c])
  | other => (0, other)

/-- The `_no_fraction` branch of `unsigned/1`. -/
def noFraction (whole : Nat) (after : List Byte) : Nat × Category × List Byte :=
  if (exponent after).1 = 0 then (whole, .integer, (exponent after).2)
  else (whole + (exponent after).1, .real, (exponent after).2)

/-- `unsigned/1` -/
def unsigned (bin : List Byte) : Nat × Category × List Byte :=
  match (digits bin 0).2 with
  | a :: c :: rest =>
    if isSlash a && isDigit c then
      ((digits bin 0).1 + 1 + (digits (c :: rest) 0).1, .rational, (digits (c :: rest) 0).2)
    else if isDot a && isDigit c then
      ((digits bin 0).1 + 1 + (digits (c :: rest) 0).1 + (exponent (digits (c :: rest) 0).2).1,
        .real, (exponent (digits (c :: rest) 0).2).2)
    else noFraction (digits bin 0).1 (a :: c :: rest)
  | after => noFraction (digits bin 0).1 after

/-- `number/1` -/
def number : List Byte → Nat × Category × List Byte
  | c :: rest =>
    if isSign c then ((unsigned rest).1 + 1, (unsigned rest).2.1, (unsigned rest).2.2)
    else unsigned (c :: rest)
  | [] => unsigned []

/-- The scan loop calls `number/1` only here. -/
def startsNumber (s : List Byte) : Prop :=
  (∃ c r, s = c :: r ∧ isDigit c = true) ∨ (∃ c d r, s = c :: d :: r ∧ isSign c = true ∧ isDigit d = true)

/-! ## The BNF, transcribed as recognisers over a whole token -/

def allDigits (l : List Byte) : Bool := l.all isDigit

/-- `<unsigned_integer>` -/
def unsignedInteger : List Byte → Bool
  | [c] => isDigit c
  | c :: rest => isNonZero c && allDigits rest
  | [] => false

/-- `<positive_integer>` -/
def positiveInteger : List Byte → Bool
  | c :: rest => isNonZero c && allDigits rest
  | [] => false

/-- `<integer_digits>` -/
def integerDigits (l : List Byte) : Bool := !l.isEmpty && allDigits l

/-- One optional `<sign>`. -/
def stripSign : List Byte → List Byte
  | c :: rest => if isSign c then rest else c :: rest
  | [] => []

/-- Divide a token at the first byte satisfying `p`. -/
def splitFirst (p : Byte → Bool) : List Byte → Option (List Byte × List Byte)
  | [] => none
  | c :: rest =>
    if p c then some ([], rest)
    else match splitFirst p rest with
      | some (l, r) => some (c :: l, r)
      | none => none

/-- `<decimal_fraction>` -/
def decimalFraction (m : List Byte) : Bool :=
  match splitFirst isDot m with
  | some (w, f) => unsignedInteger w && integerDigits f
  | none => false

/-- `<exp_integer>` -/
def expInteger (e : List Byte) : Bool := integerDigits (stripSign e)

/-- `<integer>` -/
def isInteger (t : List Byte) : Bool := unsignedInteger (stripSign t)

/-- `<rational>` -/
def isRational (t : List Byte) : Bool :=
  match splitFirst isSlash (stripSign t) with
  | some (w, d) => unsignedInteger w && positiveInteger d
  | none => false

/-- `<real>` -/
def isReal (t : List Byte) : Bool :=
  match splitFirst isExp (stripSign t) with
  | some (m, e) => (integerDigits m || decimalFraction m) && expInteger e
  | none => decimalFraction (stripSign t)

/-! ## The diagnostics -/

/-- `padded/3`: a zero followed by a digit at the front of the unsigned text. -/
def leadingZero (t : List Byte) : Bool :=
  match stripSign t with
  | z :: c :: _ => isZero z && isDigit c
  | _ => false

/-- `denominator/4`: a zero right after the first slash. -/
def zeroDenominator (t : List Byte) : Bool :=
  match splitFirst isSlash (stripSign t) with
  | some (_, z :: _) => isZero z
  | _ => false

/-- The shipped rule: `TPTP0110` whenever `leadingZero` holds. -/
def warnsLeadingZero₀ (t : List Byte) (_ : Category) : Bool := leadingZero t

/-- The repaired rule: a `<real>` in the exponent-only form is exempt, since
`<decimal_exponent>` begins with `<integer_digits>`. -/
def warnsLeadingZero (t : List Byte) : Category → Bool
  | .real => leadingZero t && (stripSign t).any isDot
  | _ => leadingZero t

/-! ## `007e1` -/

/-- A `<real>` the shipped rule reported: the scanner reads it whole and the
BNF admits it, yet `leadingZero` holds. -/
theorem shipped_rule_spurious :
    number [48, 48, 55, 101, 49] = (5, .real, []) ∧
      isReal [48, 48, 55, 101, 49] = true ∧
      warnsLeadingZero₀ [48, 48, 55, 101, 49] .real = true ∧
      warnsLeadingZero [48, 48, 55, 101, 49] .real = false := by
  decide

/-- The same text with a point is not a `<real>`, and both rules report it. -/
theorem fraction_leading_zero_reported :
    number [48, 48, 55, 46, 53] = (5, .real, []) ∧
      isReal [48, 48, 55, 46, 53] = false ∧
      warnsLeadingZero [48, 48, 55, 46, 53] .real = true := by
  decide

/-! ## Shape lemmas for the scanner -/

/-- `rest` does not begin with a digit. -/
def noDigitHead (rest : List Byte) : Prop := ∀ c r, rest = c :: r → isDigit c = false

theorem allDigits_nil : allDigits [] = true := rfl
theorem allDigits_cons {c : Byte} {l : List Byte} : allDigits (c :: l) = (isDigit c && allDigits l) := by
  simp [allDigits, List.all_cons]
theorem allDigits_append {a b : List Byte} : allDigits (a ++ b) = (allDigits a && allDigits b) := by
  simp [allDigits, List.all_append]

theorem digits_spec : ∀ (l : List Byte) (t : Nat), ∃ D rest,
    digits l t = (t + D.length, rest) ∧ l = D ++ rest ∧ allDigits D = true ∧ noDigitHead rest := by
  intro l
  induction l with
  | nil => intro t; exact ⟨[], [], by simp [digits], rfl, rfl, fun c r h => by cases h⟩
  | cons c rest ih =>
    intro t
    by_cases hc : isDigit c = true
    · obtain ⟨D, r, hd, hl, hall, hno⟩ := ih (t + 1)
      refine ⟨c :: D, r, ?_, by simp [hl], by simp [allDigits_cons, hc, hall], hno⟩
      simp only [digits, hc, ↓reduceIte, hd, List.length_cons]
      congr 1; omega
    · refine ⟨[], c :: rest, by simp [digits, hc], rfl, rfl, ?_⟩
      intro c' r h
      cases h
      simpa using hc

/-- An optional sign, as a list of length at most one. -/
def SignOpt (S : List Byte) : Prop := S = [] ∨ ∃ s, S = [s] ∧ isSign s = true

theorem exponent_spec (l : List Byte) :
    exponent l = (0, l) ∨
    ∃ e S X rest, isExp e = true ∧ SignOpt S ∧ X ≠ [] ∧ allDigits X = true ∧
      l = e :: (S ++ X ++ rest) ∧ exponent l = (1 + S.length + X.length, rest) ∧ noDigitHead rest := by
  match l with
  | e :: s :: c :: rest =>
    simp only [exponent]
    split
    · rename_i h1
      simp only [Bool.and_eq_true] at h1
      obtain ⟨D, r, hd, hl, hall, hno⟩ := digits_spec (c :: rest) 0
      have hD : D ≠ [] := by
        intro hD; subst hD
        simp at hl
        exact absurd h1.2 (by rw [hno c rest hl.symm]; decide)
      right
      refine ⟨e, [s], D, r, h1.1.1, Or.inr ⟨s, rfl, h1.1.2⟩, hD, hall, ?_, ?_, hno⟩
      · simp [hl]
      · rw [hd]; simp only [List.length_cons, List.length_nil]; congr 1; omega
    · split
      · rename_i h1 h2
        simp only [Bool.and_eq_true] at h2
        obtain ⟨D, r, hd, hl, hall, hno⟩ := digits_spec (s :: c :: rest) 0
        have hD : D ≠ [] := by
          intro hD; subst hD
          simp at hl
          exact absurd h2.2 (by rw [hno s (c :: rest) hl.symm]; decide)
        right
        refine ⟨e, [], D, r, h2.1, Or.inl rfl, hD, hall, ?_, ?_, hno⟩
        · simp [hl]
        · rw [hd]; simp only [List.length_nil]; congr 1; omega
      · left; rfl
  | [e, c] =>
    simp only [exponent]
    split
    · rename_i h1
      simp only [Bool.and_eq_true] at h1
      obtain ⟨D, r, hd, hl, hall, hno⟩ := digits_spec [c] 0
      have hD : D ≠ [] := by
        intro hD; subst hD
        simp at hl
        exact absurd h1.2 (by rw [hno c [] hl.symm]; decide)
      right
      refine ⟨e, [], D, r, h1.1, Or.inl rfl, hD, hall, ?_, ?_, hno⟩
      · simp [hl]
      · rw [hd]; simp only [List.length_nil]; congr 1; omega
    · left; rfl
  | [] => left; rfl
  | [e] => left; rfl

/-- What may follow the mantissa: nothing, or an exponent part. -/
def ExpPart (E : List Byte) : Prop :=
  E = [] ∨ ∃ e S X, isExp e = true ∧ SignOpt S ∧ X ≠ [] ∧ allDigits X = true ∧ E = e :: (S ++ X)

theorem noFraction_spec (whole : Nat) (after : List Byte) :
    (noFraction whole after = (whole, .integer, after)) ∨
    ∃ E rest, ExpPart E ∧ E ≠ [] ∧ after = E ++ rest ∧
      noFraction whole after = (whole + E.length, .real, rest) ∧ noDigitHead rest := by
  rcases exponent_spec after with h | ⟨e, S, X, rest, he, hS, hX, hall, hl, hexp, hno⟩
  · left; simp [noFraction, h]
  · right
    refine ⟨e :: (S ++ X), rest, Or.inr ⟨e, S, X, he, hS, hX, hall, rfl⟩, by simp, by simp [hl], ?_, hno⟩
    have hpos : (exponent after).1 ≠ 0 := by rw [hexp]; simp
    unfold noFraction
    rw [if_neg hpos, hexp]
    refine Prod.ext ?_ rfl
    dsimp only
    simp only [List.length_cons, List.length_append]
    omega

theorem unsigned_spec (bin : List Byte) (hbin : ∃ c r, bin = c :: r ∧ isDigit c = true) :
    ∃ W, W ≠ [] ∧ allDigits W = true ∧ (
      (∃ a D rest, isSlash a = true ∧ D ≠ [] ∧ allDigits D = true ∧ bin = W ++ a :: (D ++ rest) ∧
        unsigned bin = (W.length + 1 + D.length, .rational, rest) ∧ noDigitHead rest) ∨
      (∃ a F E rest, isDot a = true ∧ F ≠ [] ∧ allDigits F = true ∧ ExpPart E ∧
        bin = W ++ a :: (F ++ E ++ rest) ∧
        unsigned bin = (W.length + 1 + F.length + E.length, .real, rest) ∧ noDigitHead rest) ∨
      (∃ E rest, ExpPart E ∧ E ≠ [] ∧ bin = W ++ E ++ rest ∧
        unsigned bin = (W.length + E.length, .real, rest) ∧ noDigitHead rest) ∨
      (∃ rest, bin = W ++ rest ∧ unsigned bin = (W.length, .integer, rest) ∧ noDigitHead rest)) := by
  obtain ⟨W, after, hd, hl, hall, hno⟩ := digits_spec bin 0
  have hW : W ≠ [] := by
    intro hW; subst hW
    obtain ⟨c, r, hb, hc⟩ := hbin
    simp at hl; subst hl
    exact absurd hc (by rw [hno c r hb]; decide)
  refine ⟨W, hW, hall, ?_⟩
  simp only [Nat.zero_add] at hd
  match hafter : after with
  | a :: c :: rest =>
    subst hafter
    simp only [unsigned, hd]
    split
    · rename_i h1
      simp only [Bool.and_eq_true] at h1
      obtain ⟨D, r, hd2, hl2, hall2, hno2⟩ := digits_spec (c :: rest) 0
      have hD : D ≠ [] := by
        intro hD; subst hD
        simp at hl2
        exact absurd h1.2 (by rw [hno2 c rest hl2.symm]; decide)
      left
      refine ⟨a, D, r, h1.1, hD, hall2, by rw [hl, hl2], ?_, hno2⟩
      rw [hd2]; simp
    · split
      · rename_i h1 h2
        simp only [Bool.and_eq_true] at h2
        obtain ⟨F, afterF, hd2, hl2, hall2, hno2⟩ := digits_spec (c :: rest) 0
        have hF : F ≠ [] := by
          intro hF; subst hF
          simp at hl2
          exact absurd h2.2 (by rw [hno2 c rest hl2.symm]; decide)
        right; left
        rcases exponent_spec afterF with h3 | ⟨e, S, X, r, he, hS, hX, hallX, hl3, hexp, hno3⟩
        · refine ⟨a, F, [], afterF, h2.1, hF, hall2, Or.inl rfl, by simp [hl, hl2], ?_, hno2⟩
          rw [hd2]; simp only [Nat.zero_add, h3]; simp
        · refine ⟨a, F, e :: (S ++ X), r, h2.1, hF, hall2,
            Or.inr ⟨e, S, X, he, hS, hX, hallX, rfl⟩, ?_, ?_, hno3⟩
          · rw [hl, hl2, hl3]; simp
          · rw [hd2]; simp only [Nat.zero_add, hexp, List.length_cons, List.length_append]
            congr 2; omega
      · rename_i h1 h2
        rcases noFraction_spec W.length (a :: c :: rest) with h3 | ⟨E, r, hE, hEne, hl3, hnf, hno3⟩
        · right; right; right
          exact ⟨a :: c :: rest, hl, h3, hno⟩
        · right; right; left
          exact ⟨E, r, hE, hEne, by rw [hl, hl3, List.append_assoc], hnf, hno3⟩
  | [] =>
    subst hafter
    simp only [unsigned, hd]
    right; right; right
    refine ⟨[], by simpa using hl, ?_, hno⟩
    simp [noFraction, exponent]
  | [a] =>
    subst hafter
    simp only [unsigned, hd]
    right; right; right
    refine ⟨[a], hl, ?_, hno⟩
    simp [noFraction, exponent]

/-! ## Recognisers on the shapes the scanner cuts -/

theorem all_not_of_allDigits {W : List Byte} (h : allDigits W = true) {p : Byte → Bool}
    (hp : ∀ c, isDigit c = true → p c = false) : ∀ c ∈ W, p c = false := by
  intro c hc
  simp only [allDigits, List.all_eq_true] at h
  exact hp c (h c hc)

theorem splitFirst_none {p : Byte → Bool} : ∀ {l : List Byte}, (∀ c ∈ l, p c = false) →
    splitFirst p l = none := by
  intro l
  induction l with
  | nil => intro _; rfl
  | cons c rest ih =>
    intro h
    have hc : p c = false := h c (by simp)
    simp only [splitFirst, hc, Bool.false_eq_true, ↓reduceIte]
    rw [ih (fun d hd => h d (by simp [hd]))]

theorem splitFirst_append {p : Byte → Bool} : ∀ {A : List Byte} {a : Byte} {B : List Byte},
    (∀ c ∈ A, p c = false) → p a = true → splitFirst p (A ++ a :: B) = some (A, B) := by
  intro A
  induction A with
  | nil => intro a B _ ha; simp [splitFirst, ha]
  | cons c rest ih =>
    intro a B h ha
    have hc : p c = false := h c (by simp)
    simp only [List.cons_append, splitFirst, hc, Bool.false_eq_true, ↓reduceIte]
    rw [ih (fun d hd => h d (by simp [hd])) ha]

theorem stripSign_digit {W : List Byte} (hW : W ≠ []) (hall : allDigits W = true) :
    stripSign W = W := by
  cases W with
  | nil => exact absurd rfl hW
  | cons c rest =>
    simp only [allDigits_cons, Bool.and_eq_true] at hall
    simp [stripSign, digit_not_sign hall.1]

theorem stripSign_append_digit {W T : List Byte} (hW : W ≠ []) (hall : allDigits W = true) :
    stripSign (W ++ T) = W ++ T := by
  cases W with
  | nil => exact absurd rfl hW
  | cons c rest =>
    simp only [allDigits_cons, Bool.and_eq_true] at hall
    simp [stripSign, digit_not_sign hall.1]

theorem unsignedInteger_iff {W : List Byte} (hW : W ≠ []) (hall : allDigits W = true) :
    unsignedInteger W = (!leadingZero W) := by
  rw [leadingZero, stripSign_digit hW hall]
  match W with
  | [] => exact absurd rfl hW
  | [c] =>
    simp only [allDigits_cons, Bool.and_eq_true] at hall
    simp [unsignedInteger, hall.1]
  | c :: d :: rest =>
    simp only [allDigits_cons, Bool.and_eq_true] at hall
    simp only [unsignedInteger, allDigits_cons, hall.2.1, hall.2.2, Bool.and_true,
      digit_zero_or_nonzero hall.1]

theorem positiveInteger_iff {D : List Byte} (hD : D ≠ []) (hall : allDigits D = true) :
    positiveInteger D = (!(match D with | z :: _ => isZero z | [] => false)) := by
  match D with
  | [] => exact absurd rfl hD
  | z :: rest =>
    simp only [allDigits_cons, Bool.and_eq_true] at hall
    simp [positiveInteger, hall.2, digit_zero_or_nonzero hall.1]

theorem integerDigits_of {X : List Byte} (hX : X ≠ []) (hall : allDigits X = true) :
    integerDigits X = true := by
  cases X with
  | nil => exact absurd rfl hX
  | cons c rest => simp [integerDigits, hall]

theorem expInteger_of {S X : List Byte} (hS : SignOpt S) (hX : X ≠ []) (hall : allDigits X = true) :
    expInteger (S ++ X) = true := by
  rcases hS with rfl | ⟨s, rfl, hs⟩
  · simp only [List.nil_append, expInteger]
    rw [stripSign_digit hX hall]
    exact integerDigits_of hX hall
  · simp [expInteger, stripSign, hs, integerDigits_of hX hall]

theorem leadingZero_append {W T : List Byte} (hW : W ≠ []) (hall : allDigits W = true) :
    leadingZero (W ++ T) = (match W with | z :: c :: _ => isZero z && isDigit c | [z] => (match T with | c :: _ => isZero z && isDigit c | [] => false) | [] => false) := by
  rw [leadingZero, stripSign_append_digit hW hall]
  match W with
  | [] => exact absurd rfl hW
  | [z] => cases T <;> simp
  | z :: c :: rest => simp

/-- The main theorem. -/
theorem number_spec (s : List Byte) (hs : startsNumber s) :
    ∃ text cat tail, number s = (text.length, cat, tail) ∧ s = text ++ tail ∧ noDigitHead tail ∧
      (cat = .integer → (isInteger text = true ↔ leadingZero text = false)) ∧
      (cat = .rational →
        (isRational text = true ↔ (leadingZero text = false ∧ zeroDenominator text = false))) ∧
      (cat = .real → (isReal text = true ↔ warnsLeadingZero text .real = false)) := by
  -- Reduce the signed case to the unsigned one.
  suffices unsignedCase : ∀ (u : List Byte), (∃ c r, u = c :: r ∧ isDigit c = true) →
      ∃ text cat tail, unsigned u = (text.length, cat, tail) ∧ u = text ++ tail ∧ noDigitHead tail ∧
        stripSign text = text ∧
        (cat = .integer → (isInteger text = true ↔ leadingZero text = false)) ∧
        (cat = .rational →
          (isRational text = true ↔ (leadingZero text = false ∧ zeroDenominator text = false))) ∧
        (cat = .real → (isReal text = true ↔ warnsLeadingZero text .real = false)) by
    rcases hs with ⟨c, r, rfl, hc⟩ | ⟨c, d, r, rfl, hc, hd⟩
    · obtain ⟨text, cat, tail, hu, hl, hno, _, hi, hr, hre⟩ := unsignedCase (c :: r) ⟨c, r, rfl, hc⟩
      refine ⟨text, cat, tail, ?_, hl, hno, hi, hr, hre⟩
      simp only [number, digit_not_sign hc, Bool.false_eq_true, ↓reduceIte, hu]
    · obtain ⟨text, cat, tail, hu, hl, hno, hstrip', hi, hr, hre⟩ :=
        unsignedCase (d :: r) ⟨d, r, rfl, hd⟩
      -- the signed token: every recogniser and both diagnostics strip the sign first
      have hstrip : stripSign (c :: text) = text := by simp [stripSign, hc]
      have e1 : isInteger (c :: text) = isInteger text := by simp only [isInteger, hstrip, hstrip']
      have e2 : leadingZero (c :: text) = leadingZero text := by
        simp only [leadingZero, hstrip, hstrip']
      have e3 : isRational (c :: text) = isRational text := by
        simp only [isRational, hstrip, hstrip']
      have e4 : zeroDenominator (c :: text) = zeroDenominator text := by
        simp only [zeroDenominator, hstrip, hstrip']
      have e5 : isReal (c :: text) = isReal text := by simp only [isReal, hstrip, hstrip']
      have e6 : warnsLeadingZero (c :: text) .real = warnsLeadingZero text .real := by
        simp only [warnsLeadingZero, hstrip, hstrip', e2]
      refine ⟨c :: text, cat, tail, ?_, by simp [hl], hno, ?_, ?_, ?_⟩
      · simp only [number, hc, ↓reduceIte, hu, List.length_cons]
      · intro hcat; rw [e1, e2]; exact hi hcat
      · intro hcat; rw [e3, e2, e4]; exact hr hcat
      · intro hcat; rw [e5, e6]; exact hre hcat
  intro u hu
  obtain ⟨W, hW, hall, hcase⟩ := unsigned_spec u hu
  have hWdigit : ∀ c ∈ W, isDigit c = true := by
    simpa [allDigits, List.all_eq_true] using hall
  have hWnotExp : ∀ c ∈ W, isExp c = false := all_not_of_allDigits hall (fun _ => digit_not_exp)
  have hWnotSlash : ∀ c ∈ W, isSlash c = false := all_not_of_allDigits hall (fun _ => digit_not_slash)
  have hWnotDot : ∀ c ∈ W, isDot c = false := all_not_of_allDigits hall (fun _ => digit_not_dot)
  rcases hcase with ⟨a, D, rest, ha, hD, hallD, hl, hu', hno⟩ |
      ⟨a, F, E, rest, ha, hF, hallF, hE, hl, hu', hno⟩ |
      ⟨E, rest, hE, hEne, hl, hu', hno⟩ | ⟨rest, hl, hu', hno⟩
  · -- rational
    have hstrip := stripSign_append_digit (T := a :: D) hW hall
    refine ⟨W ++ a :: D, .rational, rest, by rw [hu']; simp <;> omega, by simp [hl], hno,
      hstrip, (fun h => nomatch h), fun _ => ?_, (fun h => nomatch h)⟩
    simp only [isRational, zeroDenominator, hstrip, splitFirst_append hWnotSlash ha]
    rw [unsignedInteger_iff hW hall, positiveInteger_iff hD hallD, leadingZero_append hW hall]
    cases D with
    | nil => exact absurd rfl hD
    | cons z D' =>
      match W with
      | [] => exact absurd rfl hW
      | [w] =>
        cases hz : isZero z <;>
          simp [leadingZero, stripSign, digit_not_sign (hWdigit w (by simp)), slash_not_digit ha, hz]
      | w :: w' :: W' =>
        cases hw : isZero w <;> cases hz : isZero z <;>
          simp [leadingZero, stripSign, digit_not_sign (hWdigit w (by simp)),
            hWdigit w' (by simp), hw, hz]
  · -- real with a fraction
    have hstrip := stripSign_append_digit (T := a :: (F ++ E)) hW hall
    refine ⟨W ++ a :: (F ++ E), .real, rest, by rw [hu']; simp <;> omega, by simp [hl], hno,
      hstrip, (fun h => nomatch h), (fun h => nomatch h), fun _ => ?_⟩
    have hFnotExp : ∀ c ∈ F, isExp c = false := all_not_of_allDigits hallF (fun _ => digit_not_exp)
    have hanotExp : isExp a = false := dot_not_exp ha
    have hdot : (W ++ a :: (F ++ E)).any isDot = true := by
      simp [List.any_append, List.any_cons, ha]
    have hfrac : decimalFraction (W ++ a :: F) = (!leadingZero W) := by
      simp only [decimalFraction, splitFirst_append hWnotDot ha, integerDigits_of hF hallF,
        Bool.and_true]
      exact unsignedInteger_iff hW hall
    have hlz : leadingZero (W ++ a :: (F ++ E)) = leadingZero W := by
      rw [leadingZero_append hW hall]
      match W with
      | [] => exact absurd rfl hW
      | [w] => simp [leadingZero, stripSign, digit_not_sign (hWdigit w (by simp)), dot_not_digit ha]
      | w :: w' :: W' => simp [leadingZero, stripSign, digit_not_sign (hWdigit w (by simp))]
    simp only [isReal, warnsLeadingZero, hstrip, hdot, Bool.and_true]
    rcases hE with rfl | ⟨e, S, X, he, hS, hX, hallX, rfl⟩
    · simp only [List.append_nil] at hlz ⊢
      rw [splitFirst_none (fun c hc => by
        simp only [List.mem_append, List.mem_cons] at hc
        rcases hc with hc | rfl | hc
        · exact hWnotExp c hc
        · exact hanotExp
        · exact hFnotExp c hc)]
      simp only [hfrac, hlz]
      cases leadingZero W <;> simp
    · have hsplit : splitFirst isExp (W ++ a :: (F ++ e :: (S ++ X))) = some (W ++ a :: F, S ++ X) := by
        have := splitFirst_append (p := isExp) (A := W ++ a :: F) (a := e) (B := S ++ X)
          (fun c hc => by
            simp only [List.mem_append, List.mem_cons] at hc
            rcases hc with hc | rfl | hc
            · exact hWnotExp c hc
            · exact hanotExp
            · exact hFnotExp c hc) he
        simpa using this
      have hint : integerDigits (W ++ a :: F) = false := by
        simp [integerDigits, allDigits_append, allDigits_cons, dot_not_digit ha]
      simp only [hsplit, hint, hfrac, expInteger_of hS hX hallX, hlz]
      cases leadingZero W <;> simp
  · -- real in the exponent-only form
    have hstrip := stripSign_append_digit (T := E) hW hall
    refine ⟨W ++ E, .real, rest, by rw [hu']; simp, by simp [hl], hno,
      hstrip, (fun h => nomatch h), (fun h => nomatch h), fun _ => ?_⟩
    rcases hE with rfl | ⟨e, S, X, he, hS, hX, hallX, rfl⟩
    · exact absurd rfl hEne
    have hXdigit : ∀ c ∈ X, isDigit c = true := by
      simpa [allDigits, List.all_eq_true] using hallX
    have hnodot : (W ++ e :: (S ++ X)).any isDot = false := by
      rw [List.any_eq_false]
      intro c hc
      simp only [List.mem_append, List.mem_cons] at hc
      rcases hc with hc | rfl | hc | hc
      · simp [hWnotDot c hc]
      · simp [exp_not_dot he]
      · rcases hS with rfl | ⟨s, rfl, hs⟩
        · simp at hc
        · simp at hc; subst hc; simp [sign_not_dot hs]
      · simp [digit_not_dot (hXdigit c hc)]
    simp only [isReal, warnsLeadingZero, hstrip, hnodot, Bool.and_false,
      splitFirst_append hWnotExp he, integerDigits_of hW hall, expInteger_of hS hX hallX]
    simp
  · -- integer
    refine ⟨W, .integer, rest, by rw [hu'], hl, hno, stripSign_digit hW hall,
      fun _ => ?_, (fun h => nomatch h), (fun h => nomatch h)⟩
    simp only [isInteger, stripSign_digit hW hall, unsignedInteger_iff hW hall]
    cases leadingZero W <;> simp

end Tptp.Lexer.Number
