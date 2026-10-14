/-!
# `Tptp.Span`: the line index and its two lookups

`Tptp.Span.line_index/1` records the byte offset at which each line starts,
`line_column/2` resolves an offset to a one-based line and column by binary
search over that index, and `offset/3` is documented as its inverse. The
Elixir, with the tuple read as a list here and `elem/2` as `List.getD`:

```elixir
def line_index(source) do
  starts = Enum.map(:binary.matches(source, "\n"), fn {offset, _length} -> offset + 1 end)
  List.to_tuple([0 | starts])
end

def line_column(index, offset) do
  line = search(index, offset, 0, tuple_size(index) - 1)
  {line + 1, offset - elem(index, line) + 1}
end

def offset(index, line, column) do
  count = tuple_size(index)
  cond do
    line < 1 or line > count or column < 1 -> :error
    line < count and column > elem(index, line) - elem(index, line - 1) -> :error
    true -> {:ok, elem(index, line - 1) + column - 1}
  end
end

defp search(_index, _offset, low, high) when low >= high, do: low
defp search(index, offset, low, high) do
  middle = div(low + high + 1, 2)
  if elem(index, middle) > offset,
    do: search(index, offset, low, middle - 1),
    else: search(index, offset, middle, high)
end
```

This file proves that `line_column/2` and `offset/3` are inverse to one another
on every index `line_index/1` can build, for every offset of the source and
every position the index has. Nothing here was found to be wrong; the proofs
are the record that the arithmetic was checked rather than read.
-/

namespace Tptp.Span

/-- `line_index/1` on a byte list: `0`, then one past every line feed. -/
def lineStarts : List UInt8 → Nat → List Nat
  | [], _ => []
  | c :: rest, p => if c = 0x0A then (p + 1) :: lineStarts rest (p + 1) else lineStarts rest (p + 1)

def lineIndex (source : List UInt8) : List Nat := 0 :: lineStarts source 0

/-- `search/4`. -/
def search (index : List Nat) (offset lo hi : Nat) : Nat :=
  if lo ≥ hi then lo
  else if index.getD ((lo + hi + 1) / 2) 0 > offset then search index offset lo ((lo + hi + 1) / 2 - 1)
  else search index offset ((lo + hi + 1) / 2) hi
termination_by hi - lo
decreasing_by all_goals omega

/-- `line_column/2`. -/
def lineColumn (index : List Nat) (offset : Nat) : Nat × Nat :=
  (search index offset 0 (index.length - 1) + 1,
    offset - index.getD (search index offset 0 (index.length - 1)) 0 + 1)

/-- `offset/3`. `:error` is `none`. Lines and columns are naturals here; the
Elixir also rejects a negative one, by the same first test. -/
def offsetOf (index : List Nat) (line column : Nat) : Option Nat :=
  if line < 1 ∨ line > index.length ∨ column < 1 then none
  else if line < index.length ∧ column > index.getD line 0 - index.getD (line - 1) 0 then none
  else some (index.getD (line - 1) 0 + column - 1)

/-- What `line_index/1` guarantees of its result: it starts at `0` and is
strictly increasing. Everything below needs only this. -/
structure WellFormed (index : List Nat) : Prop where
  nonempty : 0 < index.length
  first : index.getD 0 0 = 0
  sorted : ∀ i j, i < j → j < index.length → index.getD i 0 < index.getD j 0

/-! ## `line_index/1` is well formed -/

theorem lineStarts_gt (source : List UInt8) : ∀ p x, x ∈ lineStarts source p → p < x := by
  induction source with
  | nil => intro p x h; simp [lineStarts] at h
  | cons c rest ih =>
    intro p x h
    simp only [lineStarts] at h
    split at h
    · simp only [List.mem_cons] at h
      rcases h with rfl | h
      · omega
      · have := ih (p + 1) x h; omega
    · have := ih (p + 1) x h; omega

theorem lineStarts_pairwise (source : List UInt8) : ∀ p, (lineStarts source p).Pairwise (· < ·) := by
  induction source with
  | nil => intro p; simp [lineStarts]
  | cons c rest ih =>
    intro p
    simp only [lineStarts]
    split
    · exact List.Pairwise.cons (fun x hx => by have := lineStarts_gt rest (p + 1) x hx; omega) (ih (p + 1))
    · exact ih (p + 1)

theorem pairwise_getD {l : List Nat} (h : l.Pairwise (· < ·)) :
    ∀ i j, i < j → j < l.length → l.getD i 0 < l.getD j 0 := by
  induction l with
  | nil => intro i j _ hj; simp at hj
  | cons a rest ih =>
    intro i j hij hj
    rw [List.pairwise_cons] at h
    cases i with
    | zero =>
      cases j with
      | zero => omega
      | succ j =>
        simp only [List.length_cons] at hj
        have hmem : rest.getD j 0 ∈ rest := by
          rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by omega)]
          exact List.getElem_mem _
        simp only [List.getD_cons_zero, List.getD_cons_succ]
        exact h.1 _ hmem
    | succ i =>
      cases j with
      | zero => omega
      | succ j =>
        simp only [List.length_cons] at hj
        simp only [List.getD_cons_succ]
        exact ih h.2 i j (by omega) (by omega)

theorem lineIndex_wellFormed (source : List UInt8) : WellFormed (lineIndex source) := by
  refine ⟨by simp [lineIndex], by simp [lineIndex], ?_⟩
  apply pairwise_getD
  simp only [lineIndex]
  exact List.Pairwise.cons (fun x hx => by have := lineStarts_gt source 0 x hx; omega)
    (lineStarts_pairwise source 0)

/-! ## The binary search finds the last line start at or before the offset -/

theorem WellFormed.mono {index : List Nat} (w : WellFormed index) :
    ∀ i j, i ≤ j → j < index.length → index.getD i 0 ≤ index.getD j 0 := by
  intro i j hij hj
  rcases Nat.lt_or_eq_of_le hij with h | h
  · exact Nat.le_of_lt (w.sorted i j h hj)
  · subst h; exact Nat.le_refl _

/-- The invariant the search keeps: `lo ≤ hi < size`, the line at `lo` starts
at or before `offset`, and the line after `hi`, if any, starts after it. -/
theorem search_spec (index : List Nat) (offset : Nat) :
    ∀ k lo hi, hi - lo ≤ k → lo ≤ hi → hi < index.length →
      index.getD lo 0 ≤ offset → (hi + 1 < index.length → offset < index.getD (hi + 1) 0) →
      lo ≤ search index offset lo hi ∧ search index offset lo hi ≤ hi ∧
        index.getD (search index offset lo hi) 0 ≤ offset ∧
        (search index offset lo hi + 1 < index.length →
          offset < index.getD (search index offset lo hi + 1) 0) := by
  intro k
  induction k with
  | zero =>
    intro lo hi hk hle hhi hlo hnext
    have : lo = hi := by omega
    subst this
    rw [search]; simp only [Nat.le_refl, ↓reduceIte]
    exact ⟨by simp, by simp, hlo, hnext⟩
  | succ k ih =>
    intro lo hi hk hle hhi hlo hnext
    by_cases heq : lo ≥ hi
    · have : lo = hi := by omega
      subst this
      rw [search]; simp only [Nat.le_refl, ↓reduceIte]
      exact ⟨by simp, by simp, hlo, hnext⟩
    · rw [search]
      simp only [heq, ↓reduceIte]
      by_cases hmid : index.getD ((lo + hi + 1) / 2) 0 > offset
      · simp only [hmid, ↓reduceIte]
        have := ih lo ((lo + hi + 1) / 2 - 1) (by omega) (by omega) (by omega) hlo
          (fun h => by
            have : (lo + hi + 1) / 2 - 1 + 1 = (lo + hi + 1) / 2 := by omega
            rw [this]; exact hmid)
        exact ⟨this.1, by omega, this.2.2.1, this.2.2.2⟩
      · simp only [hmid, ↓reduceIte]
        have := ih ((lo + hi + 1) / 2) hi (by omega) (by omega) hhi (by omega) hnext
        exact ⟨by omega, this.2.1, this.2.2.1, this.2.2.2⟩

/-- Among a well-formed index's positions, the one the invariant describes is
unique: it is the line the offset is on. -/
theorem position_unique {index : List Nat} (w : WellFormed index) (offset r₁ r₂ : Nat)
    (h₁ : r₁ < index.length) (h₂ : r₂ < index.length)
    (a₁ : index.getD r₁ 0 ≤ offset) (b₁ : r₁ + 1 < index.length → offset < index.getD (r₁ + 1) 0)
    (a₂ : index.getD r₂ 0 ≤ offset) (b₂ : r₂ + 1 < index.length → offset < index.getD (r₂ + 1) 0) :
    r₁ = r₂ := by
  rcases Nat.lt_trichotomy r₁ r₂ with h | h | h
  · have := w.mono (r₁ + 1) r₂ (by omega) h₂
    have := b₁ (by omega)
    omega
  · exact h
  · have := w.mono (r₂ + 1) r₁ (by omega) h₁
    have := b₂ (by omega)
    omega

/-! ## The two lookups are inverse -/

/-- `offset/3` undoes `line_column/2`: every byte offset comes back as itself.
The offset need not even be inside the source; the index does not record where
the source ends, as `offset/3`'s documentation says. -/
theorem offset_lineColumn {index : List Nat} (w : WellFormed index) (offset : Nat) :
    offsetOf index (lineColumn index offset).1 (lineColumn index offset).2 = some offset := by
  have hsize := w.nonempty
  have spec := search_spec index offset (index.length - 1) 0 (index.length - 1) (Nat.le_refl _)
    (by omega) (by omega) (by rw [w.first]; exact Nat.zero_le _) (fun h => by omega)
  obtain ⟨r, hr'⟩ : ∃ r, search index offset 0 (index.length - 1) = r := ⟨_, rfl⟩
  rw [hr'] at spec
  obtain ⟨_, hr, hle, hnext⟩ := spec
  simp only [lineColumn, hr', offsetOf]
  have h1 : ¬ (r + 1 < 1 ∨ r + 1 > index.length ∨ offset - index.getD r 0 + 1 < 1) := by omega
  rw [if_neg h1]
  have h2 : ¬ (r + 1 < index.length ∧
      offset - index.getD r 0 + 1 > index.getD (r + 1) 0 - index.getD (r + 1 - 1) 0) := by
    intro ⟨hlt, hgt⟩
    have := hnext hlt
    simp only [Nat.add_sub_cancel] at hgt
    omega
  rw [if_neg h2]
  simp only [Nat.add_sub_cancel]
  congr 1
  omega

/-- `line_column/2` undoes `offset/3`: every position `offset/3` accepts comes
back as the same line and column. -/
theorem lineColumn_offset {index : List Nat} (w : WellFormed index) (line column o : Nat)
    (h : offsetOf index line column = some o) : lineColumn index o = (line, column) := by
  have hsize := w.nonempty
  unfold offsetOf at h
  by_cases h1 : line < 1 ∨ line > index.length ∨ column < 1
  · rw [if_pos h1] at h; cases h
  rw [if_neg h1] at h
  by_cases h2 : line < index.length ∧ column > index.getD line 0 - index.getD (line - 1) 0
  · rw [if_pos h2] at h; cases h
  rw [if_neg h2] at h
  have ho : index.getD (line - 1) 0 + column - 1 = o := Option.some.inj h
  have a₁ : index.getD (line - 1) 0 ≤ o := by omega
  have b₁ : line - 1 + 1 < index.length → o < index.getD (line - 1 + 1) 0 := by
    intro hlt
    have e : line - 1 + 1 = line := by omega
    rw [e] at hlt ⊢
    have hmono := w.sorted (line - 1) line (by omega) hlt
    have : ¬ (column > index.getD line 0 - index.getD (line - 1) 0) := fun hc => h2 ⟨hlt, hc⟩
    omega
  have spec := search_spec index o (index.length - 1) 0 (index.length - 1) (Nat.le_refl _)
    (by omega) (by omega) (by rw [w.first]; exact Nat.zero_le _) (fun h => by omega)
  obtain ⟨r, hr'⟩ : ∃ r, search index o 0 (index.length - 1) = r := ⟨_, rfl⟩
  rw [hr'] at spec
  obtain ⟨_, hr, a₂, b₂⟩ := spec
  have hru := position_unique w o r (line - 1) (by omega) (by omega) a₂ b₂ a₁ b₁
  subst hru
  simp only [lineColumn, hr']
  refine Prod.ext ?_ ?_
  · dsimp only; omega
  · dsimp only; omega

end Tptp.Span
