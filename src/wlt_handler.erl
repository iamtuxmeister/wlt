%%% Shared handler utilities.
%%% myapp_handler:render(Req, "home.html", #{title => <<"Home">>})
%%% myapp_handler:reply_json(Req, 200, #{ok => true})
%%% myapp_handler:not_found(Req)
-module(wlt_handler).

-export([render/3, reply_json/3, reply_error/3, not_found/1, base_ctx/1,
         page_ctx/1, is_htmx/1]).

render(Req, Template, Ctx) ->
    Mod     = wlt_templates:template_module(
                  filename:join(["priv/templates", Template])),
    FullCtx = maps:merge(base_ctx(Req), Ctx),
    case Mod:render(FullCtx) of
        {ok, Iolist} ->
            cowboy_req:reply(200,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                Iolist, Req);
        {error, Reason} ->
            error_logger:error_msg("[handler] template ~p error: ~p~n",
                                   [Template, Reason]),
            reply_error(Req, 500, <<"Template rendering failed">>)
    end.

reply_json(Req, Status, Data) ->
    cowboy_req:reply(Status,
        #{<<"content-type">> => <<"application/json; charset=utf-8">>},
        jsone:encode(Data), Req).

reply_error(Req, Status, Message) ->
    case error_dtl:render(#{status => Status, message => Message}) of
        {ok, Html} ->
            cowboy_req:reply(Status,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                Html, Req);
        _ ->
            cowboy_req:reply(Status,
                #{<<"content-type">> => <<"text/plain">>},
                Message, Req)
    end.

not_found(Req) -> reply_error(Req, 404, <<"Page not found">>).

base_ctx(Req) ->
    {Y, _, _} = date(),
    #{path     => cowboy_req:path(Req),
      app_name => <<"wlt">>,
      year     => integer_to_binary(Y)}.

%% Shared context needed by every full-page shell (home.html, book_page.html,
%% teaching_page.html), since all three include partials/contact.html.
page_ctx(Req) ->
    {ok, RecaptchaCfg} = application:get_env(wlt, recaptcha),
    SiteKey = proplists:get_value(site_key, RecaptchaCfg),
    QsVals = cowboy_req:parse_qs(Req),
    ContactStatus = proplists:get_value(<<"contact">>, QsVals, <<>>),
    #{recaptcha_key  => SiteKey,
      contact_status => ContactStatus}.

%% Whether this request came from an htmx-driven swap (as opposed to a
%% direct load/refresh/shared link), per htmx's "HX-Request" header.
is_htmx(Req) ->
    cowboy_req:header(<<"hx-request">>, Req) =:= <<"true">>.
