-module(home_handler).
-behaviour(cowboy_handler).
-export([init/2]).

init(Req, State) ->
    {ok, BookRows} = wlt_db:q(
        "SELECT id, name, testament FROM books ORDER BY sort_order"
    ),
    Books = [#{id => Id, name => Name} || [Id, Name, _Testament] <- BookRows],
    OtBooks = [B || {[_Id, _Name, <<"OT">>], B} <- lists:zip(BookRows, Books)],
    NtBooks = [B || {[_Id, _Name, <<"NT">>], B} <- lists:zip(BookRows, Books)],
    TeachingsCtx = #{ot_books => OtBooks, nt_books => NtBooks},
    Req2 =
        case wlt_handler:is_htmx(Req) of
            true ->
                wlt_handler:render(Req, "partials/teachings_ot_nt.html", TeachingsCtx);
            false ->
                Ctx = maps:merge(TeachingsCtx, wlt_handler:page_ctx(Req)),
                wlt_handler:render(Req, "home.html", maps:put(title, <<"Welcome">>, Ctx))
        end,
    {ok, Req2, State}.
