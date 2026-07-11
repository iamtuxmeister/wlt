%%% GET /teachings/book/:id - a single book with its list of teachings.
-module(book_handler).
-behaviour(cowboy_handler).
-export([init/2]).

init(Req, State) ->
    case wlt_id:parse(cowboy_req:binding(id, Req)) of
        {ok, Id}  -> render_book(Req, State, Id);
        error     -> {ok, wlt_handler:not_found(Req), State}
    end.

render_book(Req, State, Id) ->
    case wlt_db:q("SELECT id, name FROM books WHERE id = ?1", [Id]) of
        {ok, [[BookId, Name]]} ->
            {ok, Rows} = wlt_db:q(
                "SELECT id, start_chapter, end_chapter, title "
                "FROM teachings WHERE book_id = ?1 ORDER BY start_chapter, id",
                [Id]),
            Teachings = [#{id => Tid, start_chapter => StartCh,
                           end_chapter => EndCh, title => Title}
                         || [Tid, StartCh, EndCh, Title] <- Rows],
            BookCtx = #{book => #{id => BookId, name => Name},
                        teachings => Teachings},
            Req2 =
                case wlt_handler:is_htmx(Req) of
                    true ->
                        wlt_handler:render(Req, "partials/book_teachings.html", BookCtx);
                    false ->
                        Ctx = maps:merge(BookCtx, wlt_handler:page_ctx(Req)),
                        wlt_handler:render(Req, "book_page.html",
                                            maps:put(title, Name, Ctx))
                end,
            {ok, Req2, State};
        {ok, []} ->
            {ok, wlt_handler:not_found(Req), State}
    end.
