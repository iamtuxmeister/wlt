%%% GET /teachings/teaching/:id - a single teaching (audio + breadcrumb).
-module(teaching_handler).
-behaviour(cowboy_handler).
-export([init/2]).

init(Req, State) ->
    case wlt_id:parse(cowboy_req:binding(id, Req)) of
        {ok, Id}  -> render_teaching(Req, State, Id);
        error     -> {ok, wlt_handler:not_found(Req), State}
    end.

render_teaching(Req, State, Id) ->
    Sql =
        "SELECT t.id, t.title, t.start_chapter, t.end_chapter, "
        "       t.audio_url, t.taught_on, b.id, b.name "
        "FROM teachings t JOIN books b ON b.id = t.book_id "
        "WHERE t.id = ?1",
    case wlt_db:q(Sql, [Id]) of
        {ok, [[TId, Title, StartCh, EndCh, AudioUrl, TaughtOn, BookId, BookName]]} ->
            TeachingCtx = #{
                teaching => #{id => TId, title => Title,
                              start_chapter => StartCh, end_chapter => EndCh,
                              audio_url => AudioUrl, taught_on => TaughtOn},
                book     => #{id => BookId, name => BookName}
            },
            Req2 =
                case wlt_handler:is_htmx(Req) of
                    true ->
                        wlt_handler:render(Req, "partials/teaching_player.html", TeachingCtx);
                    false ->
                        Ctx = maps:merge(TeachingCtx, wlt_handler:page_ctx(Req)),
                        wlt_handler:render(Req, "teaching_page.html",
                                            maps:put(title, Title, Ctx))
                end,
            {ok, Req2, State};
        {ok, []} ->
            {ok, wlt_handler:not_found(Req), State}
    end.
