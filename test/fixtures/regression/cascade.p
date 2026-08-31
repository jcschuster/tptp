%----An unterminated quote leaves the paren depth stuck above zero, so the
%----dots that follow are read as part of a term and the next two statements
%----are swallowed. Recovery resumes once the depth returns to zero.
fof(before, axiom, p).
fof(unterminated, axiom, 'no closing quote).
fof(swallowed_one, axiom, q).
fof(swallowed_two, axiom, r)).
fof(after, axiom, s).
