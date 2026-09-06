tff(m_t, type, m: map($i, $i) > $o).
tff(p_t, type, p: $i > $o).
tff(m_a, axiom, ![X: $i, Y: $i]: (m(X, Y) => p(X))).
