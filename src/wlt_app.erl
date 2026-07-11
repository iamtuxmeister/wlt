-module(wlt_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    {ok, Env} = application:get_env(wlt, http),
    Port = proplists:get_value(port, Env, 8080),

    ok = wlt_templates:compile_all(),
    ok = wlt_db:init(),

    Dispatch = cowboy_router:compile([
        {'_', [
            {"/",                       home_handler,     []},
            {"/contact",                contact_handler,  []},
            {"/teachings/book/:id",     book_handler,      []},
            {"/teachings/teaching/:id", teaching_handler,  []},
            {"/static/[...]",           cowboy_static,     {priv_dir, wlt, "static"}}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(http_listener,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),

    error_logger:info_msg("wlt started on port ~p~n", [Port]),
    wlt_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(http_listener),
    wlt_db:close(),
    ok.
