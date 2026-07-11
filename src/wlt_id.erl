%%% Small helper for parsing route :id bindings.
-module(wlt_id).
-export([parse/1]).

parse(undefined) -> error;
parse(Bin) when is_binary(Bin) ->
    case string:to_integer(binary_to_list(Bin)) of
        {Int, ""} when is_integer(Int) -> {ok, Int};
        _                              -> error
    end.
