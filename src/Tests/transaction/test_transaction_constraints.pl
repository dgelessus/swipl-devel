/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2020, VU University Amsterdam
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(test_transaction_constraints,
          [ test_transaction_constraints/0,
            test_transaction_constraints/3
          ]).

/** <module> Test transactions with constraints.

This module implements a rather  silly   constraint  to avoid concurrent
transactions from creating multiple values for   what should be a simple
fact with exactly one clause. Silly in the  sense that a lock around the
entire transaction is for this example a   much  simpler way to maintain
consistency.
*/

:- if(current_prolog_flag(threads, true)).

:- use_module(library(random)).
:- use_module(library(thread)).
:- use_module(library(debug)).

% :- debug(veto).

:- meta_predicate
    concurrent_with(0,0).

test_transaction_constraints :-
    test_transaction_constraints(1000, 2, 0).

test_transaction_constraints(N, M, Delay) :-
    flag(illegal_state, _, 0),
    concurrent_with(no_duplicate_temp_loop,
                    test(N, M, Delay)),
    get_flag(illegal_state, Count),
    (   Count == 0
    ->  true
    ;   format(user_error, 'Got ~D illegal states~n', [Count]),
        fail
    ).

:- dynamic
    temperature/1.

test(N, M, Delay) :-
    retractall(temperature(_)),
    asserta(temperature(0)),
    set_flag(conflict, 0),
    concurrent_forall(
        between(1, N, _),
        set_random_temp(Delay),
        [ threads(M)
        ]),
    get_flag(conflict, C),
    debug(veto, 'Resolved ~D conflicts', [C]).

%!  set_temp(+Degrees)
%
%   Update the single clause for temperature/1   using a transaction. As
%   two transactions be started that both want   to assert a new clause,
%   we must guard against this using   a  constraint. If the transaction
%   fails because the constraint it violated we just try again (we could
%   also generate an exception from  the   constraint  and not retry the
%   transaction).

set_temp(Degrees) :-
    repeat,
    transaction(update_temp(Degrees),
                no_duplicate_temp('Vetoed'),
                temp),
    !.

%!  update_temp(+Term)
%
%   The classical Prolog way to update a fact.

update_temp(Temp) :-
    temperature(Temp),
    !.
update_temp(Temp) :-
    retractall(temperature(_)),
    asserta(temperature(Temp)).

%!  no_duplicate_temp(+Why)
%
%   Ensure there is only one clause.  This is our constraint.

no_duplicate_temp(_) :-
    predicate_property(temperature(_), number_of_clauses(1)),
    !.
no_duplicate_temp(Why) :-
    findall(Temp, temperature(Temp), List),
    debug(veto, '~w: ~p', [Why, List]),
    flag(conflict, N, N+1),
    fail.

set_random_temp(Delay) :-
    A is random_float*Delay,
    sleep(A),
    random_between(-40, 40, Temp),
    set_temp(Temp).

concurrent_with(G1, G2) :-
    setup_call_cleanup(
        thread_create(G1, Id, []),
        G2,
        (   thread_signal(Id, abort),
            thread_join(Id, _)
        )).

no_duplicate_temp_loop :-
    (   snapshot(no_duplicate_temp('Verify'))
    ->  true
    ;   flag(illegal_state, C, C+1)
    ),
    no_duplicate_temp_loop.

:- else.

test_transaction_constraints.

:- endif.
