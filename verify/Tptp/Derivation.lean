/-!
# `Tptp.Derivation.cone/2` keeps every edge it needs

`cone/2` retains a node and its ancestors:

```elixir
def cone(%__MODULE__{} = derivation, name) when is_binary(name) do
  retained = retained(derivation, name)
  nodes = Map.new(retained, &{&1, derivation.nodes[&1]})
  ...
end

defp retained(derivation, name) do
  if Map.has_key?(derivation.nodes, name) do
    MapSet.new([name | ancestors(derivation, name)])
  else
    MapSet.new()
  end
end
```

where `ancestors/2` walks the parent edges transitively. Version 0.2.0 also
filtered each retained node's `parents` down to the retained names. This file
shows the filter could only ever remove a name that resolves to no node: a
parent that is a node of the graph is an ancestor of the node it is a parent of,
hence of the cone's root, hence retained. So dropping the filter changes no
edge of the cone, and it stops a node that the derivation does not count as a
leaf from being counted as one inside its cone.
-/

namespace Tptp.Derivation

variable {α : Type}

/-- `parent p n`: `p` is named in `n`'s parents and is a node of the graph,
that is, `p → n` is an edge `parents_of/2` follows. -/
def Edges (α : Type) := α → α → Prop

/-- `Reaches parent p n`: `n` is reachable from `p` along one or more edges,
which is `n ∈ descendants p`, or equally `p ∈ ancestors n`. -/
inductive Reaches (parent : Edges α) : α → α → Prop
  | step {p n} : parent p n → Reaches parent p n
  | trans {p m n} : parent p m → Reaches parent m n → Reaches parent p n

/-- `retained/2`: the root and everything that reaches it. -/
def Retained (parent : Edges α) (root : α) (x : α) : Prop := x = root ∨ Reaches parent x root

/-- Every edge into a retained node comes from a retained node. -/
theorem retained_closed (parent : Edges α) (root n p : α)
    (hn : Retained parent root n) (hp : parent p n) : Retained parent root p := by
  rcases hn with rfl | hn
  · exact Or.inr (Reaches.step hp)
  · exact Or.inr (Reaches.trans hp hn)

/-- So filtering a retained node's resolved parents to the retained set keeps
all of them: the filter was a no-op on edges. -/
theorem filter_keeps_edges (parent : Edges α) (root n : α) [DecidablePred (Retained parent root)]
    (hn : Retained parent root n) (ps : List α) (hps : ∀ p ∈ ps, parent p n) :
    ps.filter (fun p => decide (Retained parent root p)) = ps := by
  rw [List.filter_eq_self]
  intro p hp
  exact decide_eq_true (retained_closed parent root n p hn (hps p hp))

end Tptp.Derivation
