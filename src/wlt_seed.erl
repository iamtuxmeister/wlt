%%% Seed teachings from a CSV file.
%%%
%%% Run from `rebar3 shell` (after the app has started, so wlt_db is up):
%%%   wlt_seed:seed_teachings("priv/seed/teachings.csv").
%%%
%%% CSV columns (no header row), one teaching per line:
%%%   book_name,start_chapter,end_chapter,title,audio_filename,taught_on
%%%
%%% - book_name must match a row in the `books` table (case-insensitive).
%%% - audio_filename is relative to priv/static/audio/, e.g. "mark-01.mp3";
%%%   it's stored as the full "/static/audio/<file>" URL.
%%% - taught_on is a free-form date string (e.g. "2018-03-11"), or blank.
-module(wlt_seed).
-export([seed_teachings/1]).

seed_teachings(Path) ->
    {ok, Bin} = file:read_file(Path),
    Lines = [L || L <- binary:split(Bin, [<<"\n">>, <<"\r\n">>], [global]),
                  L =/= <<>>],
    Results = [seed_line(L) || L <- Lines],
    Ok    = length([ok || ok <- Results]),
    Error = Results -- lists:duplicate(Ok, ok),
    io:format("Seeded ~b teaching(s), ~b error(s)~n", [Ok, length(Error)]),
    [io:format("  ~p~n", [E]) || E <- Error],
    ok.

seed_line(Line) ->
    case binary:split(Line, <<",">>, [global]) of
        [BookName, StartCh, EndCh, Title, AudioFile, TaughtOn] ->
            insert_teaching(trim(BookName), StartCh, EndCh,
                             trim(Title), trim(AudioFile), trim(TaughtOn));
        [BookName, StartCh, EndCh, Title, AudioFile] ->
            insert_teaching(trim(BookName), StartCh, EndCh,
                             trim(Title), trim(AudioFile), <<>>);
        _ ->
            {error, {malformed_line, Line}}
    end.

insert_teaching(BookName, StartChBin, EndChBin, Title, AudioFile, TaughtOn) ->
    case wlt_db:q("SELECT id FROM books WHERE lower(name) = lower(?1)",
                  [BookName]) of
        {ok, [[BookId]]} ->
            StartCh  = binary_to_integer(StartChBin),
            EndCh    = binary_to_integer(EndChBin),
            AudioUrl = <<"/static/audio/", AudioFile/binary>>,
            wlt_db:exec(
                "INSERT INTO teachings "
                "(book_id, start_chapter, end_chapter, title, audio_url, taught_on) "
                "VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                [BookId, StartCh, EndCh, Title, AudioUrl, TaughtOn]),
            ok;
        {ok, []} ->
            {error, {unknown_book, BookName}}
    end.

trim(Bin) -> list_to_binary(string:trim(binary_to_list(Bin))).
