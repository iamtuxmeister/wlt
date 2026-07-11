%%% Database abstraction layer.
%%% Switch backend in sys.config: {db_backend, sqlite} | {db_backend, postgres}
%%% Public API: init/0, close/0, q/1, q/2, exec/1, exec/2
-module(wlt_db).

-export([init/0, close/0, q/1, q/2, exec/1, exec/2]).

init() ->
    case backend() of
        sqlite   -> init_sqlite();
        postgres -> init_postgres()
    end.

close() ->
    case backend() of
        sqlite   -> esqlite3:close(conn());
        postgres -> ok
    end.

q(Sql)         -> q(Sql, []).
q(Sql, Params) ->
    case backend() of
        sqlite   -> sqlite_q(Sql, Params);
        postgres -> {error, postgres_not_configured}
    end.

exec(Sql)         -> exec(Sql, []).
exec(Sql, Params) ->
    case backend() of
        sqlite   -> sqlite_exec(Sql, Params);
        postgres -> {error, postgres_not_configured}
    end.

%% --- SQLite ----------------------------------------------------------------

init_sqlite() ->
    {ok, Cfg} = application:get_env(wlt, sqlite),
    Path = proplists:get_value(path, Cfg, "priv/db/wlt.db"),
    ok   = filelib:ensure_dir(Path),
    {ok, Db} = esqlite3:open(Path),
    persistent_term:put({wlt_db, conn}, Db),
    run_migrations(Db),
    ok.

conn() -> persistent_term:get({wlt_db, conn}).

sqlite_q(Sql, Params) ->
    case esqlite3:q(conn(), Sql, Params) of
        Rows when is_list(Rows) -> {ok, Rows};
        {error, _} = E          -> E
    end.

sqlite_exec(Sql, []) ->
    case esqlite3:exec(conn(), Sql) of
        ok             -> ok;
        {error, _} = E -> E
    end;
sqlite_exec(Sql, Params) ->
    case esqlite3:q(conn(), Sql, Params) of
        Rows when is_list(Rows) -> ok;
        {error, _} = E          -> E
    end.

%% --- PostgreSQL stub -------------------------------------------------------
%% Uncomment epgsql + poolboy in rebar.config, set {db_backend, postgres}
%% in sys.config, then implement myapp_pg_worker.erl.

init_postgres() ->
    error(postgres_backend_not_configured).

%% --- Migrations ------------------------------------------------------------

run_migrations(Db) ->
    esqlite3:exec(Db,
        "CREATE TABLE IF NOT EXISTS schema_migrations ("
        "  version TEXT PRIMARY KEY,"
        "  applied_at TEXT DEFAULT (datetime('now'))"
        ");"),
    lists:foreach(fun({Vsn, Sql}) ->
        Rows = esqlite3:q(Db,
            "SELECT version FROM schema_migrations WHERE version = ?1",
            [Vsn]),
        case Rows of
            [] ->
                ok = esqlite3:exec(Db, Sql),
                esqlite3:q(Db,
                    "INSERT INTO schema_migrations (version) VALUES (?1)",
                    [Vsn]),
                error_logger:info_msg("[db] Applied migration: ~s~n", [Vsn]);
            _ -> ok
        end
    end, migrations()).

migrations() ->
    [
        {"20240101_001_create_example",
         "CREATE TABLE IF NOT EXISTS example ("
         "  id         INTEGER PRIMARY KEY AUTOINCREMENT,"
         "  name       TEXT NOT NULL,"
         "  created_at TEXT DEFAULT (datetime('now'))"
         ");"},
        {"20260710_002_create_books",
         "CREATE TABLE IF NOT EXISTS books ("
         "  id         INTEGER PRIMARY KEY,"
         "  name       TEXT NOT NULL,"
         "  testament  TEXT NOT NULL CHECK (testament IN ('OT','NT')),"
         "  sort_order INTEGER NOT NULL"
         ");"},
        {"20260710_003_seed_books", seed_books_sql()},
        {"20260710_004_create_teachings",
         "CREATE TABLE IF NOT EXISTS teachings ("
         "  id            INTEGER PRIMARY KEY AUTOINCREMENT,"
         "  book_id       INTEGER NOT NULL REFERENCES books(id),"
         "  start_chapter INTEGER NOT NULL,"
         "  end_chapter   INTEGER NOT NULL,"
         "  title         TEXT NOT NULL,"
         "  audio_url     TEXT NOT NULL,"
         "  taught_on     TEXT"
         ");"}
        %% Add new migrations here:
        %% {"20240102_002_add_notes",
        %%  "ALTER TABLE example ADD COLUMN notes TEXT;"}
    ].

%% Canonical 66 books, seeded from the `old`/`new` book-name lists.
seed_books_sql() ->
    OldTestament = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1st Samuel", "2nd Samuel",
        "1st Kings", "2nd Kings", "1st Chronicles", "2nd Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
        "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
        "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah",
        "Haggai", "Zechariah", "Malachi"
    ],
    NewTestament = [
        "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
        "1st Corinthians", "2nd Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "1st Thessalonians",
        "2nd Thessalonians", "1st Timothy", "2nd Timothy", "Titus",
        "Philemon", "Hebrews", "James", "1st Peter", "2nd Peter",
        "1st John", "2nd John", "3rd John", "Jude", "Revelation"
    ],
    Rows = lists:zip(lists:seq(1, length(OldTestament)), OldTestament)
        ++ lists:zip(lists:seq(length(OldTestament) + 1,
                                length(OldTestament) + length(NewTestament)),
                      NewTestament),
    Values = [io_lib:format("(~b, '~s', '~s', ~b)",
                             [Id, escape_sql(Name),
                              testament_for(Id, length(OldTestament)), Id])
              || {Id, Name} <- Rows],
    lists:flatten([
        "INSERT INTO books (id, name, testament, sort_order) VALUES ",
        string:join(Values, ", "),
        ";"
    ]).

testament_for(Id, OtCount) when Id =< OtCount -> "OT";
testament_for(_Id, _OtCount)                  -> "NT".

escape_sql(Str) ->
    lists:flatten(string:replace(Str, "'", "''", all)).

backend() ->
    application:get_env(wlt, db_backend, sqlite).
