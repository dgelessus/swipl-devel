/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        jan@swi-prolog.org
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2021, SWI-Prolog Solutions b.v.
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

:- module(test_transact_incr,
          [ test_transact_incr/0
          ]).
:- use_module(library(plunit)).
:- use_module(library(increval)).
:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(prolog_code)).
:- use_module(library(tables)).

/** <module> Test lazy monotonic tabling
*/

test_transact_incr :-
    run_tests([ test_transact_incr_1
              ]).

:- meta_predicate
    init(0),
    cleanup(:),
    queued_answers(:,-,-),
    expect(?, 0, +),
    expect_valid(0),
    expect_invalid(0),
    expect_forced(0),
    incr_is_forced(0),
    expect_queued_answers(:, +).

% ================================================================
% Elementary testing

:- begin_tests(test_transact_incr_1).

:- dynamic d/1 as incremental.
:- table p/1 as (incremental).

p(X) :- d(X).

% Commits have no impact
test(commit, [cleanup(cleanup([d/1]))]) :-
    assertz(d(1)),
    expect(X, p(X), [1]),
    transaction(( assertz(d(2)),
                  expect(X, p(X), [1,2])
                )),
    expect_valid(p(_)),
    expect(X, p(X), [1,2]).

% A rollback must invalidate a table that is reevaluated
% inside a transaction while a dependent is modified.
test(rollback, [cleanup(cleanup([d/1]))]) :-
    assertz(d(1)),
    expect(X, p(X), [1]),
    \+ transaction(( assertz(d(2)),
                     expect(X, p(X), [1,2]),
                     fail
                   )),
    expect_invalid(p(_)),
    expect(X, p(X), [1]).

% snapshots must behave the same (and are easier, so
% we continue with them)
test(snapshot, [cleanup(cleanup([d/1]))]) :-
    assertz(d(1)),
    expect(X, p(X), [1]),
    snapshot(( assertz(d(2)),
               expect(X, p(X), [1,2])
             )),
    expect_invalid(p(_)),
    expect(X, p(X), [1]).

% A table that is evaluated inside a transaction while it
% has no dependencies on modified predicates remains valid
test(snapshot, [cleanup(cleanup([d/1]))]) :-
    assertz(d(1)),
    assertz(d(2)),
    snapshot(( expect(X, p(X), [1,2])
             )),
    expect_valid(p(_)),
    expect(X, p(X), [1,2]).

% a table reevaluated inside a transaction while the
% dependencies are untouched in the transaction remains
% valid.
test(snapshot, [cleanup(cleanup([d/1]))]) :-
    assertz(d(1)),
    expect(X, p(X), [1]),
    assertz(d(2)),
    snapshot(( expect_invalid(p(_)),
               expect(X, p(X), [1,2])
             )),
    expect_valid(p(_)),
    expect(X, p(X), [1,2]).

% A table that is evaluated inside a transaction, then
% updated based on data changed must be invalidated.
test(snapshot, [cleanup(cleanup([d/1]))]) :-
    assertz(d(1)),
    assertz(d(2)),
    snapshot(( expect(X, p(X), [1,2]),
               assertz(d(3)),
               expect(X, p(X), [1,2,3])
             )),
    expect_invalid(p(_)),
    expect(X, p(X), [1,2]).

:- end_tests(test_transact_incr_1).


		 /*******************************
		 *         TEST HELPERS		*
		 *******************************/

init(P) :-
    forall(P, true).

cleanup(M:List) :-
    abolish_all_tables,
    maplist(cleanup(M), List).

cleanup(M, PI) :-
    pi_head(PI, Head),
    retractall(M:Head).

expect(Templ, Goal, Answer) :-
    findall(Templ, Goal, R0),
    sort(R0, R),
    sort(Answer, Answer1),
    assertion(Answer1 == R).

expect_valid(Goal) :-
    assertion(\+ incr_is_invalid(Goal)).

expect_invalid(Goal) :-
    assertion(incr_is_invalid(Goal)).

expect_forced(Goal) :-
    assertion(incr_is_forced(Goal)).

incr_is_forced(Goal) :-
    get_call(Goal, ATrie, _Templ),
    '$idg_forced'(ATrie).

queued_answers(To, From, Count) :-
    get_calls(To, DstTrie, _Ret),
    '$idg_mono_affects_lazy'(DstTrie, SrcTrie, _Dep, _DepRef, Answers),
    '$tbl_table_status'(SrcTrie, _Status, From0, _Skeleton),
    unqualify(To, From0, From),
    length(Answers, Count).

unqualify(M:_, M:From, From) :- !.
unqualify(_, From, From).


expect_queued_answers(To, Expected0) :-
    findall(From-Count, queued_answers(To, From, Count), Pairs1),
    sort(Pairs1, Found),
    sort(Expected0, Expected),
    assertion(Found =@= Expected).

