% Nitrogen Web Framework for Erlang
% Copyright (c) 2008-2009 Rusty Klophaus
% See MIT-LICENSE for licensing information.

-module (wf_render_elements).
-include ("wf.inc").
-export ([
	render_elements/2,
	temp_id/0,
	to_html_id/1
]).

% render_elements(Elements, Context) - {ok, Html, NewContext}
% Render the elements in Context#context.elements
% Return the HTML that was produced, and the new context holding actions.
render_elements(Elements, Context) ->
	{ok, HtmlAcc, NewContext} = render_elements(Elements, [], Context),
	{ok, HtmlAcc, NewContext}.

% render_elements(Elements, HtmlAcc, Context) -> {ok, Html, NewContext}.
render_elements(S, HtmlAcc, Context) when S == undefined orelse S == []  ->
	{ok, HtmlAcc, Context};
	
render_elements(S, HtmlAcc, Context) when is_binary(S) orelse ?IS_STRING(S) ->
	{ok, [S|HtmlAcc], Context};

render_elements(Elements, HtmlAcc, Context) when is_list(Elements) ->
	F = fun(X, {ok, HAcc, Cx}) ->
		render_elements(X, HAcc, Cx)
	end,
	{ok, Html, NewContext} = lists:foldl(F, {ok, [], Context}, Elements),
	HtmlAcc1 = [lists:reverse(Html)|HtmlAcc],
	{ok, HtmlAcc1, NewContext};
	
render_elements(Element, HtmlAcc, Context) when is_tuple(Element) ->
	{ok, Html, NewContext} = render_element(Element, Context),
	HtmlAcc1 = [Html|HtmlAcc],
	{ok, HtmlAcc1, NewContext};
	
render_elements(script, HtmlAcc, Context) ->
	HtmlAcc1 = [script|HtmlAcc],
	{ok, HtmlAcc1, Context};
	
render_elements(Unknown, _HtmlAcc, _Context) ->
	throw({unanticipated_case_in_render_elements, Unknown}).
	
% This is a Nitrogen element, so render it.
render_element(Element, Context) when is_tuple(Element) ->
	% Get the element's backing module...
	Base = wf_utils:get_elementbase(Element),
	Module = Base#elementbase.module, 
	
	% Verify that this is an element...
	case Base#elementbase.is_element == is_element of
		true -> ok;
		false -> throw({not_an_element, Element})
	end,

	% Set the element ID if it is not already set...
	ID = case Base#elementbase.id of
		undefined -> wf:temp_id();
		Other -> wf:to_list(Other)
	end,
	CurrentPath = [wf:to_list(ID)|Context#context.current_path],
	HtmlID = to_html_id([ID|Context#context.current_path]),
	
	% Update the base element with the new id...
	Base1 = Base#elementbase {id = ID},
	Element1 = wf_utils:replace_with_base(Base1, Element),
		
	% Push the new path into our list of dom_paths...
	DomPaths = Context#context.dom_paths,
	Context1 = Context#context { dom_paths=[CurrentPath|DomPaths] },
	
	case {Base1#elementbase.show_if, is_temp_element(ID)} of
		{true, true} -> 			
			% This is a temp element. Don't update the current path, it should use the parent path.
			% Wire the actions, render the element...
			{ok, Context2} = wff:wire(ID, Base1#elementbase.actions, Context1),
		 	{ok, _Html, _Context3} = call_element_render(Module, HtmlID, Element1, Context2);

		{true, false} -> 
			% This is a named element. Update the current path.
			OldPath = Context#context.current_path,
			Context2 = Context1#context { current_path=CurrentPath },
	
			% Wire the actions, render the element...
			{ok, Context3} = wff:wire(me, Base1#elementbase.actions, Context2),
			{ok, Html, Context4} = call_element_render(Module, HtmlID, Element1, Context3),
					
			% Restore the old path...
			Context5 = Context4#context { current_path=OldPath },
			{ok, Html, Context5};
			
		{_, _} -> 
			{ok, [], Context}
	end.
	
% call_element_render(Module, Context, HtmlID, Element) -> {ok, Html, NewContext}.
% Calls the render_element/3 function of an element to turn an element record into
% HTML.
call_element_render(Module, HtmlID, Element, Context) ->
	{module, Module} = code:ensure_loaded(Module),
	case erlang:function_exported(Module, render_element, 3) of
		true  -> call_element_render_with_context(Module, HtmlID, Element, Context);
		false -> call_element_render_without_context(Module, HtmlID, Element, Context)
	end.

% Call render_element in functional style, explicitly passing in the context.	
call_element_render_with_context(Module, HtmlID, Element, Context) ->
	% Render the new elements into HTML, this could produce even more actions.
	{ok, NewElements, Context1} = erlang:apply(Module, render_element, [HtmlID, Element, Context]),
	{ok, _Html, _Context2} = render_elements(NewElements, [], Context1).
	
% Call render_element in the old style, storing context in process dictionary.
call_element_render_without_context(Module, HtmlID, Element, Context) ->
	put(context, Context),
	NewElements = erlang:apply(Module, render_element, [HtmlID, Element]),
	Context1 = get(context),
	{ok, _Html, _Context2} = render_elements(NewElements, [], Context1).

to_html_id(P) ->
	P1 = lists:reverse(P),
	string:join(P1, "__").
	
temp_id() ->
	{_, _, C} = now(), 
	"temp" ++ integer_to_list(C).

is_temp_element(undefined) -> true;
is_temp_element([P]) -> is_temp_element(P);
is_temp_element(P) -> 
	Name = wf:to_list(P),
	length(Name) > 4 andalso
	lists:nth(1, Name) == $t andalso
	lists:nth(2, Name) == $e andalso
	lists:nth(3, Name) == $m andalso
	lists:nth(4, Name) == $p.