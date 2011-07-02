/* -*- Mode: Prolog -*- */

:- module(owl2_visitor,
          [
           visit_all/2,
           visit_axioms/3,
           axiom_rewrite_list/3,
           rewrite_axiom/3,
           structurally_equivalent/2 % only exported for testing purposes..
           ]).

:- use_module(owl2_model).

%% visit_all_axioms(+Visitor,Ts)
visit_all(Visitor,Ts) :-
        findall(Axiom,axiom(Axiom),Axioms),
        visit_axioms(Axioms,Visitor,Ts).

visit_ontology(Ontology,Visitor) :-
        visit_ontology(Ontology,Visitor,_).
visit_ontology(Ontology,Visitor,Ts) :-
        findall(Axiom,ontologyAxiom(Ontology,Axiom),Axioms),
        visit_axioms(Axioms,Visitor,Ts).

%% visit_axioms(+Axioms:list,+Visitor,?Terms)
visit_axioms([],_,[]).
visit_axioms([Axiom|Axioms],Visitor,Ts_All) :-
        visit_axiom(Axiom,Visitor,Ts),
        visit_axioms(Axioms,Visitor,Ts2),
        append(Ts,Ts2,Ts_All).

%% visit_axiom(+Axiom,+Visitor,?Results:list)
%
% Visitor = visitor(Goal,AxiomTemplate,ExpressionTemplate,Result)
%
% Goal is applied for all axioms matching AxiomTemplate, the results are collected,
%  then all sub-expressions are visited, with the results appended
% A simple example collects all subclasses:
% ==
% visitor(true,subClassOf(X,Y),_,X)
% ==
% leaf classes:
% ==
% visitor(\+subClassOf(_,X),subClassOf(X,Y),_,X)
% ==
visit_axiom(Axiom,Visitor,Ts_All) :-
        visitor_axiom_template(Visitor,VisitGoal,AxiomTemplate,T),
        findall(T,(Axiom=AxiomTemplate,VisitGoal),Ts),
        Axiom =.. [_|Args],
        visit_args(Axiom,Args,Visitor,Ts2),
        append(Ts,Ts2,Ts_All).

visit_args(_,[],_,[]).
visit_args(Axiom,[Arg|Args],Visitor,Ts_All) :-
        visit_expression(Axiom,Arg,Visitor,Ts),
        visit_args(Axiom,Args,Visitor,Ts2),
        append(Ts,Ts2,Ts_All).

%% visit_expression(+SourceAxiom,+Expression,+Visitor,?Results:list)
%
% Visitor = visitor(Goal,AxiomTemplate,ExpressionTemplate,Result)
%
% Goal is called if the input expression matches the expression template
visit_expression(Axiom,Ex,Visitor,Ts_All) :-
        visitor_expression_template(Visitor,VisitGoal,AxiomTemplate,ExTemplate,T),
        !,
        findall(T,(Axiom=AxiomTemplate,Ex=ExTemplate,VisitGoal),Ts),
        !,
        Ex =.. [_|Args],
        visit_args(Axiom,Args,Visitor,Ts2),
        append(Ts,Ts2,Ts_All).
visit_expression(_,_,_,[]).

visitor_axiom_template(visitor(G,AT,_,R),G,AT,R) :- !.
visitor_axiom_template(axiom_visitor(G,AT,R),G,AT,R) :- !.
visitor_axiom_template(_,fail,_,_) :- !.
visitor_expression_template(visitor(G,AT,ET,R),G,AT,ET,R) :- !.
visitor_expression_template(expression_visitor(G,ET,R),G,_,ET,R) :- !.
visitor_expression_template(expression_visitor(G,AT,ET,R),G,AT,ET,R) :- !.

% ----------------------------------------
% axiom rewriting
% ----------------------------------------

%% axiom_rewrite_list(+Axiom,+Rule,?NewAxioms:list)
%
% given a ground axiom, calculate any rewrites
axiom_rewrite_list(Axiom,Rule,NewAxioms) :-
        setof(NewAxiom,rewrite_axiom(Axiom,Rule,NewAxiom),NewAxioms).

%% rewrite_axiom(+Axiom,+Rule,?NewAxiom) is nondet
%
% fails if Axiom does not match rule.
% succeeds once if Rule is deterministic.
% succeeds one or more times if Rule is non-deterministic.
% Rules are non-deterministic if 
rewrite_axiom(Axiom,Rules,NewAxiom) :-
        is_list(Rules),
        !,
        rewrite_axiom_multirule(Axiom,Rules,NewAxiom).
rewrite_axiom(Axiom,Rule,NewAxiom) :-
        debug(visitor,'testing ~w using ~w',[Axiom,Rule]),
        rule_axiom_template(Rule,ConditionalGoal,AxiomTemplate,TrAxiom),
        findall(TrAxiom,(structurally_equivalent(Axiom,AxiomTemplate),ConditionalGoal),A1L),
        %findall(TrAxiom,(structurally_equivalent(Axiom,AxiomTemplate),once(ConditionalGoal)),[A1]),
        %!,
        member(A1,A1L),
        member_or_identity(A1x,A1),
        debug(visitor,'  rewriting ~q ===> ~q',[Axiom,A1x]),
        A1x =.. [Pred|Args],
        rewrite_args(Axiom,Args,Rule,Args2),
        debug(visitor,'  rewrote ~w ===> ~w',[Args,Args2]),
        NewAxiom =.. [Pred|Args2].

%% rewrite_axiom_multirule(+AxiomIn,+Rules:list,?NewAxiom)
%
% iterates through rules applying each rule on axiom.
% note: does not attempt to forward chain, but an extension to the rule language
% could be added for this
rewrite_axiom_multirule(Axiom,Rules,OutAxiom) :-
        rewrite_axiom_multirule_sweep(Axiom,Rules,OutAxiom),
        !.
        %rewrite_axiom_multirule(NewAxiom,Rules,OutAxiom).

rewrite_axiom_multirule_sweep(Axiom,[],Axiom) :- !.
rewrite_axiom_multirule_sweep(Axiom,[Rule|Rules],NewAxiom) :-
        rewrite_axiom(Axiom,Rule,Axiom_2), % todo - nd
        !,
        rewrite_axiom_multirule_sweep(Axiom_2,Rules,NewAxiom).

%% rewrite_args(+Axiom,+ArgsIn:list,+Rule,?ArgsOut:list)
rewrite_args(_,[],_,[]) :- !.
rewrite_args(Axiom,[Arg|Args],Rule,[NewArg|NewArgs]) :-
        debug(v2,'  XX rewriting ~w',[Arg]),
        rewrite_expression(Axiom,Arg,Rule,NewArg),
        debug(v2,'  ===> XX  ~w',[NewArg]),
        rewrite_args(Axiom,Args,Rule,NewArgs).


%% rewrite_expression(+SourceAxiom,+Expression,+Rule,?NewExpression) is nondet
%
% Rule = visitor(Goal,AxiomTemplate,ExpressionTemplate,Result)
%
% Goal is called if the input expression matches the expression template
rewrite_expression(_,Ex,Rule,_) :-
        var(Ex),
        !,
        throw(error(variable_expression(Rule))).
rewrite_expression(Axiom,Ex,Rule,NewEx) :-
        nonvar(Ex),
        is_list(Ex),
        !,
        rewrite_args(Axiom,Ex,Rule,NewEx).
rewrite_expression(Axiom,Ex,Rule,NewEx) :-
        rule_expression_template(Rule,ConditionalGoal,ExTemplate,TrEx),
        findall(TrEx,(structurally_equivalent(Ex,ExTemplate),once(ConditionalGoal)),[Ex1]),
        !,
        debug(v2,'  ** tr ~q',[Ex1]),
        member_or_identity(Ex1_Single,Ex1),
        Ex1_Single =.. [Pred|Args],
        rewrite_args(Axiom,Args,Rule,NewArgs),
        NewEx =.. [Pred|NewArgs].
rewrite_expression(Axiom,Ex,Rule,NewEx) :-
        !,
        Ex =.. [Pred|Args],
        rewrite_args(Axiom,Args,Rule,NewArgs),
        NewEx =.. [Pred|NewArgs].


%% rule_axiom_template(+TrRule,Goal,InAxiomTemplate,OutAxiomTemplate)
rule_axiom_template(tr(axiom,In,Out,G,_),G,In,Out).
rule_axiom_template(tr(_,_,_,_,_),true,Ax,Ax). % pass-through
rule_axiom_template(Rule,_,_,_) :- Rule\=tr(_,_,_,_,_),throw(error(invalid(Rule))).
rule_expression_template(tr(expression,In,Out,G,_),G,In,Out).
%rule_expression_template(tr(_,_,_,_,_),true,Ex,Ex). % pass-through

member_or_identity(X,L) :-
        (   L=(A,B)
        *-> (   member_or_identity(X,A)
            ;   member_or_identity(X,B))
        ;   X=L).

% structural match
structurally_equivalent(Term,Term) :- !.
structurally_equivalent(QTerm,MTerm) :-
        QTerm =.. [Pred|QArgs],
        MTerm =.. [Pred|MArgs],
        structurally_equivalent_args(QArgs,MArgs),
        !.

structurally_equivalent_args(X,X) :- !.
structurally_equivalent_args(propertyChain(L1),propertyChain(L2)) :-
        !,
        % property chains are the only expressions where order is important
        L1=L2.
structurally_equivalent_args([Set1],[Set2]) :- % order of args is unimportant e.g. intersectionOf(Set)
        is_list(Set1),
        !,
        structurally_equivalent_args_unordered(Set1,Set2),
        !.

structurally_equivalent_args([],[]).
structurally_equivalent_args([A1|Args1],[A2|Args2]) :-
        structurally_equivalent(A1,A2),
        structurally_equivalent_args(Args1,Args2).

structurally_equivalent_args_unordered([],[]) :- !.
structurally_equivalent_args_unordered(Tail,[X]) :- nonvar(X),X=tail(Tail),!.
structurally_equivalent_args_unordered(_,[]) :- !,fail.
structurally_equivalent_args_unordered([],_) :- !,fail.
structurally_equivalent_args_unordered(L1,[X,A2|L2_Tail]) :-
        nonvar(X),
        X=tail(_),
        !,
        select(A1,L1,L1_Tail),
        structurally_equivalent(A1,A2),
        structurally_equivalent_args_unordered(L1_Tail,[X|L2_Tail]).
structurally_equivalent_args_unordered(L1,[A2|L2_Tail]) :-
        select(A1,L1,L1_Tail),
        structurally_equivalent(A1,A2),
        structurally_equivalent_args_unordered(L1_Tail,L2_Tail).


% ----------------------------------------
% test
% ----------------------------------------

t :-
        ontology(Ont),
        visit_ontology( Ont, visitor(check_av(Axiom,Expr,T), Axiom,Expr,T), L ),
        maplist(writeln,L).
                      
check_av(Axiom,Expr,bad(Expr,Axiom)) :-
        nonvar(Expr),
        Expr=unionOf(_),
        !.

        

        
