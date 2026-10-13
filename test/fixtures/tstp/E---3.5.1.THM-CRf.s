%------------------------------------------------------------------------------
% File     : E---3.5.1
% Problem  : PUZ001+1 : TPTP v9.3.1. Released v2.0.0.
% Transfm  : none
% Format   : tptp:raw
% Command  : run_E /export/starexec/sandbox2/benchmark/theBenchmark.p 300 THM

% Computer : n004.cluster.edu
% Model    : x86_64 x86_64
% CPU      : Intel(R) Xeon(R) CPU E5-2620 v4 2.10GHz
% Memory   : 8046.5625MB
% OS       : Linux 6.8.0-71-generic
% CPULimit : 300s
% WCLimit  : 300s
% DateTime : Thu Sep 24 02:01:19 PM UTC 2026

% Result   : Theorem 0.12s 0.45s
% Output   : CNFRefutation 0.12s
% Verified : 
% SZS Type : Refutation
%            Derivation depth      :    8
%            Number of leaves      :   11
% Syntax   : Number of formulae    :   54 (  22 unt;   0 def)
%            Number of atoms       :   95 (  28 equ)
%            Maximal formula atoms :    4 (   1 avg)
%            Number of connectives :   79 (  38   ~;  28   |;   2   &)
%                                         (   0 <=>;  11  =>;   0  <=;   0 <~>)
%            Maximal formula depth :    5 (   3 avg)
%            Maximal term depth    :    2 (   1 avg)
%            Number of predicates  :    6 (   4 usr;   1 prp; 0-2 aty)
%            Number of functors    :    5 (   5 usr;   4 con; 0-1 aty)
%            Number of variables   :   40 (   0 sgn  26   !;   3   ?)

% Comments : 
%------------------------------------------------------------------------------
fof(pel55_4,axiom,
    ! [X1,X2] :
      ( killed(X1,X2)
     => hates(X1,X2) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_4) ).

fof(pel55_1,axiom,
    ? [X1] :
      ( killed(X1,agatha)
      & lives(X1) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_1) ).

fof(pel55_3,axiom,
    ! [X1] :
      ( lives(X1)
     => ( X1 = charles
        | X1 = butler
        | X1 = agatha ) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_3) ).

fof(pel55_10,axiom,
    ! [X1] :
    ? [X2] : ~ hates(X1,X2),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_10) ).

fof(pel55_5,axiom,
    ! [X1,X2] :
      ( killed(X1,X2)
     => ~ richer(X1,X2) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_5) ).

fof(pel55_8,axiom,
    ! [X1] :
      ( ~ richer(X1,agatha)
     => hates(butler,X1) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_8) ).

fof(pel55_6,axiom,
    ! [X1] :
      ( hates(agatha,X1)
     => ~ hates(charles,X1) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_6) ).

fof(pel55_9,axiom,
    ! [X1] :
      ( hates(agatha,X1)
     => hates(butler,X1) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_9) ).

fof(pel55_7,axiom,
    ! [X1] :
      ( X1 != butler
     => hates(agatha,X1) ),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_7) ).

fof(pel55_11,axiom,
    agatha != butler,
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55_11) ).

fof(pel55,conjecture,
    killed(agatha,agatha),
    file('/export/starexec/sandbox2/benchmark/theBenchmark.p',pel55) ).

fof(c_0_11,plain,
    ! [X4,X5] :
      ( hates(X4,X5)
      | ~ killed(X4,X5) ),
    inference(fof_nnf,[status(thm)],[inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[pel55_4])])]) ).

fof(c_0_12,plain,
    ( killed(esk1_0,agatha)
    & lives(esk1_0) ),
    inference(skolemize,[status(esa)],[inference(variable_rename,[status(thm)],[pel55_1])]) ).

fof(c_0_13,plain,
    ! [X8] :
      ( X8 = charles
      | X8 = butler
      | X8 = agatha
      | ~ lives(X8) ),
    inference(fof_nnf,[status(thm)],[inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[pel55_3])])]) ).

fof(c_0_14,plain,
    ! [X1] :
    ? [X2] : ~ hates(X1,X2),
    inference(fof_simplification,[status(thm)],[pel55_10]) ).

fof(c_0_15,plain,
    ! [X1,X2] :
      ( killed(X1,X2)
     => ~ richer(X1,X2) ),
    inference(fof_simplification,[status(thm)],[pel55_5]) ).

fof(c_0_16,plain,
    ! [X1] :
      ( ~ richer(X1,agatha)
     => hates(butler,X1) ),
    inference(fof_simplification,[status(thm)],[pel55_8]) ).

fof(c_0_17,plain,
    ! [X1] :
      ( hates(agatha,X1)
     => ~ hates(charles,X1) ),
    inference(fof_simplification,[status(thm)],[pel55_6]) ).

cnf(c_0_18,plain,
    ( ~ killed(X1,X2)
    | hates(X1,X2) ),
    inference(split_conjunct,[status(thm)],[c_0_11]) ).

cnf(c_0_19,plain,
    killed(esk1_0,agatha),
    inference(split_conjunct,[status(thm)],[c_0_12]) ).

cnf(c_0_20,plain,
    ( ~ lives(X1)
    | X1 = charles
    | X1 = butler
    | X1 = agatha ),
    inference(split_conjunct,[status(thm)],[c_0_13]) ).

cnf(c_0_21,plain,
    lives(esk1_0),
    inference(split_conjunct,[status(thm)],[c_0_12]) ).

fof(c_0_22,plain,
    ! [X13] : ~ hates(X13,esk2_1(X13)),
    inference(fof_nnf,[status(thm)],[inference(skolemize,[status(esa)],[inference(variable_rename,[status(thm)],[c_0_14])])]) ).

fof(c_0_23,plain,
    ! [X12] :
      ( hates(butler,X12)
      | ~ hates(agatha,X12) ),
    inference(fof_nnf,[status(thm)],[inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[pel55_9])])]) ).

fof(c_0_24,plain,
    ! [X1] :
      ( X1 != butler
     => hates(agatha,X1) ),
    inference(fof_simplification,[status(thm)],[pel55_7]) ).

fof(c_0_25,plain,
    ! [X6,X7] :
      ( ~ richer(X6,X7)
      | ~ killed(X6,X7) ),
    inference(fof_nnf,[status(thm)],[inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[c_0_15])])]) ).

fof(c_0_26,plain,
    ! [X11] :
      ( hates(butler,X11)
      | richer(X11,agatha) ),
    inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[c_0_16])]) ).

fof(c_0_27,plain,
    ! [X9] :
      ( ~ hates(charles,X9)
      | ~ hates(agatha,X9) ),
    inference(fof_nnf,[status(thm)],[inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[c_0_17])])]) ).

cnf(c_0_28,plain,
    hates(esk1_0,agatha),
    inference(spm,[status(thm)],[c_0_18,c_0_19]) ).

cnf(c_0_29,plain,
    ( esk1_0 = charles
    | esk1_0 = butler
    | esk1_0 = agatha ),
    inference(spm,[status(thm)],[c_0_20,c_0_21]) ).

fof(c_0_30,plain,
    agatha != butler,
    inference(fof_simplification,[status(thm)],[pel55_11]) ).

cnf(c_0_31,plain,
    ~ hates(X1,esk2_1(X1)),
    inference(split_conjunct,[status(thm)],[c_0_22]) ).

cnf(c_0_32,plain,
    ( ~ hates(agatha,X1)
    | hates(butler,X1) ),
    inference(split_conjunct,[status(thm)],[c_0_23]) ).

fof(c_0_33,plain,
    ! [X10] :
      ( hates(agatha,X10)
      | X10 = butler ),
    inference(variable_rename,[status(thm)],[inference(fof_nnf,[status(thm)],[c_0_24])]) ).

cnf(c_0_34,plain,
    ( ~ richer(X1,X2)
    | ~ killed(X1,X2) ),
    inference(split_conjunct,[status(thm)],[c_0_25]) ).

cnf(c_0_35,plain,
    ( hates(butler,X1)
    | richer(X1,agatha) ),
    inference(split_conjunct,[status(thm)],[c_0_26]) ).

cnf(c_0_36,plain,
    ( ~ hates(charles,X1)
    | ~ hates(agatha,X1) ),
    inference(split_conjunct,[status(thm)],[c_0_27]) ).

cnf(c_0_37,plain,
    ( hates(charles,agatha)
    | esk1_0 = agatha
    | esk1_0 = butler ),
    inference(spm,[status(thm)],[c_0_28,c_0_29]) ).

fof(c_0_38,plain,
    agatha != butler,
    inference(fof_nnf,[status(thm)],[c_0_30]) ).

cnf(c_0_39,plain,
    ~ hates(agatha,esk2_1(butler)),
    inference(spm,[status(thm)],[c_0_31,c_0_32]) ).

cnf(c_0_40,plain,
    ( hates(agatha,X1)
    | X1 = butler ),
    inference(split_conjunct,[status(thm)],[c_0_33]) ).

fof(c_0_41,negated_conjecture,
    ~ killed(agatha,agatha),
    inference(assume_negation,[status(cth)],[pel55]) ).

cnf(c_0_42,plain,
    ( ~ killed(X1,agatha)
    | hates(butler,X1) ),
    inference(spm,[status(thm)],[c_0_34,c_0_35]) ).

cnf(c_0_43,plain,
    ( ~ hates(agatha,agatha)
    | esk1_0 = butler
    | esk1_0 = agatha ),
    inference(spm,[status(thm)],[c_0_36,c_0_37]) ).

cnf(c_0_44,plain,
    agatha != butler,
    inference(split_conjunct,[status(thm)],[c_0_38]) ).

cnf(c_0_45,plain,
    esk2_1(butler) = butler,
    inference(spm,[status(thm)],[c_0_39,c_0_40]) ).

fof(c_0_46,negated_conjecture,
    ~ killed(agatha,agatha),
    inference(fof_simplification,[status(thm)],[c_0_41]) ).

cnf(c_0_47,plain,
    hates(butler,esk1_0),
    inference(spm,[status(thm)],[c_0_42,c_0_19]) ).

cnf(c_0_48,plain,
    ( esk1_0 = agatha
    | esk1_0 = butler ),
    inference(sr,[status(thm)],[inference(spm,[status(thm)],[c_0_43,c_0_40]),c_0_44]) ).

cnf(c_0_49,plain,
    ~ hates(butler,butler),
    inference(spm,[status(thm)],[c_0_31,c_0_45]) ).

fof(c_0_50,negated_conjecture,
    ~ killed(agatha,agatha),
    inference(fof_nnf,[status(thm)],[c_0_46]) ).

cnf(c_0_51,plain,
    esk1_0 = agatha,
    inference(sr,[status(thm)],[inference(spm,[status(thm)],[c_0_47,c_0_48]),c_0_49]) ).

cnf(c_0_52,negated_conjecture,
    ~ killed(agatha,agatha),
    inference(split_conjunct,[status(thm)],[c_0_50]) ).

cnf(c_0_53,plain,
    $false,
    inference(sr,[status(thm)],[inference(rw,[status(thm)],[c_0_19,c_0_51]),c_0_52]),
    [proof] ).

%------------------------------------------------------------------------------
%----ORIGINAL SYSTEM OUTPUT
% 0.00/0.03  % Problem  : PUZ001+1 : TPTP v9.3.1. Released v2.0.0.
% 0.00/0.05  % Command  : run_E /export/starexec/sandbox2/benchmark/theBenchmark.p 300 THM
% 0.12/0.38  % Computer : n004.cluster.edu
% 0.12/0.38  % Model    : x86_64 x86_64
% 0.12/0.38  % CPU      : Intel(R) Xeon(R) CPU E5-2620 v4 @ 2.10GHz
% 0.12/0.38  % Memory   : 8046.5625MB
% 0.12/0.38  % OS       : Linux 6.8.0-71-generic
% 0.12/0.38  % CPULimit : 300
% 0.12/0.38  % WCLimit  : 300
% 0.12/0.38  % DateTime : Mon Sep 21 03:44:20 UTC 2026
% 0.12/0.38  % CPUTime  : 
% 0.12/0.38  Running run_E /export/starexec/sandbox2/benchmark/theBenchmark.p 300 THM
% 0.12/0.43  Running first-order theorem proving
% 0.12/0.43  Running: /export/starexec/sandbox2/solver/bin/eprover --delete-bad-limit=2000000000 --definitional-cnf=24 -s --print-statistics -R --print-version --proof-object --auto-schedule=8 --cpu-limit=300 /export/starexec/sandbox2/benchmark/theBenchmark.p
% 0.12/0.45  % Version: 3.5.1
% 0.12/0.45  % Preprocessing class: FSMSSMSSSSSNFFN.
% 0.12/0.45  % Scheduled 4 strats onto 8 cores with 300 seconds (2400 total)
% 0.12/0.45  % Starting G-E--_208_C18_F1_SE_CS_SOS_SP_PS_S5PRR_RG_S04AN with 1500s (5) cores
% 0.12/0.45  % Starting new_bool_3 with 300s (1) cores
% 0.12/0.45  % Starting new_bool_1 with 300s (1) cores
% 0.12/0.45  % Starting sh5l with 300s (1) cores
% 0.12/0.45  % sh5l with pid 2170034 completed with status 0
% 0.12/0.45  % Result found by sh5l
% 0.12/0.45  % Preprocessing class: FSMSSMSSSSSNFFN.
% 0.12/0.45  % Scheduled 4 strats onto 8 cores with 300 seconds (2400 total)
% 0.12/0.45  % Starting G-E--_208_C18_F1_SE_CS_SOS_SP_PS_S5PRR_RG_S04AN with 1500s (5) cores
% 0.12/0.45  % Starting new_bool_3 with 300s (1) cores
% 0.12/0.45  % Starting new_bool_1 with 300s (1) cores
% 0.12/0.45  % Starting sh5l with 300s (1) cores
% 0.12/0.45  % (lift_lambdas = 0, lambda_to_forall = 0,unroll_only_formulas = 0, sine = gf500_gu_R04_F100_L20000)
% 0.12/0.45  % SinE strategy is gf500_gu_R04_F100_L20000
% 0.12/0.45  % Search class: FGHSF-FFSS11-SFFFFFNN
% 0.12/0.45  % Scheduled 5 strats onto 1 cores with 300 seconds (300 total)
% 0.12/0.45  % Starting SubtermCWHack with 31s (1) cores
% 0.12/0.45  % SubtermCWHack with pid 2170043 completed with status 0
% 0.12/0.45  % Result found by SubtermCWHack
% 0.12/0.45  % Preprocessing class: FSMSSMSSSSSNFFN.
% 0.12/0.45  % Scheduled 4 strats onto 8 cores with 300 seconds (2400 total)
% 0.12/0.45  % Starting G-E--_208_C18_F1_SE_CS_SOS_SP_PS_S5PRR_RG_S04AN with 1500s (5) cores
% 0.12/0.45  % Starting new_bool_3 with 300s (1) cores
% 0.12/0.45  % Starting new_bool_1 with 300s (1) cores
% 0.12/0.45  % Starting sh5l with 300s (1) cores
% 0.12/0.45  % (lift_lambdas = 0, lambda_to_forall = 0,unroll_only_formulas = 0, sine = gf500_gu_R04_F100_L20000)
% 0.12/0.45  % SinE strategy is gf500_gu_R04_F100_L20000
% 0.12/0.45  % Search class: FGHSF-FFSS11-SFFFFFNN
% 0.12/0.45  % Scheduled 5 strats onto 1 cores with 300 seconds (300 total)
% 0.12/0.45  % Starting SubtermCWHack with 31s (1) cores
% 0.12/0.45  % Preprocessing time       : 0.001 s
% 0.12/0.45  
% 0.12/0.45  % Proof found!
% 0.12/0.45  % SZS status Theorem
% 0.12/0.45  % SZS output start CNFRefutation
% See solution above
% 0.12/0.45  % Parsed axioms                        : 14
% 0.12/0.45  % Removed by relevancy pruning/SinE    : 0
% 0.12/0.45  % Initial clauses                      : 15
% 0.12/0.45  % Removed in clause preprocessing      : 0
% 0.12/0.45  % Initial clauses in saturation        : 15
% 0.12/0.45  % Processed clauses                    : 40
% 0.12/0.45  % ...of these trivial                  : 0
% 0.12/0.45  % ...subsumed                          : 4
% 0.12/0.45  % ...remaining for further processing  : 36
% 0.12/0.45  % Other redundant clauses eliminated   : 0
% 0.12/0.45  % Clauses deleted for lack of memory   : 0
% 0.12/0.45  % Backward-subsumed                    : 9
% 0.12/0.45  % Backward-rewritten                   : 6
% 0.12/0.45  % Generated clauses                    : 43
% 0.12/0.45  % ...of the previous two non-redundant : 40
% 0.12/0.45  % ...aggressively subsumed             : 0
% 0.12/0.45  % Contextual simplify-reflections      : 0
% 0.12/0.45  % Paramodulations                      : 38
% 0.12/0.45  % Factorizations                       : 5
% 0.12/0.45  % NegExts                              : 0
% 0.12/0.45  % Equation resolutions                 : 0
% 0.12/0.45  % Disequality decompositions           : 0
% 0.12/0.45  % Total rewrite steps                  : 11
% 0.12/0.45  % ...of those cached                   : 6
% 0.12/0.45  % Propositional unsat checks           : 0
% 0.12/0.45  %    Propositional check models        : 0
% 0.12/0.45  %    Propositional check unsatisfiable : 0
% 0.12/0.45  %    Propositional clauses             : 0
% 0.12/0.45  %    Propositional clauses after purity: 0
% 0.12/0.45  %    Propositional unsat core size     : 0
% 0.12/0.45  %    Propositional preprocessing time  : 0.000
% 0.12/0.45  %    Propositional encoding time       : 0.000
% 0.12/0.45  %    Propositional solver time         : 0.000
% 0.12/0.45  %    Success case prop preproc time    : 0.000
% 0.12/0.45  %    Success case prop encoding time   : 0.000
% 0.12/0.45  %    Success case prop solver time     : 0.000
% 0.12/0.45  % Current number of processed clauses  : 21
% 0.12/0.45  %    Positive orientable unit clauses  : 6
% 0.12/0.45  %    Positive unorientable unit clauses: 0
% 0.12/0.45  %    Negative unit clauses             : 7
% 0.12/0.45  %    Non-unit-clauses                  : 8
% 0.12/0.45  % Current number of unprocessed clauses: 3
% 0.12/0.45  % ...number of literals in the above   : 6
% 0.12/0.45  % Current number of archived formulas  : 0
% 0.12/0.45  % Current number of archived clauses   : 15
% 0.12/0.45  % Clause-clause subsumption calls (NU) : 21
% 0.12/0.45  % Rec. Clause-clause subsumption calls : 17
% 0.12/0.45  % Non-unit clause-clause subsumptions  : 9
% 0.12/0.45  % Unit Clause-clause subsumption calls : 13
% 0.12/0.45  % Rewrite failures with RHS unbound    : 0
% 0.12/0.45  % BW rewrite match attempts            : 2
% 0.12/0.45  % BW rewrite match successes           : 2
% 0.12/0.45  % Condensation attempts                : 0
% 0.12/0.45  % Condensation successes               : 0
% 0.12/0.45  % Termbank termtop insertions          : 898
% 0.12/0.45  % Search garbage collected termcells   : 81
% 0.12/0.45  
% 0.12/0.45  % -------------------------------------------------
% 0.12/0.45  % User time                : 0.005 s
% 0.12/0.45  % System time              : 0.003 s
% 0.12/0.45  % Total time               : 0.007 s
% 0.12/0.45  % Maximum resident set size: 3636 pages
% 0.12/0.45  
% 0.12/0.45  % -------------------------------------------------
% 0.12/0.45  % User time                : 0.006 s
% 0.12/0.45  % System time              : 0.008 s
% 0.12/0.45  % Total time               : 0.013 s
% 0.12/0.45  % Maximum resident set size: 4608 pages
% 0.12/0.45  % E exiting
%------------------------------------------------------------------------------
