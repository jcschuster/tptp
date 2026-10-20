%--------------------------------------------------------------------------
% File     : MGT087+1 : TPTP v9.3.1. Bugfixed v9.3.1.
% Domain   : Management
% Problem  : totality - lteq denotation is non-empty
% Version  : Especial.
% English  : 

% Refs       [MC+26] Mustafa et al. (2026), Axis Decomposition for ODRL
% Source     [MC+26]
% Names      ODRL500-1.p [MC+26]

% Status   : Theorem
% Rating   : ? v9.3.1
% Syntax   : Number of formulae    :   35 (  14 unt;   0 def)
%            Number of atoms       :   87 (  26 equ)
%            Maximal formula atoms :    7 (   2 avg)
%            Number of connectives :   62 (  10   ~;   9   |;  23   &)
%                                         (   8 <=>;  12  =>;   0  <=;   0 <~>)
%            Maximal formula depth :    9 (   4 avg)
%            Maximal term depth    :    2 (   1 avg)
%            Number of predicates  :   12 (  11 usr;   0 prp; 1-4 aty)
%            Number of functors    :    7 (   7 usr;   6 con; 0-2 aty)
%            Number of variables   :   58 (  55   !;   3   ?)
% SPC      : FOF_THM_RFO_SEQ

% Comments : Requires MGT002+0.ax + MGT002+2.ax.
% Bugfixes : v9.3.1 - $distinct expanded to inequalities.
%--------------------------------------------------------------------------
include('Axioms/MGT002+0.ax').
include('Axioms/MGT002+2.ax').
%--------------------------------------------------------------------------
%----Named constants and ordering 
fof(val_v0,axiom,
    val(v0) ).

fof(val_v200,axiom,
    val(v200) ).

fof(val_v600,axiom,
    val(v600) ).

fof(ord_v0_v200,axiom,
    less(v0,v200) ).

fof(ord_v0_v600,axiom,
    less(v0,v600) ).

fof(ord_v200_v600,axiom,
    less(v200,v600) ).

fof(distinct,axiom,
    ( v0 != v200
    & v0 != v600
    & v200 != v600 ) ).

fof(odrl500,conjecture,
    ? [X] : in_lopen(X,v0,v600) ).

%--------------------------------------------------------------------------
