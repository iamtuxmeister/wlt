%%% Bulk-import teaching audio from a directory tree of .mp3 files.
%%%
%%% Run from `rebar3 shell` (after the app has started, so wlt_db is up):
%%%   wlt_import:import_dir("/home/ks/Sources/Audio").
%%%
%%% The book for each file is determined from the *filename text* via an
%%% alias table, not from which directory it happens to sit in -- some of
%%% the source directories mix in files that actually belong to a different
%%% book (e.g. the "Ezra" directory contains files titled "Esther ...").
%%%
%%% For each matched file:
%%%   - the chapter/verse text after the matched book alias becomes the
%%%     `descriptor`; the first number found in it is `start_chapter`
%%%     (used for sorting), the last is `end_chapter`
%%%   - title is rebuilt as "{Canonical Book Name} {descriptor}"
%%%   - the source file is copied to
%%%     priv/static/audio/<book-slug>/<descriptor-slug>.mp3
%%%   - a row is inserted into `teachings`, skipped if that audio_url
%%%     already exists (safe to re-run)
%%%   - anything that can't be matched to a book, or has no chapter number,
%%%     is recorded as a warning instead of guessed
-module(wlt_import).
-export([import_dir/1]).

-define(AUDIO_ROOT, "priv/static/audio").

import_dir(Root) ->
    Files = [F || F <- filelib:wildcard(filename:join([Root, "**", "*.mp3"])),
                  filelib:is_regular(F)],
    Aliases = sorted_aliases(),
    {ok, ExistingRows} = wlt_db:q("SELECT audio_url FROM teachings"),
    PreExisting = sets:from_list([U || [U] <- ExistingRows]),
    {_Seen, Imported, Skipped, Warnings} =
        lists:foldl(fun(File, Acc) -> import_file(File, Aliases, PreExisting, Acc) end,
                     {PreExisting, 0, 0, []}, Files),
    io:format("~n~b imported, ~b skipped as duplicates (already imported), "
              "~b warning(s)~n", [Imported, Skipped, length(Warnings)]),
    lists:foreach(fun(W) -> io:format("  WARNING: ~s~n", [W]) end,
                  lists:reverse(Warnings)),
    ok.

import_file(File, Aliases, PreExisting, {Seen, Imported, Skipped, Warnings}) ->
    Name = filename:basename(File, ".mp3"),
    case match_book(Name, Aliases) of
        {ok, DbName, Descriptor} ->
            %% No chapter number in the filename means a single-chapter book
            %% (Jude, Philemon, Obadiah, 2/3 John) or an intro clip -- default
            %% to chapter 0 rather than flagging as a warning.
            {StartCh, EndCh} = case chapters(Descriptor) of
                {ok, S, E} -> {S, E};
                error       -> {0, 0}
            end,
            Title = case Descriptor of
                <<>> -> unicode:characters_to_binary(DbName);
                _    -> iolist_to_binary([DbName, " ", Descriptor])
            end,
            BookSlug = slugify(DbName),
            BaseSlug = case slugify(unicode:characters_to_list(Descriptor)) of
                ""  -> "0";
                Slg -> Slg
            end,
            PlainUrl = iolist_to_binary(
                ["/static/audio/", BookSlug, "/", BaseSlug, ".mp3"]),
            IsPreExisting = sets:is_element(PlainUrl, PreExisting),
            IsSeenThisRun = sets:is_element(PlainUrl, Seen),
            if
                IsPreExisting ->
                    %% Already imported by a previous run of this script.
                    {Seen, Imported, Skipped + 1, Warnings};
                IsSeenThisRun ->
                    %% Two different source files produce the same book +
                    %% chapter/verse slug within this run -- can't tell
                    %% which is "correct", so surface it instead of
                    %% silently keeping one or overwriting the other.
                    W = io_lib:format(
                        "duplicate slug within this run, kept the first "
                        "and skipped: ~s", [File]),
                    {Seen, Imported, Skipped, [W | Warnings]};
                true ->
                    AudioUrl = copy_audio(File, BookSlug, BaseSlug),
                    ok = insert_teaching(DbName, StartCh, EndCh, Title, AudioUrl),
                    {sets:add_element(PlainUrl, Seen), Imported + 1, Skipped, Warnings}
            end;
        error ->
            W = io_lib:format("no book match: ~s", [File]),
            {Seen, Imported, Skipped, [W | Warnings]}
    end.

%% --- Book matching -----------------------------------------------------

match_book(Name, Aliases) ->
    LowerName = string:lowercase(list_to_binary(Name)),
    match_book(LowerName, list_to_binary(Name), Aliases).

match_book(_LowerName, _OrigName, []) ->
    error;
match_book(LowerName, OrigName, [{Alias, DbName} | Rest]) ->
    LowerAlias = string:lowercase(list_to_binary(Alias)),
    case binary:match(LowerName, LowerAlias) of
        {Start, Len} ->
            After = binary:part(OrigName, Start + Len,
                                 byte_size(OrigName) - Start - Len),
            Descriptor = trim_descriptor(After),
            {ok, DbName, Descriptor};
        nomatch ->
            match_book(LowerName, OrigName, Rest)
    end.

trim_descriptor(Bin) ->
    Str = unicode:characters_to_list(Bin),
    Trimmed = string:trim(Str, both, " \t,-.&"),
    list_to_binary(Trimmed).

%% Longest alias first, so e.g. "1 John" is tried before the bare "John".
sorted_aliases() ->
    lists:sort(fun({A, _}, {B, _}) -> byte_size(list_to_binary(A)) >=
                                       byte_size(list_to_binary(B)) end,
               aliases()).

aliases() ->
    [
        {"Genesis", "Genesis"}, {"Exodus", "Exodus"},
        {"Leviticus", "Leviticus"}, {"Levitcus", "Leviticus"},
        {"Numbers", "Numbers"}, {"Deuteronomy", "Deuteronomy"},
        {"Joshua", "Joshua"}, {"Judges", "Judges"}, {"Ruth", "Ruth"},
        {"1 Samuel", "1st Samuel"}, {"1 Sam", "1st Samuel"},
        {"2 Samuel", "2nd Samuel"}, {"2 Sam", "2nd Samuel"},
        {"1 Kings", "1st Kings"}, {"2 Kings", "2nd Kings"},
        {"1 Chronicles", "1st Chronicles"}, {"2 Chronicles", "2nd Chronicles"},
        {"Ezra", "Ezra"}, {"Nehemiah", "Nehemiah"}, {"Esther", "Esther"},
        {"Job", "Job"}, {"Psalm", "Psalms"}, {"Proverbs", "Proverbs"},
        {"Ecclesiastes", "Ecclesiastes"}, {"Song of Solomon", "Song of Solomon"},
        {"Isaiah", "Isaiah"}, {"Jeremiah", "Jeremiah"}, {"Jeremaiah", "Jeremiah"},
        {"Lamentations", "Lamentations"}, {"Ezekiel", "Ezekiel"},
        {"Daniel", "Daniel"}, {"Hosea", "Hosea"}, {"Joel", "Joel"},
        {"Amos", "Amos"}, {"Obadiah", "Obadiah"}, {"Jonah", "Jonah"},
        {"Micah", "Micah"}, {"Nahum", "Nahum"}, {"Habakkuk", "Habakkuk"},
        {"Zephaniah", "Zephaniah"}, {"Haggai", "Haggai"},
        {"Zechariah", "Zechariah"}, {"Malachi", "Malachi"},
        {"Matthew", "Matthew"}, {"Mark", "Mark"}, {"Luke", "Luke"},
        {"1 John", "1st John"}, {"2 John", "2nd John"}, {"3 John", "3rd John"},
        {"John", "John"}, {"Acts", "Acts"}, {"Romans", "Romans"},
        {"1 Corinthians", "1st Corinthians"}, {"2 Corinthians", "2nd Corinthians"},
        {"Galatians", "Galatians"}, {"Ephesians", "Ephesians"},
        {"Philippians", "Philippians"}, {"Colossians", "Colossians"},
        {"1 Thessalonians", "1st Thessalonians"},
        {"2 Thessalonians", "2nd Thessalonians"},
        {"1 Timothy", "1st Timothy"}, {"2 Timothy", "2nd Timothy"},
        {"Titus", "Titus"}, {"Philemon", "Philemon"}, {"Hebrews", "Hebrews"},
        {"James", "James"}, {"1 Peter", "1st Peter"}, {"2 Peter", "2nd Peter"},
        {"Jude", "Jude"}, {"Revelation", "Revelation"}
    ].

%% --- Chapter parsing -----------------------------------------------------

chapters(Descriptor) ->
    case re:run(Descriptor, "[0-9]+", [global, {capture, all, list}]) of
        {match, Matches} ->
            Numbers = [list_to_integer(N) || [N] <- Matches],
            {ok, hd(Numbers), lists:last(Numbers)};
        nomatch ->
            error
    end.

%% --- Audio file copy -----------------------------------------------------

copy_audio(SourceFile, BookSlug, BaseSlug) ->
    Dir = filename:join([?AUDIO_ROOT, BookSlug]),
    ok = filelib:ensure_dir(filename:join(Dir, "x")),
    TargetFile = filename:join(Dir, BaseSlug ++ ".mp3"),
    {ok, _} = file:copy(SourceFile, TargetFile),
    iolist_to_binary(["/static/audio/", BookSlug, "/", BaseSlug, ".mp3"]).

slugify(Str) ->
    Lower = string:lowercase(Str),
    {ok, Re} = re:compile("[^a-z0-9]+"),
    Replaced = re:replace(Lower, Re, "-", [global, {return, list}]),
    string:trim(Replaced, both, "-").

%% --- DB insert -----------------------------------------------------------

insert_teaching(DbName, StartCh, EndCh, Title, AudioUrl) ->
    {ok, BookRows} = wlt_db:q("SELECT id FROM books WHERE name = ?1", [DbName]),
    case BookRows of
        [[BookId]] ->
            wlt_db:exec(
                "INSERT INTO teachings "
                "(book_id, start_chapter, end_chapter, title, audio_url) "
                "VALUES (?1, ?2, ?3, ?4, ?5)",
                [BookId, StartCh, EndCh, Title, AudioUrl]),
            ok;
        [] ->
            error({unknown_book, DbName})
    end.
