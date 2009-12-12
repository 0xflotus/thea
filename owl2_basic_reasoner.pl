/* -*- Mode: Prolog -*- */

:- module(owl2_basic_reasoner,
          [
           entailed/1,
           property_assertion_common_ancestor/5,
           property_assertion_least_common_ancestor/5
          ]).

:- use_module(owl2_model).
:-['rules/basicset'].

:- multifile entailed/2.
:- multifile entailed_2/2.
:- multifile entailed_5/2.

:- discontiguous entailed/2.
:- discontiguous entailed_2/2.
:- discontiguous entailed_5/2.

%% entailed(?Axiom) is nondet
% true if Axiom is entailed
entailed(A) :-
        entailed(A,[]).


entailed(A,EL) :- entailed_2(A,EL).

% NEXT LEVEL
entailed_2(A,EL) :- entailed_5(A,EL).


% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% level 5:
% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


% NEXT LEVEL
entailed_5(A,EL) :- entailed_10(A,EL).


% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% level 10:
% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

% asserted
entailed_10(subClassOf(X,Y),_) :- subClassOf(X,Y).

% asserted
entailed_10(classAssertion(C,I),_) :- classAssertion(C,I).

% asserted
entailed_10(propertyAssertion(P,I,J),_) :- propertyAssertion(P,I,J).

% asserted
entailed_10(individual(I),_) :- individual(I).

:- dynamic entailed_cached/1.
% cached
entailed_10(X,_) :-
        entailed_cached(X).

entailed_10(X,_) :-
        \+ entailed_cached(_),
        forall(entailed_pre(A),
               assert(entailed_cached(A))),
        assert(entailed_cached(null)), % to ensure only executed once
        entailed_cached(X).


% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% UTIL
% ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pairwise_equivalent_class(X,Y) :- equivalentClasses(L),member(X,L),member(Y,L),X\=Y.
pairwise_disjoint_class(X,Y) :- disjointClasses(L),member(X,L),member(Y,L),X\=Y.

% TODO: make subClassOf nothing?
unsatisfiable(X) :-
        pairwise_disjoint_class(A,B),
        entailed(subClassOf(X,A)),
        entailed(subClassOf(X,B)).

% TODO: move this to a utility module
property_assertion_common_ancestor(P,XI,YI,XC,YC) :-
        propertyAssertion(P,XI,YI),
        % TESTING ONLY:
        sub_atom(XI,0,_,_,'http://ccdb.ucsd.edu/SAO/DPO/2.0/DPO.owl'),
        debug(owl2_basic_reasoner,'Testing ~w ~w ~w',[P,XI,YI]),
        entailed(classAssertion(XC,XI)),
        entailed(classAssertion(YC,YI)).

property_assertion_least_common_ancestor(P,XI,YI,XC,YC) :-
        property_assertion_common_ancestor(P,XI,YI,XC,YC),
        \+ ((property_assertion_common_ancestor(P,XI,YI,XC2,YC2),
             entailed(subClassOfReflexive(XC2,XC)),
             entailed(subClassOfReflexive(YC2,YC)),
             (   XC2\=XC ; YC2\=YC))).


% ----------------------------------------
% ABox Reasoning
% ----------------------------------------

% reified version of Grosof

/*
classAssertion(C,I) :- propertyRange(P,C),propertyAssertion(P,_,I).

propertyAssertion(P,A,B) :- transitiveProperty(P),propertyAssertion(P,A,C),propertyAssertion(P,C,B).
propertyAssertion(P,A,B) :- symmetricProperty(P),propertyAssertion(P,B,A).
propertyAssertion(Q,A,B) :- subPropertyOf(P,Q),propertyAssertion(P,A,B).

% role chains
propertyAssertion(P,A,B) :- subPropertyOf(propertyChain([P1|PL]),P),propertyAssertion(P,A,C),propertyAssertion_chain(PL,C,B).

propertyAssertion_chain([],_,_).
propertyAssertion_chain([P|PL],A,B) :- propertyAssertion(P,A,C),propertyAssertion_chain(PL,C,B).


*/

/** <module> simple scruffy backward chaining 

  ---+ Synopsis

  ==
  :- use_module(bio(owl2_basic_reasoner)).


  ==

  ---+ Details

  In certain circumstances, it may be desirable to use simple standard
  prolog backward chaining to do basic reasoning over an ontology. For
  example, if you want a lightweight fast way of finding the transitive
  closure of subClassOf/2 and want to avoid external dependencies then
  this might be the right approach.
  
  This module comes with a sizeable caveat emptor. There will be
  circumstances when reasoning will not terminate (although the module
  uses a few tricks to avoid these).

  ---+ Status

  This module is still somewhat experimental

  ---++ When should you use this module?

  See Reasoning-using-Thea.txt

  * You don't want to invoke any external dependencies, such as JPL or an external reasoner

  * You are prepared for incomplete results under certain circumstances

  * The task at hand is suited to 'scruffy' reasoning

  For example, if you have a large lightly axiomatized ontology in
  memory and you just want to find the closure of subClassOf/2 and the
  graph of class/1 nodes linked by transitive someValuesFrom/2
  restrictions.

  ---++ Implementation overview

  Using prolog and standard backwarch chaining we can find the
  transitive closure of a predicate like this:

  ==
  entailed(subClassOf(X,Y)) :- subClassOf(X,Y). % base case
  entailed(subClassOf(X,Z)) :- subClassOf(X,Y), entailed(subClassOf(X,Z)).
  ==

  However, this suffers from some limitations:

  * If subClassOf/2 contains cycles, the program will be
  non-terminating (not an impossible scenario, as subClassOf/2 is
  reflexive)

  * When we start to add rules for other axioms, there is a danger the
    rules will interact in a way that causes non-termination.

  The implementation of this module provides a few tricks under-the-hood:

  * A list of 'visited nodes' is maintained to avoid non-termination
   over cycles in some scenarios (not a replacement for tabling
   however)

  * The rules are stratified into levels. 

*/
