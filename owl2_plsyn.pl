/* -*- Mode: Prolog -*- */

:- module(owl2_plsyn,[
                      write_owl_as_plsyn/0,

                      plsyn_owl/2,
                      
                      op(1200,xfy,(--)),
                      op(1150,fx,class),
                      op(1150,fx,individual),
                      op(1150,xfy,disjointUnion),
                      op(1150,fx,transitive),
                      op(1150,fx,symmetric),
                      op(1150,fx,asymmetric),
                      op(1150,fx,reflexive),
                      op(1150,fx,irreflexive),
                                % 700 <
                                % 700 =
                      op(700,xfy,(->)),
                      op(650,xfy,(::)),
                      op(600,xfy,not),
                      op(500,xfy,or),
                      op(200,xfy,and),
                      op(200,xfy,that),
                      op(150,xfy,some),
                      op(150,xfy,only),
                      op(150,xfy,value)

                     ]).


:- use_module(owl2_model).
:- use_module(swrl).

:- op(1200,xfy,(--)).
:- op(1150,fx,individual).

:- op(1150,xfy,disjointUnion).

:- op(1150,fx,transitive).
:- op(1150,fx,symmetric).
:- op(1150,fx,asymmetric).
:- op(1150,fx,reflexive).
:- op(1150,fx,irreflexive).
% 700 <
% 700 =
:- op(700,xfy,(->)).
:- op(650,xfy,(::)).
:- op(600,xfy,not).
:- op(500,xfy,or).
:- op(200,xfy,and).
:- op(200,xfy,that).
:- op(150,xfy,some).
:- op(150,xfy,only).
:- op(150,xfy,value).
:- op(100,fx,(?)).

:- multifile owl2_io:load_axioms_hook/3.
owl2_io:load_axioms_hook(File,plsyn,Opts) :-
        owl_parse_plsyn(File,Opts). % TODO


write_owl_as_plsyn:-
        forall(axiompred(PS),
               write_axioms_as_plsyn(PS)).

write_axioms_as_plsyn(P/A):-
        !,
        functor(H,P,A),
        forall(H,(plsyn_owl(Pl,H),format('~q.~n',[Pl]))).

plsyn_owl(Pl,Owl) :-
        nonvar(Pl),
        plsyn2owl(Pl,Owl),
        !.
plsyn_owl(Pl,Owl) :-
        nonvar(Owl),
        owl2plsyn(Owl,Pl),
        !.


plsyn2owl(Pl,Owl) :-
        Pl=..[PlPred|Args],
        plpred2owlpred(PlPred,OwlPred),
        !,
        maplist(plsyn2owl,Args,Args2),
        Owl=..[OwlPred|Args2].
plsyn2owl(Pl,Owl) :-
        Pl=..[PlPred|Args],
        plpred2owlpred_list(PlPred,OwlPred), % TODO - reverse
        !,
        maplist(plsyn2owl,Args,Args2),
        Owl=..[OwlPred,[Args2]].

% TODO: entity annotations
plsyn2owl(Ax--Comments,[PlAx,axiomAnnotation('rdfs:comment',literal(Comments))]) :-
        !,
        plsyn2owl(Ax,PlAx).

% e.g. r < r1 * r2 *r3 ...
plsyn2owl(R < R1*R2,subPropertyOf(R,propertyChain(Chain))) :-
        plsyn2owl_ec(R1*R2,(*),Chain).

% we can chain over a=b=c=d as equivalent/sameAs is transitive
% (note we cannot do this for different/disjoint)
plsyn2owl(A=B,sameIndividual(ECs)) :-
        !,
        plsyn2owl_ec(A=B,(=),ECs).
plsyn2owl(A==B,equivalentClasses(ECs)) :-
        !,
        plsyn2owl_ec(A==B,(==),ECs).
plsyn2owl(A=@=B,equivalentProperties(ECs)) :-
        !,
        plsyn2owl_ec(A=@=B,(=@=),ECs).
plsyn2owl(A and B,intersectionOf(ECs)) :-
        !,
        plsyn2owl_ec(A and B,and,ECs).
plsyn2owl(A or B,unionOf(ECs)) :-
        !,
        plsyn2owl_ec(A or B,or,ECs).
plsyn2owl(X,X) :- !.


plsyn2owl_ec(T,Op,L) :-
        T=..[Op,A,B],
        !,
        plsyn2owl_ec(A,Op,LA),
        plsyn2owl_ec(B,Op,LB),
        append(LA,LB,L).
plsyn2owl_ec(A,_,[A]).
        

owl2plsyn(Owl,Pl) :-
        Owl=..[OwlPred|Args],
        plpred2owlpred(PlPred,OwlPred),
        !,
        maplist(owl2plsyn,Args,Args2),
        Pl=..[PlPred|Args2].
owl2plsyn(equivalentProperties(Args),Pl) :-
        maplist(owl2plsyn,Args,Args2),
        list_to_chain(Args2,(=@=),Pl).
owl2plsyn(equivalentClasses(Args),Pl) :-
        maplist(owl2plsyn,Args,Args2),
        list_to_chain(Args2,(==),Pl).
owl2plsyn(sameIndividuals(Args),Pl) :-
        maplist(owl2plsyn,Args,Args2),
        list_to_chain(Args2,(=),Pl).
owl2plsyn(intersectionOf(Args),Pl) :-
        maplist(owl2plsyn,Args,Args2),
        list_to_chain(Args2,and,Pl).
owl2plsyn(unionOf(Args),Pl) :-
        maplist(owl2plsyn,Args,Args2),
        list_to_chain(Args2,or,Pl).
owl2plsyn(implies(A,C),(A2->C2)) :-
        swrlatoms2plsyn(A,A2),
        swrlatoms2plsyn(C,C2).
owl2plsyn(X,X) :- !.

swrlatoms2plsyn(A,A2) :-
        is_list(A),
        !,
        maplist(swrlatom2plsyn,A,AL),
        list_to_chain(AL,(,),A2).
swrlatoms2plsyn(A,A2) :-
        !,
        swrlatom2plsyn(A,A2).

swrlatom2plsyn(description(CE,I),H) :-
        !,
        swrlatom2plsyn(I,I2),
        H=..[CE,I2].
swrlatom2plsyn(differentFrom(X,Y),X2 \= Y2) :-
        !,
        swrlatom2plsyn(X,X2),
        swrlatom2plsyn(Y,Y2).
swrlatom2plsyn(IPA,IPA2) :-
        IPA=..[P,X,Y],
        !,
        swrlatom2plsyn(X,X2),
        swrlatom2plsyn(Y,Y2),
        IPA2=..[P,X2,Y2].

swrlatom2plsyn(i(V),?V) :- !.
swrlatom2plsyn(X,X) :- !.


        
list_to_chain([X],_,X) :- !.
list_to_chain([X1|L],Op,Pl) :-
        !,
        list_to_chain(L,Op,X2),
        Pl=..[Op,X1,X2].


plpred2owlpred(transitive,transitiveProperty).

%plpred2owlpred(inverseOf,inverseProperties).

plpred2owlpred(some,someValuesFrom).
plpred2owlpred(only,allValuesFrom).


plpred2owlpred(::,classAssertion).
plpred2owlpred(<,subClassOf).
plpred2owlpred(@<,subPropertyOf).

plpred2owlpred_list(\=,differentIndividuals). 
plpred2owlpred_list(\=,disjointClasses). 





/** <module> prolog-style syntactic sugar for OWL

  ---+ Synopsis

==
:- use_module(bio(owl2_plsyn)).

% 
demo:-
  nl.
  

==

---+ Details



---+ Additional Information

This module is part of blip. For more details, see http://www.blipkit.org

@author  Chris Mungall
@version $Revision$
@see     README
@license License


*/
