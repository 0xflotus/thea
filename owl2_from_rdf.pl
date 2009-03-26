/* -*- Mode: Prolog -*- */
% **********************************************************************
%                                OWL PARSER
% Author: Vangelis Vassiliadis
% Change Log: 
%             May 04: Initial release 0.1 
%             Jan 05: Version 0.2 - Some code optimisation.
%             Feb 05: DisjointClass, EquivalentClass
%             Mar 05: DifferentFrom
%             Feb 09: OWL2 (CJM)
%             
% Version 0.3 First release, March 22, 2005
%             
% Version 0.4 Changes (use of SWI's rdf parser 5.5.12)
%             * rdf_load/2 options to noshare of blank nodes and use a 
%               convert function to hold datatyped values.
%             * removed fix_owl. Apparently is not needed with SWI 5.5.x
%	      * Implemented equivalentProperties by re-using the logic
%	        of equivalentClass and sameAs. 
%	      * Implementation of owl:imports (handled at RDF/triple
%		level) by importing all RDF triples prior to building
%		the the OWL abstract syntax terms. Flag to select if 
%		imports will be handled.
%	      * OWL parser can parse now either local files or URLs (in-
%		line with Semweb's package RDF parser). Use of SWI's
%		http package.
%	      * owl_pack_ontology, owl_report	
% Version 0.5.5: March 07: Changes to the use_module and definitions for Thea 0.5.5 release. 
% To do        Check and report for purely Internal (DL errors) 
%              Inferences 
%  Changes for GIT
% **********************************************************************

:- module(owl2_from_rdf,
	  [ 
            owl_parse_rdf/1,
            owl_parse_rdf/2,
	    owl_parse/4,
            convert/3,
	    expand_ns/2,                  %  ?NS_URL, ?Full_URL
	    collapse_ns/4,
	   
	    blanknode/3,
	    blanknode_gen/2,
	    owl_parser_log/2
	  ]).

:- use_module(owl2_model).

:- use_module(library('semweb/rdf_db.pl')).
:- use_module(library('semweb/rdf_edit.pl')).
:- use_module(library('semweb/rdfs.pl')).
:- use_module(library('url.pl')).
:- use_module(library('http/http_open.pl')).

:- dynamic(owl/4).
:- dynamic(blanknode/3).
:- dynamic(owl_parser_log/2).
:- dynamic(blanknode_gen/2).
:- dynamic(outstream/1).
:- dynamic(annotation/3). % implements the ANN(X) function.
:- dynamic(owl_repository/2). % implements a simple OWL repository: if URL not found, Ontology is read from a repository (local) RURL


% we make this discontiguous so that the code can follow the structure of the document as much as possible

:- discontiguous owl_parse_axiom/1.
:- discontiguous owl_parse_axiom/3.


% -----------------------------------------------------------------------		    
%                                Top Level  Predicates
% -----------------------------------------------------------------------

owl_parse_rdf(F):-
	owl_parse_rdf(F,[]).
owl_parse_rdf(F,Opts):-
	(   member(imports(Imports),Opts)
	->  true
	;   Imports=false),
	(   member(clear(Clear),Opts)
	->  true
	;   Clear=false),
	owl_parse(F,Clear,Clear,Imports),
	debug(owl_parser,'parsed ~w',[F]).


%% owl_parse(+URL, +RDF_Load_Mode, +OWL_Parse_Mode, +Imports)
%
%  Top level predicate to parse a set of RDF triples and produce an
%  Abstract Syntax representation of an OWL ontology.
%		    
%	Calls the rdf_load_stream predicate to parse RDF stream in URL. 
%       If RDF_Load_Mode = complete it first retacts all rdf triples.
%       If Imports = true it handles owl:import clause at RDF level.
%
% owl_parse(+OWL_Parse_Mode).
            					       

owl_parse(URL, RDF_Load_Mode, OWL_Parse_Mode,ImportFlag) :-
%	(   RDF_Load_Mode=complete,!,rdf_retractall(_,_,_); true),
	(   RDF_Load_Mode=complete -> rdf_retractall(_,_,_) ; true),
	retractall(rdf_db:rdf_source(_,_,_,_)),
        debug(owl_parser,'Loading stream ~w',[URL]),
	owl_canonical_parse_2([URL],URL,ImportFlag,[],ProcessedIRI),
	(   OWL_Parse_Mode=complete -> owl_clear_as ; true),
	owl_canonical_parse_3(ProcessedIRI).
	        

owl_canonical_parse_2([],_,_,Processed,Processed) :- !.

owl_canonical_parse_2([IRI|ToProcessRest],ImportFlag,Parent,ProcessedIn,ProcessedOut) :-
	member(IRI,ProcessedIn),!,
	owl_canonical_parse_2(ToProcessRest,ImportFlag,Parent,ProcessedIn,ProcessedOut).

owl_canonical_parse_2([IRI|ToProcessRest],Parent,ImportFlag,ProcessedIn,ProcessedOut) :-
	% Get rdf triples, *Ontology* and Imports 
	rdf_load_stream(IRI,O,Imports),
	%	process(IRI,O,Imports),!,
	( nonvar(O) -> Ont = O; Ont = Parent, retractall(rdf(Parent,'http://www.w3.org/2002/07/owl#imports',IRI)) ),
	rdf_2_owl(IRI), % move the RDF triples into the owl-Ont/4 facts
	% print(IRI-triples-processed-into-Ont),nl,
	(   ImportFlag = true -> owl_canonical_parse_2(Imports,Ont,ImportFlag,[IRI|ProcessedIn],ProcessedIn1) ; 
	ProcessedIn1=[IRI|ProcessedIn]),
	owl_canonical_parse_2(ToProcessRest,Parent,ImportFlag,ProcessedIn1,ProcessedOut).


owl_canonical_parse_3([]).

owl_canonical_parse_3([IRI|Rest]) :-
        debug(owl_parser,'Commencing rdf_2_owl. Generating owl/4',[]),
	% Remove anyu existing not used owl fact
	retractall(owl(_,_,_,not_used)),
	% Copy the owl facts of the IRI document to the 'not_used'
	forall(owl(S,P,O,IRI),assert(owl(S,P,O,not_used))),
	% continue with parsing using the rules...
        owl_parse_nonannotated_axioms(ontology/1),
	
	findall(_,ann(_,_),_), % finad all annotations, assert annotation(X,AP,AV) axioms.
        forall((axiompred(PredSpec),\+dothislater(PredSpec),\+omitthis(PredSpec)),
               owl_parse_annotated_axioms(PredSpec)),
        forall((axiompred(PredSpec),dothislater(PredSpec),\+omitthis(PredSpec)),
               owl_parse_annotated_axioms(PredSpec)),

	forall((axiompred(PredSpec),\+dothislater(PredSpec),\+omitthis(PredSpec)),
               owl_parse_nonannotated_axioms(PredSpec)),
        forall((axiompred(PredSpec),dothislater(PredSpec),\+omitthis(PredSpec)),
               owl_parse_nonannotated_axioms(PredSpec)),!,
	owl_canonical_parse_3(Rest).


omitthis(ontology/1).

:- discontiguous dothislater/1.


owl_parse_annotated_axioms(Pred/Arity) :-
        debug(owl_parser_detail,'Parsing all of type: ~w',[Pred]),
        functor(Head,Pred,Arity),
	forall(owl_parse_axiom(Head,true,Annotations), 
	       (   assert(Head), 
		   forall(member(X,Annotations),
			  forall(annotation(X,AP,AV),assert(annotation(Head,AP,AV)))
			 )
	       )
	      ).
owl_parse_nonannotated_axioms(Pred/Arity) :-
        debug(owl_parser_detail,'Parsing all of type: ~w',[Pred]),
        functor(Head,Pred,Arity),
	forall(owl_parse_axiom(Head,false,_), 
	       assert(Head)
	      ).


% -----------------------------------------------------------------------		    
%                                UTILITY Predicates
% -----------------------------------------------------------------------

%%       owl_parser_log(+Log)
%
%       Log is a list; together with a timestamp it is asserted as
%       an owl_parser_log/2 term.

owl_parser_log(Log) :-
	debug(owl_parser,'~w',[Log]),
	get_time(T),convert_time(T,TS),
	assertz(owl_parser_log(TS, Log)).


%%       owl_clear_as.
%
%       Clears the prolog terms that store the Abstract Syntax
%       implementation of the OWL ontology.

owl_clear_as :- 
        debug(owl_parser,'Clearing abstract syntax',[]),
        forall((axiompred(PredSpec),predspec_head(PredSpec,Head)),
               retractall(Head)).

predspec_head(Pred/A,Head) :- functor(Head,Pred,A).

u_assert(Term) :- 
	call(Term), !; assert(Term).


convert(T,V,typed_value(T,V)).     


%%	rdf_2_owl/1.     
%       
%       Converts RDF triples to OWL/4 triples so that
%	their use can tracked by the OWL parser.


rdf_2_owl(Ont) :-
	owl_parser_log(['Removing existing owl triples']),
	retractall(owl(_,_,_,_)),
	owl_parser_log('Copying RDF triples to OWL triples'), 
	rdf(X,Y,Z), 
%	owl_fix_no(X,X1), owl_fix_no(Y,Y1), owl_fix_no(Z,Z1),
	assert(owl(X,Y,Z,Ont)), fail.

rdf_2_owl(_Ont) :-
	owl_count(Z),
	owl_parser_log(['Number of owl triples copied: ',Z]).


%%       rdf_load_stream(+URL, -Ontology, -Imports)
%	
%	This predicate calls the rdf parser to parse the RDF/XML URL
%	into RDF triples. URL can be a local file or a URL.
%	The predicate returns all Imports based on the 	owl:imports predicate. 
%	Also the Ontology of the URL if an owl:Ontology exists, var
%	otherise. 


rdf_load_stream(URL,Ontology,Imports) :- 
  	(sub_string(URL,0,4,_,'http'), !, 
	 catch((http_open(URL,RDF_Stream,[]),		
		rdf_load(RDF_Stream,[if(true),blank_nodes(noshare),result(Action, Triples, MD5)]),
		debug(owl_parser,' Loaded ~w stream: ~w Action: ~w Triples:~w MD5: ~w',[URL,RDF_Stream,Action,Triples,MD5]),
		close(RDF_Stream)),
	       Message, 
	       (owl_repository(URL,RURL),!,rdf_load_stream(RURL,Ontology,Imports) ;
	         print(Message),nl)) 
	;
	 RDF_Stream = URL, rdf_load(RDF_Stream,[blank_nodes(noshare),if(true)])
	),
	(   rdf(Ontology,'http://www.w3.org/1999/02/22-rdf-syntax-ns#type','http://www.w3.org/2002/07/owl#Ontology'),
	    findall(I,rdf(Ontology,'http://www.w3.org/2002/07/owl#imports',I),Imports) 
	; 
	    Imports = []
	).


%%	fix_no(+A,-B)  
%
%	This is used to correct an RDF parser error: 
%       To remove duplicate ## from a URL.

/*	Obsolete with version 5.5.x of SWI's RDF parser
owl_fix_no(literal(X), literal(X)) :- !.

owl_fix_no(A,B) :- 
	sub_atom(A,Start,_,After,'##'),
	sub_atom(A,0,Start,_,New_A),
	Start1 is Start + 2,
	sub_atom(A,Start1,After,_,B1),
	atom_concat(New_A,'#',A1), 
	atom_concat(A1,B1,B),!,print(A-B).

owl_fix_no(A,A).
*/
 

%%	owl_count(?U). 
%       Returns/Checks the number of unused OWL triples. 

owl_count(U) :- 
	findall(1,owl(_,_,_,not_used),X), length(X,U).


%%       test_use_owl(?S,?P,?O)   
%	As use_owl/3, but does not consume the triple

test_use_owl(X1,Y1,Z1) :- 
	expand_ns(X1,X),
	expand_ns(Y1,Y),
	expand_ns(Z1,Z),
	owl(X,Y,Z, not_used).

test_use_owl(X1,Y1,Z1,named) :- 
	expand_ns(X1,X),
	expand_ns(Y1,Y),
	expand_ns(Z1,Z),
	owl(X,Y,Z, not_used),
	not(sub_string(X,0,2,_,'__')).

%%       use_owl(+Triples:list)   
%	Marks a list of OWL triples as used, but only if all match. Expands the S,P,O.

use_owl(Triples) :-
        forall(member(owl(S,P,O),Triples),
               test_use_owl(S,P,O)),
        forall(member(owl(S,P,O),Triples),
               use_owl(S,P,O)).

%%       use_owl(?S,?P,?O)   
%	Marks an OWL triple as used. Expands the S,P,O.

use_owl(X1,Y1,Z1) :- 
	expand_ns(X1,X),
	expand_ns(Y1,Y),
	expand_ns(Z1,Z),
	owl(X,Y,Z, not_used),
	debug(owl_parser_detail,'using ~w ~w ~w',[X,Y,Z]),
	retract(owl(X,Y,Z, not_used)),
	assert(owl(X,Y,Z,used)).


%%	use_owl(?S,?P,?O,named). 
%
%       Same as use_owl/3, but marks only if S 	is Named URI (i.e. non blank node).

use_owl(X1,Y1,Z1,named) :- 
	expand_ns(X1,X),
	expand_ns(Y1,Y),
	expand_ns(Z1,Z),
	owl(X,Y,Z, not_used),
	not(sub_string(X,0,2,_,'__')), 
	retract(owl(X,Y,Z, not_used)),
	assert(owl(X,Y,Z,used)).


%%       expand_ns(+NS_URL, ?Full_URL)
%
%       Expands a 'namespaced' URI of the form ns:fragment to a full URI
%       substituting the full expansion for ns from the ns/2 facts
expand_ns(NS_URL, Full_URL) :-
	nonvar(NS_URL), 
	not(NS_URL = literal(_)),
	uri_split(NS_URL,Short_NS,Term, ':'), 
	rdf_db:ns(Short_NS,Long_NS),!,
	concat_atom([Long_NS,Term],Full_URL).

expand_ns(URL, URL).


%%       collapse_ns(+FullURL, ?NSURL, +Options)
%
%	Collapses a full URI of the form Path#fragment to a Namespaced
%	URI NS:fragment substituting the full expansion for ns from
%	the ns/2 facts
%	Char is either ':' for normal ns notation or '_' for builing
%	prolog terms.
%	Options supported: no_base(ShortNs): Use only term!


collapse_ns(FullURL, NSURL,Char,Options) :-
	nonvar(FullURL), 
	not(FullURL = literal(_)),
	uri_split(FullURL,LongNS, Term, '#'), 
	concat(LongNS,'#',LongNS1),
	rdf_db:ns(ShortNS,LongNS1),
	(   member(no_base(ShortNS),Options), ! , NSURL = Term 
	; 
	concat_atom([ShortNS,Char,Term],NSURL)
	),!.
% CJM
collapse_ns(FullURL, NSURL,_Char,Options) :-
	nonvar(FullURL), 
	not(FullURL = literal(_)),
	uri_split(FullURL,LongNS, Term, '#'), 
	member(no_base(LongNS),Options),
        !,
        NSURL = Term.


collapse_ns(URL, URL,_,_).



%%       uri_split(+URI,-Namespace,-Term,+Split_Char) :-
%
%       Splits a URI into the Namespace and the Term parts 
%       separated by the Split_Char character.
%       It supposes URI = concat(Namespace,Split_Char,Term)

uri_split(URI,Namespace,Term,Split_Char) :-
	sub_atom(URI,Start,_,After,Split_Char),
	sub_atom(URI,0,Start,_,Namespace),
	Start1 is Start + 1, 
	sub_atom(URI,Start1,After,_,Term). 

	
%%       owl_collect_linked_nodes(+Node,+Predicate, +InList,-OutList)

%	Appends Node to the InList, and recursively, all other
%	Nodes that are linked with the Predicate to the Node. The
%	result is returned to OutList.

owl_collect_linked_nodes(Node,Predicate,InList,OutList) :-
	use_owl(Node,Predicate,A),!,
	owl_collect_linked_nodes(Node,Predicate,InList,List1),
	owl_collect_linked_nodes(A,Predicate,List1,OutList).

owl_collect_linked_nodes(Node,Predicate,InList,OutList) :-
	use_owl(A,Predicate,Node),!,
	owl_collect_linked_nodes(Node,Predicate,InList,List1),
	owl_collect_linked_nodes(A,Predicate,List1,OutList).
	
owl_collect_linked_nodes(Node,_,List, [Node|List]) :- 
	not(memberchk(Node, List)),!.

owl_collect_linked_nodes(_,_,List, List) :- !.


% ----------------------------------------------------------------
%                OWL Parser implementation predicates	       
% ----------------------------------------------------------------

%%       owl_deprecated_class(+CID,-Deprecated).
%
%       Deprecated is set to true if Class CID is defined as deprecated.
%       false otherwise.

owl_deprecated_class(CID,Deprecated) :-
	use_owl(CID,'rdf:type','owl:DeprecatedClass'), Deprecated = true,!; 
	Deprecated = false.

%%       owl_deprecated_property(+PID,-Deprecated).
%
%	Deprecated is set to true if Property PID is defined as
%	deprecated; false otherwise.

owl_deprecated_property(PID,Deprecated) :-
	use_owl(PID,'rdf:type','owl:DeprecatedProperty'), Deprecated = true,!; 
	Deprecated = false.

%%       owl_get_bnode(+Node,+Description)
%
%	if Node is a blank (not named) node, then it is asserted in
%	the database as a blanknode(Node,Description,used) term.
%	The purpose is to record when a blank node has been used, so
%	subsequent uses of it will result in structure sharing. 

owl_get_bnode(Node,Description) :-
	sub_string(Node,0,2,_,'__'),!,
	not( blanknode(Node,_,_)),
	assert(blanknode(Node,Description, used)).

owl_get_bnode(_,_).

%%       owl_optional_type(+D).
%
%	It simply consumes any optional owl:Class or
%	rdfs:Class type triples for description D

use_optional_type(D) :- 
  use_owl(D,'rdf:type','owl:Class'), use_owl(D,'rdf:type','rdfs:Class'),!;
  use_owl(D,'rdf:type','rdfs:Class'),!;
  true.



% ----------------------------------------------------------------
% 3 Mapping from RDF Graphs to the Structural Specification
% ----------------------------------------------------------------

/*

  This section specifies the results of steps CP-2.2 and CP-3.3 of the
  canonical parsing process from Section 3.6 of the OWL 2
  Specification [OWL 2 Specification] on an ontology document D that
  can be parsed into an RDF graph G. An OWL 2 tool MAY implement these
  steps in any way it chooses; however, the results MUST be
  structurally equivalent to the ones defined in the following
  sections. These steps do not depend on the RDF syntax used to encode
  the RDF graph in D; therefore, the ontology document D is identified
  in this section with the corresponding RDF graph G.

An RDF syntax ontology document is any sequence of octets accessible
from some given IRI that can be parsed into an RDF graph, and that
then be transformed into an OWL 2 ontology by the canonical parsing
process instantiated as specified in this section.

The following sections contain rules in which triple patterns are
matched to G. If a triple pattern contains a variable number of
triples, the maximal possible subset of G MUST be matched. The
following notation is used in the patterns:

    * The notation NN_INT(n) can be matched to any literal whose value n is a nonnegative integer.
    * Possible conditions on the pattern are enclosed in curly braces { }.
    * Some patterns use optional parts, which are enclosed in square brackets '[ ]'.
    * The abbreviation T(SEQ y1 ... yn) denotes the pattern corresponding to RDF lists, as shown in Table 3.

  */

%       owl_description_list(+Node, -List) 
%
%       If +Node is defined as rdf:type rdf:List, then List returns
%       a prolog list of descriptions for this Node.

owl_description_list('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil',[]) :- !.
	     
owl_description_list(X,[F|R]) :- 
	use_owl(X,'rdf:type','rdf:List'),
	use_owl(X,'rdf:first',Element),
	owl_description(Element,F),
	use_owl(X,'rdf:rest',Y),
	!,owl_description_list(Y,R).


%       owl_individual_list(+Node, -List) 
%
%       If +Node is defined as rdf:type rdf:List, then List returns
%       a prolog list of individuals for this Node.

owl_individual_list('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil',[]) :- !.

owl_individual_list(X,[F|R]) :- 
	use_owl(X,'rdf:type','rdf:List'),
	use_owl(X,'rdf:first',F),
	use_owl(X,'rdf:rest',Y),
	!,owl_individual_list(Y,R).

%       owl_property_list(+Node, -List) 
%
%       If +Node is defined as rdf:type rdf:List, then List returns
%       a prolog list of properties for this Node.

owl_property_list('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil',[]) :- !.
	     
owl_property_list(X,[F|R]) :- 
	use_owl(X,'rdf:type','rdf:List'),
	use_owl(X,'rdf:first',Element),
	owl_property_expression(Element,F),
	use_owl(X,'rdf:rest',Y),
	!,owl_property_list(Y,R).

%       owl_datarange_list(+Node, -List) 
%
%       If +Node is defined as rdf:type rdf:List, then List returns
%       a prolog list of dataranges for this Node.

owl_datarange_list('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil',[]) :- !.
	     
owl_datarange_list(X,[F|R]) :- 
	use_owl(X,'rdf:type','rdf:List'),
	use_owl(X,'rdf:first',Element),
	owl_datarange(Element,F),
	use_owl(X,'rdf:rest',Y),
	!,owl_datarange_list(Y,R).

%       owl_datatype_restriction_list(+Node, -List) 
%
%       If +Node is defined as rdf:type rdf:List, then List returns
%       a prolog list of datatype restrictions for this Node.

owl_datatype_restriction_list('http://www.w3.org/1999/02/22-rdf-syntax-ns#nil',[]) :- !.
	     
owl_datatype_restriction_list(X,[W-L|R]) :- 
	use_owl(X,'rdf:type','rdf:List'),
	use_owl(X,'rdf:first',Element),
	use_owl(Element,W,L),	
	use_owl(X,'rdf:rest',Y),
	!,owl_datatype_restriction_list(Y,R).


% 3.1 Extracting Declarations and the IRIs of the Directly Imported Ontology Documents
% This section specifies the result of step CP-2.2 of the canonical parsing process on an RDF graph G

% 3.1.2 Parsing of the Ontology Header and Declarations

owl_parse_axiom(ontology(O)) :-
        use_owl(O,'rdf:type','owl:Ontology'),
        nb_setval(current_ontology,O).

owl_parse_axiom(ontologyImport(O,IRI)) :-
        use_owl(O,'owl:imports',IRI).

owl_parse_axiom(ontologyVersionInfo(O,IRI)) :-
        use_owl(O,'owl:versionInfo',IRI).

% See table 5.
% TODO

%% triple_remove(L,T)

% See table 6.
% http://www.w3.org/TR/2008/WD-owl2-mapping-to-rdf-20081202/
triple_replacements(owl(X,'rdf:type','owl:OntologyProperty'),[owl(X,'rdf:type','owl:AnnotationProperty')]).
triple_replacements(owl(X,'rdf:type','owl:InverseFunctionalProperty'),[owl(X,'rdf:type','owl:ObjectProperty'),owl(X,'rdf:type','owl:InverseFunctionalProperty')]).
triple_replacements(owl(X,'rdf:type','owl:TransitiveProperty'),[owl(X,'rdf:type','owl:ObjectProperty'),owl(X,'rdf:type','owl:TransitiveProperty')]).
triple_replacements(owl(X,'rdf:type','owl:SymmetricProperty'),[owl(X,'rdf:type','owl:ObjectProperty'),owl(X,'rdf:type','owl:SymmetricProperty')]).


% DECLARATIONS

% See table 7.
% http://www.w3.org/TR/2008/WD-owl2-mapping-to-rdf-20081202/

owl_parse_axiom(class(C),AnnMode,List) :-
	test_use_owl(C,'rdf:type','owl:Class'),
	valid_axiom_annotation_mode(AnnMode,C,'rdf:type','owl:Class',List),
        (   use_owl(C,'rdf:type','owl:Class',named) ; use_owl(C,'rdf:type','rdfs:Class',named)).

owl_parse_axiom(class(C)) :-
        use_owl([owl(X,'rdf:type','owl:Axiom'),
                 owl(X,'owl:subject',C),
                 owl(X,'owl:predicate','rdf:type'),
                 owl(X,'owl:object','owl:Class')]).

owl_parse_axiom(datatype(D)) :-
        use_owl(D,'rdf:type','rdf:Datatype').
owl_parse_axiom(datatype(C)) :-
        use_owl([owl(X,'rdf:type','owl:Axiom'),
                 owl(X,'owl:subject',C),
                 owl(X,'owl:predicate','rdf:type'),
                 owl(X,'owl:object','owl:Datatype')]).

owl_parse_axiom(objectProperty(D)) :-
        use_owl(D,'rdf:type','owl:ObjectProperty').
owl_parse_axiom(objectProperty(C)) :-
        use_owl([owl(X,'rdf:type','owl:Axiom'),
                 owl(X,'owl:subject',C),
                 owl(X,'owl:predicate','rdf:type'),
                 owl(X,'owl:object','owl:ObjectProperty')]).

% note the difference in names between syntax and rdf
owl_parse_axiom(dataProperty(D)) :-
        use_owl(D,'rdf:type','owl:DatatypeProperty').
owl_parse_axiom(dataProperty(C)) :-
        use_owl([owl(X,'rdf:type','owl:Axiom'),
                 owl(X,'owl:subject',C),
                 owl(X,'owl:predicate','rdf:type'),
                 owl(X,'owl:object','owl:DatatypeProperty')]).

owl_parse_axiom(annotationProperty(D)) :-
        use_owl(D,'rdf:type','owl:AnnotationProperty').
owl_parse_axiom(annotationProperty(C)) :-
        use_owl([owl(X,'rdf:type','owl:Axiom'),
                 owl(X,'owl:subject',C),
                 owl(X,'owl:predicate','rdf:type'),
                 owl(X,'owl:object','owl:AnnotationProperty')]).

owl_parse_axiom(namedIndividual(D)) :-
        use_owl(D,'rdf:type','owl:NamedIndividual').
owl_parse_axiom(namedIndividual(C)) :-
        use_owl([owl(X,'rdf:type','owl:Axiom'),
                 owl(X,'owl:subject',C),
                 owl(X,'owl:predicate','rdf:type'),
                 owl(X,'owl:object','owl:NamedIndividual')]).

% Table 8. Identifying Anonymous Individuals in Reification
% TODO


% 3.2 Populating an Ontology


% 3.2.1 Analyzing Declarations

% 3.2.2 Parsing of Annotations

% 
%       ann(?X, -Extension List)
%       
%       Implements function ANN(x) 3.2.2 Table 10


ann(X,Y) :-
	ann(X,X,Y).


ann(X,X1, annotation(X1,Y,Z)) :-  
	annotationProperty(Y),use_owl(X,Y,Z), 
	% print(annotation(X-Y-Z-X1)),nl,
	u_assert(annotation(X1,Y,Z)),
	ann2(X,Y,Z,X1).


ann2(X,Y,Z,X1) :-
	test_use_owl(W,'rdf:type','owl:Annotation'),
	test_use_owl(W,'owl:subject',X),
	test_use_owl(W,'owl:object',Z),
	use_owl([owl(W,'rdf:type','owl:Annotation'),
		 owl(W,'owl:subject',X),
		 owl(W,'owl:predicate',Y),
		 owl(W,'owl:object',Z)]),
	print(w-W),nl,
	ann(W,annotation(X1,Y,Z),Term),u_assert(Term),
	print('==='-Term),nl.

ann2(_,_,_,_).



% 3.2.4 Parsing of Expressions


% Table 11. Parsing Object Property Expressions

owl_property_expression(C,C) :- 
	not(sub_string(C,0,2,_,'__')). % better: IRI(C).

owl_property_expression(C,D) :- 
	blanknode(C,D,Use),
	(   Use = used, owl_parser_log(C-D), 
	    retractall(blanknode(C,D,used)),
	    assert(blanknode(C,D,shared))
	;
	    true).

owl_property_expression(P,inverseOf(Q)) :-
        use_owl(P,'owl:inverseOf',Q),
        owl_get_bnode(P,inverseOf(Q)).


% Table 12. Parsing of Data Ranges

owl_datarange(D,D) :-
	not(sub_string(D,0,2,_,'__')). % better: IRI(C).

owl_datarange(C,D) :- 
	blanknode(C,D,Use),
	(   Use = used, owl_parser_log(C-D), 
	    retractall(blanknode(C,D,used)),
	    assert(blanknode(C,D,shared))
	;
	true).

owl_datarange(D,intersectionOf(L)) :-
	use_owl(D,'rdf:type','rdfs:Datatype'),
	use_owl(D,'owl:intersectionOf',Y),
        owl_datarange_list(Y,L),
	owl_get_bnode(D,intersectionOf(L)).

owl_datarange(D,unionOf(L)) :-
	use_owl(D,'rdf:type','rdfs:Datatype'),
	use_owl(D,'owl:unionOf',Y),
        owl_datarange_list(Y,L),
	owl_get_bnode(D,unionOf(L)).


owl_datarange(D,complementOf(DY)) :-
	use_owl(D,'rdf:type','rdfs:Datatype'),
	use_owl(D,'owl:datatypeComplementOf',Y),
        owl_datarange(Y,DY),
	owl_get_bnode(D,complementOf(DY)).

% Table 14, case 2
 owl_datarange(D,complementOf('rdfs:Literal')) :-
	use_owl(D,'rdf:type','rdfs:DataRange'),
	use_owl(D,'owl:oneOf',[]),
	owl_get_bnode(D,complementOf('rdfs:Literal')).

owl_datarange(D,oneOf(L)) :- 
	use_owl(D,'rdf:type','rdfs:Datatype'),
	use_owl(D,'owl:oneOf',L1),
	owl_individual_list(L1,L),
	owl_get_bnode(D,oneOf(L)).

% Table 14, case 1
owl_datarange(D,oneOf(L)) :- 
	use_owl(D,'rdf:type','rdfs:DataRange'),
	use_owl(D,'owl:oneOf',L1),
	owl_individual_list(L1,L),
	owl_get_bnode(D,oneOf(L)).

	      
owl_datarange(D,datatypeRestriction(DY,L)) :- 
	use_owl(D,'rdf:type','rdfs:Datatype'),
	use_owl(D,'owl:onDatatype',Y),
	owl_datarange(Y,DY),
	use_owl(D,'owl:withRestrictions',L1),
	owl_datatype_restriction_list(L1,L),
	owl_get_bnode(D,datatypeRestriction(DY,L)).


% Table 13. Parsing of Class Expressions

% ----------------------------------------------------------------------
%       owl_description(+Node,-Description).
%
%	It implements OWL AS production rules for Descriptions.
%       I.e. a Description can be any of
%         - a Class ID 
%	  - an existing blank node (in which case we have structure
%	    sharing),
%         - a unionOf(DescriptionList) term. 
%         - a intersectionOf(DescriptionList) term.
%         - a complementOf(Description) term.
%         - a oneOf(IndividualList) term.
%
%         During the construction of the Description any blank node 
%         is recorded for later structure sharing checks. 

owl_description(C,C) :- 
	not(sub_string(C,0,2,_,'__')).

owl_description(C,D) :- 
	blanknode(C,D,Use),
	(   Use = used, owl_parser_log(C-D), 
	    retractall(blanknode(C,D,used)),
	    assert(blanknode(C,D,shared))
	;
	    true).

owl_description(D,intersectionOf(L)) :- 
	use_owl(D,'owl:intersectionOf',L1),
	owl_description_list(L1,L),
	owl_get_bnode(D,intersectionOf(L)).

owl_description(D,unionOf(L)) :- 
	use_owl(D,'owl:unionOf',L1),
	owl_description_list(L1,L),
	owl_get_bnode(D,unionOf(L)).


owl_description(D,complementOf(Descr)) :- 
	use_owl(D,'owl:complementOf',D1),
	owl_description(D1,Descr),
	owl_get_bnode(D,complementOf(Descr)).

owl_description(D,oneOf(L)) :- 
	use_owl(D,'owl:oneOf',L1),
	owl_individual_list(L1,L),
	owl_get_bnode(D,oneOf(L)).

owl_description(D,Restriction) :- 
	owl_restriction(D, Restriction),
	owl_get_bnode(D,Restriction).

% Table 15 - OWL DL compatibility class expressions
% 
owl_description(D,Result) :-
	use_owl(D,'rdf:type','owl:Class'),
	use_owl(D,'owl:unionOf',L),
	owl_description_list(L,DL),
	(   DL = [], Result = 'owl:Nothing' ;
	    DL = [D1], Result = D1),
	owl_get_bnode(D,Result).

owl_description(D,Result) :-
	use_owl(D,'rdf:type','owl:Class'),
	use_owl(D,'owl:intersectionOf',L),
	owl_description_list(L,DL),
	(   DL = [], Result = 'owl:Thing' ;
	    DL = [D1], Result = D1),
	owl_get_bnode(D,Result).

owl_description(D,Result) :-
	use_owl(D,'rdf:type','owl:Class'),
	use_owl(D,'owl:oneOf',[]),
	Result = 'owl:Nothing',
	owl_get_bnode(D,Result).



%       owl_restriction(+Element,-Restriction).
%
%       If Element is defined as a owl:Restriction on property P then
%       Restriction binds to a restriction(Property,Type) term, 
%	according to OWL Abstract syntax specification.

owl_restriction(Element,Restriction) :- 
	use_owl(Element,'rdf:type','owl:Restriction'),
	(   use_owl(Element, 'owl:onProperty',PropertyID) ;
    	    use_owl(Element, 'owl:onProperties',PropertyID)
	),
	owl_restriction_type(Element,PropertyID, Restriction),	    
        debug(owl_parser_detail,'Restriction: ~w',[Restriction]).



owl_restriction_type(E, P, someValuesFrom(PX, DX)) :- 
	use_owl(E, 'owl:someValuesFrom',D),
	(   owl_description(D, DX) ; owl_datarange(D,DX)),
        (   P = [_|_], owl_property_list(P,PX) ;  owl_property_expression(P, PX)).


owl_restriction_type(E, P, allValuesFrom(PX,DX)) :- 
	use_owl(E, 'owl:allValuesFrom',D),
	(   owl_description(D, DX) ; owl_datarange(D,DX)),
        (   P = [_|_], owl_property_list(P,PX) ;  owl_property_expression(P, PX)).


% changed from thea value-->hasValue
owl_restriction_type(E, P, hasValue(PX,Value)) :- 
	use_owl(E, 'owl:hasValue',Value),
        owl_property_expression(P, PX).

% VV:check if RDF parser returns a triple with O=true for 
% "true"^^xsd:boolean
owl_restriction_type(E, P, hasSelf(PX)) :- 
	use_owl(E, 'owl:hasSelf', true),
        owl_property_expression(P, PX).

% changed from Thea: cardinality->exactCardinality
owl_restriction_type(E, P,exactCardinality(N,PX)) :- 
	use_owl(E, 'owl:cardinality',N),
        owl_property_expression(P, PX).

owl_restriction_type(E, P,exactCardinality(N,PX,DX)) :- 
	use_owl(E, 'owl:qualifiedCardinality',N),
	(   use_owl(E, 'owl:onClass',D),owl_description(D, DX) ; 
	    use_owl(E, 'owl:onDataRange',D), owl_datarange(D,DX)
	),
        owl_property_expression(P, PX).

owl_restriction_type(E, P, minCardinality(N,PX)) :- 
	use_owl(E, 'owl:minCardinality',N),
        owl_property_expression(P, PX).

owl_restriction_type(E, P, minCardinality(N,PX,DX)) :- 
	use_owl(E, 'owl:minQualifiedCardinality',N),
	(   use_owl(E, 'owl:onClass',D),owl_description(D, DX);
	    use_owl(E, 'owl:onDataRange',D), owl_datarange(D,DX)
	),
        owl_property_expression(P, PX).

owl_restriction_type(E, P, maxCardinality(N,PX)) :- 
	use_owl(E, 'owl:maxCardinality',N),
        owl_property_expression(P, PX).

owl_restriction_type(E, P, maxCardinality(N,PX,DX)) :- 
	use_owl(E, 'owl:maxQualifiedCardinality',N),
	(   use_owl(E, 'owl:onClass',D),owl_description(D, DX);
	    use_owl(E, 'owl:onDataRange',D), owl_datarange(D,DX)),
        owl_property_expression(P, PX).


% Table 14. Parsing of Data Ranges for Compatibility with OWL DL
% Included into owl_datarange clauses above

% Table 15. Parsing of Class Expressions for Compatibility with OWL DL
% Included into owl_dexcription clauses above




% Table 16. Parsing of Axioms without Annotations

% Declarations handled previously

% CLASS AXIOMS

% valid_axiom_annotation_mode: add clauses for the disjoint etc ....

valid_axiom_annotation_mode(Mode,S,P,O,List) :-
	findall(Node,(test_use_owl(Node,'rdf:type','owl:Axiom'),
		      test_use_owl(Node,'owl:subject',S),
		      test_use_owl(Node,'owl:predicate',P),
		      test_use_owl(Node,'owl:object',O)),
		List),
	(   Mode = true, List = [_|_],!; Mode = false, List = []),
	forall(member(Node,List), use_owl([owl(Node,'rdf:type','owl:Axiom'),
					   owl(Node,'owl:subject',S),
					   owl(Node,'owl:predicate',P),
					   owl(Node,'owl:object',O)])).
	       

owl_parse_axiom(subClassOf(DX,DY),AnnMode,List) :- 
	test_use_owl(X,'rdfs:subClassOf',Y),
	valid_axiom_annotation_mode(AnnMode,X,'rdfs:subClassOf',Y,List),
	use_owl(X,'rdfs:subClassOf',Y),
        owl_description(X,DX),
	owl_description(Y,DY).

% Process each equivalentClass pair separately in order to capture
% annotations. Block the maximally connected subgraph.
% TODO. Process the equivalent(L) axioms to generate maximally connected 
% equivalentClasses(L) axioms. (but without annotations?)

owl_parse_axiom(equivalentClasses(DL),AnnMode,List) :-
	test_use_owl(X,'owl:equivalentClass',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:equivalentClass',Y,List),
	use_owl(X,'owl:equivalentClass',Y),	
        % maximally_connected_subgraph_over('owl:equivalentClass',L),
        maplist(owl_description,[X,Y],DL),
        debug(owl_parser_detail,'equivalentClasses Descs: ~w',[DL]).

% Clarify with CM: what is this clause for???

owl_parse_axiom(equivalentClasses([C,D])) :-
        % TODO: this could be made more efficient by enforcing order of building
        (   test_use_owl(C,'rdf:type','owl:Class',named)
        ;   test_use_owl(C,'rdf:type','rdfs:Class',named)
        ;   class(C)),
        owl_description(C,D),
        C\=D.


% TODO. Process the disjointClasses(L) axioms to generate
% larger set of disjoint: ie if N classes are pairwise DisJoint
% then we can assert a disjointClasses for all N 
 
owl_parse_axiom(disjointClasses([DX,DY]),AnnMode,List) :- 
	test_use_owl(X,'owl:disjointClass',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:disjointClass',Y,List),
	use_owl(X,'owl:disjointClass',Y),	
        owl_description(X,DX),
	owl_description(Y,DY).

% One of the cases where annotations are those of _x and we do not seek
% for further annotation axioms. Par. 3.2.5. 
% Whatever the AnnNode, _x is returned (will be ignored if mode false

owl_parse_axiom(disjointClasses(L),_AnnMode,[X]) :-
        % TODO: X may be referred to in an annotation axiom??
	use_owl(X,'rdf:type','owl:AllDisjointClasses'),
        use_owl(X,'owl:members',L1),
        owl_description_list(L1,L).


owl_parse_axiom(disjointUnion(DX,DY),AnnMode,List) :- 
	test_use_owl(X,'owl:disjointUnionOf',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:disjointUnionOf',Y,List),
	use_owl(X,'owl:disjointUnionOf',Y),
        owl_description(X,DX),
        owl_description_list(Y,DY).



% PROPERTY AXIOMS


% introduces bnode
owl_parse_axiom(subPropertyOf(propertyChain(PL),QX),AnnMode,List) :-
	test_use_owl(X,'rdfs:subPropertyOf',Q),        
	valid_axiom_annotation_mode(AnnMode,X,'rdfs:subPropertyOf',Q,List),
	use_owl(X,'rdfs:subPropertyOf',Q),
	use_owl(X,'owl:propertyChain',L1),
	owl_property_list(L1,PL),
        owl_property_expression(Q,QX).

owl_parse_axiom(subPropertyOf(PX,QX),AnnMode,List) :-
	test_use_owl(P,'rdfs:subPropertyOf',Q),        
	valid_axiom_annotation_mode(AnnMode,P,'rdfs:subPropertyOf',Q,List),
	use_owl(P,'rdfs:subPropertyOf',Q),       
        owl_property_expression(P,PX),
        owl_property_expression(Q,QX).


% Process each equivalentProperty pair separately in order to capture
% annotations. Block the maximally connected subgraph.
% TODO. Process the equivalent(L) axioms to generate maximally connected 
% equivalentProperties(L) axioms. (but without annotations?)

owl_parse_axiom(equivalentProperties(OPEL),AnnMode,List) :- 	
	test_use_owl(X,'owl:equivalentProperty',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:equivalentProperty',Y,List),
	use_owl(X,'owl:equivalentProperty',Y),	
	% maximally_connected_subgraph_over('owl:equivalentProperty',L),
	maplist(owl_property_expression,[X,Y],OPEL).
	

% TODO. Process the disjointProperties(L) axioms to generate
% larger set of disjoint: ie if N properties are pairwise DisJoint
% then we can assert a disjointClasses for all N 
 
owl_parse_axiom(disjointProperties([DX,DY]),AnnMode,List) :- 
	test_use_owl(X,'owl:propertyDisjointWith',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:propertyDisjointWith',Y,List),
	use_owl(X,'owl:propertyDisjointWith',Y),
        owl_description(X,DX),
	owl_description(Y,DY).

% One more of the cases where annotations are those of _x and we do not
% seek for further annotation axioms. Par. 3.2.5. Whatever the AnnNode,
% _x is returned (will be ignored if mode false)

owl_parse_axiom(disjointProperties(L),_AnnMode,[X]) :-
        % TODO: X may be referred to in an annotation axiom??
	use_owl(X,'rdf:type','owl:AllDisjointProperties'),
        use_owl(X,'owl:members',L1),
        L1 = [_,_|_],           % length >= 2
        owl_property_list(L1,L).


owl_parse_axiom(propertyDomain(PX,CX),AnnMode,List) :-
	test_use_owl(P,'rdfs:domain',C),
	valid_axiom_annotation_mode(AnnMode,P,'rdfs:domain',C,List),
        use_owl(P,'rdfs:domain',C),
	(   annotationProperty(P),CX = C ; 
	    owl_property_expression(P,PX),
	    owl_description(C,CX)
	).

% We need to distinguish here between object and data property
% Currently we first test if the range is a class, this means OPE
% otherwise if it is a datarange it means a DPE.
% Ideally we should also check possible declarations of OPE or DPE.

owl_parse_axiom(propertyRange(PX,CX),AnnMode,List) :-
	test_use_owl(P,'rdfs:range',C),
	valid_axiom_annotation_mode(AnnMode,P,'rdfs:range',C,List),
        use_owl(P,'rdfs:range',C),
	(   annotationProperty(P), CX = C ; 
	    owl_property_expression(P,PX),
            (   owl_description(C,CX) ; owl_datarange(C,CX))
	).


owl_parse_axiom(inverseProperties(PX,QX),AnnMode,List) :-
	test_use_owl(P,'owl:inverseOf',Q),
	valid_axiom_annotation_mode(AnnMode,P,'owl:inverseOf',Q,List),
	use_owl(P,'owl:inverseOf',Q),
        owl_property_expression(P,PX),
        owl_property_expression(Q,QX).


owl_parse_axiom(functionalProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:FunctionalProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:FunctionalProperty',List),	
        use_owl(P,'rdf:type','owl:FunctionalProperty').


owl_parse_axiom(inverseFunctionalProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:InverseFunctionalProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:InverseFunctionalProperty',List),
        use_owl(P,'rdf:type','owl:InverseFunctionalProperty').


owl_parse_axiom(reflexiveProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:ReflexiveProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:ReflexiveProperty',List),	
        use_owl(P,'rdf:type','owl:ReflexiveProperty').

owl_parse_axiom(irreflexiveProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:IrreflexiveProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:IrreflexiveProperty',List),	
        use_owl(P,'rdf:type','owl:IrreflexiveProperty').

owl_parse_axiom(symmetricProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:SymmetricProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:SymmetricProperty',List),	
        use_owl(P,'rdf:type','owl:SymmetricProperty').

owl_parse_axiom(asymmetricProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:AsymmetricProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:AsymmetricProperty',List),		
        use_owl(P,'rdf:type','owl:AsymmetricProperty').

owl_parse_axiom(transitiveProperty(P),AnnMode,List) :-
	test_use_owl(P,'rdf:type','owl:TransitiveProperty'),
	valid_axiom_annotation_mode(AnnMode,P,'rdf:type','owl:TransitiveProperty',List),	
	use_owl(P,'rdf:type','owl:TransitiveProperty').

owl_parse_axiom(hasKey(CX,L),AnnMode,List) :-
	test_use_owl(C,'owl:hasKey',L1),
	valid_axiom_annotation_mode(AnnMode,C,'owl:hasKey',L1,List),	
	use_owl(C,'owl:hasKey',L1),
	owl_description(C,CX),
        L1 = [_,_|_],           % length >= 2
        owl_property_list(L1,L).

% INDIVIDUALS

owl_parse_axiom(sameIndividual(X,Y),AnnMode,List) :-
	test_use_owl(X,'owl:sameAs',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:sameAs',Y,List),
	use_owl(X,'owl:sameAs',Y).


owl_parse_axiom(differentIndividuals([X,Y]),AnnMode,List) :- 
	test_use_owl(X,'owl:differentFrom',Y),
	valid_axiom_annotation_mode(AnnMode,X,'owl:differentFrom',Y,List),
	use_owl(X,'owl:differentFrom',Y).


owl_parse_axiom(differentIndividuals(L),_AnnMode,[X]) :-	
	use_owl(X,'rdf:type','owl:AllDifferent'),
	use_owl(X,'owl:distinctMembers',L1),	
        owl_individual_list(L1,L).

owl_parse_axiom(differentIndividuals(L),_AnnMode,[X]) :-	
	use_owl(X,'rdf:type','owl:AllDifferent'),
	use_owl(X,'owl:memebrs',L1),	
        owl_individual_list(L1,L).


dothislater(classAssertion/3).
owl_parse_axiom(classAssertion(CX,I),AnnMode,List) :-
	test_use_owl(I,'rdf:type',C),
	valid_axiom_annotation_mode(AnnMode,X,'rdf:type',C,List),
	use_owl(X,'rdf:type',C),	
        owl_description(C,CX).


dothislater(propertyAssertion/3).
owl_parse_axiom(propertyAssertion(PX,A,B),AnnMode,List) :-
        test_use_owl(A,P,B), % B can be literal or individual
	valid_axiom_annotation_mode(AnnMode,A,P,B,List),		
        \+ annotationProperty(P), % these triples should have been removed before, during ann parsing
        use_owl(A,P,B),
        owl_property_expression(P,PX). % can also be inverse


owl_parse_axiom(negativePropertyAssertion(PX,A,B),_,X) :-
        use_owl(X,'rdf:type','owl:NegativePropertyAssertion'),
        use_owl(X,'owl:sourceIndividual',A),
        use_owl(X,'owl:assertionProperty',P),
        use_owl(X,'owl:targetValue',B),
        owl_property_expression(P,PX). 


owl_parse_axiom(annotationAssertion('owl:deprecated', X, true),AnnMode,List) :-
	test_use_owl(X, 'rdf:type', 'owl:DeprecatedClass'),
	valid_axiom_annotation_mode(AnnMode,X,'rdf:type','owl:DeprecatedClass',List),
	use_owl(X, 'rdf:type', 'owl:DeprecatedClass').

owl_parse_axiom(annotationAssertion('owl:deprecated', X, true),AnnMode,List) :-
	test_use_owl(X, 'rdf:type', 'owl:DeprecatedProperty'),
	valid_axiom_annotation_mode(AnnMode,X,'rdf:type','owl:DeprecatedProperty',List),
	use_owl(X, 'rdf:type', 'owl:DeprecatedProperty').


	
% Table 17. Parsing of Annotated Axioms


dothislater(annotationAssertion/3).
owl_parse_axiom(annotationAssertion(P,A,B)) :-
        use_owl(A,P,B), % B can be literal or individual
        annotationProperty(P).




% UTIL

%% maximally_connected_subgraph_over(+P,?ConnectedSets) is semidet
maximally_connected_subgraph_over(P,CSet):-
        maximally_connected_subgraph_over(P,[],CSetL),
        member(CSet,CSetL).

%% maximally_connected_subgraph_over(+P,+Used,?ListOfConnectedSets) is det
maximally_connected_subgraph_over(P,Used,[CSet|All]):-
        test_use_owl(X,P,Y), % seed
        \+ member(X,Used),
        \+ member(Y,Used),
        use_owl(X,P,Y), % seed
        !,
        extend_set_over(P,[X,Y],CSet),
        append(CSet,Used,Used2),
        maximally_connected_subgraph_over(P,Used2,All).
maximally_connected_subgraph_over(_,_,[]).


% det
extend_set_over(P,L,L2):-
        member(X,L),
        test_use_owl(X,P,Y),
        \+ member(Y,L),
        use_owl(X,P,Y),
        !,
        extend_set_over(P,[Y|L],L2).
extend_set_over(P,L,L2):-
        member(X,L),
        test_use_owl(Y,P,X),
        \+ member(Y,L),
        use_owl(Y,P,X),
        !,
        extend_set_over(P,[Y|L],L2).
extend_set_over(_,L,L):- !.

	
   	

% 
% go
% 
	
go :- 
	retractall(annotation(_,_,_)),
	retractall(owl(_,_,_,_)),
	retractall(class(_)),
	retractall(subClassOf(_,_)),
	consult('test2.owl'),
	findall(_,ann(_,_),_),
        owl_parse_annotated_axioms(class/1),
	owl_parse_annotated_axioms(subClassOf/2),
	owl_parse_nonannotated_axioms(class/1),
	owl_parse_nonannotated_axioms(subClassOf/2).
	
