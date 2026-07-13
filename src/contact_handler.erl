%%% POST /contact - verify reCAPTCHA v3, then relay the message via the
%%% local MTA's `sendmail` binary. Redirects back to "/?contact=sent#contact"
%%% or "/?contact=error#contact" so home_handler can show a status banner.
-module(contact_handler).
-behaviour(cowboy_handler).
-export([init/2]).

init(Req, State) ->
    case cowboy_req:method(Req) of
        <<"POST">> -> handle_post(Req, State);
        _          -> {ok, cowboy_req:reply(405, Req), State}
    end.

handle_post(Req, State) ->
    {ok, Fields, Req1} = cowboy_req:read_urlencoded_body(Req),
    FirstName = field(<<"first_name">>, Fields),
    LastName  = field(<<"last_name">>, Fields),
    FromEmail = field(<<"from_email">>, Fields),
    Message   = field(<<"message">>, Fields),
    Token     = field(<<"recaptcha_token">>, Fields),
    RemoteIp  = client_ip(Req1),
    Result =
        case verify_recaptcha(Token, RemoteIp) of
            true  -> send_mail(FirstName, LastName, FromEmail, Message);
            false ->
                error_logger:error_msg("[contact] recaptcha verification failed~n"),
                {error, recaptcha_failed}
        end,
    Status = case Result of ok -> <<"sent">>; {error, _} -> <<"error">> end,
    Req2 = cowboy_req:reply(303, #{
        <<"location">> => <<"/?contact=", Status/binary, "#contact">>
    }, Req1),
    {ok, Req2, State}.

field(Name, Fields) -> proplists:get_value(Name, Fields, <<>>).

client_ip(Req) ->
    case cowboy_req:header(<<"x-real-ip">>, Req) of
        undefined ->
            {Ip, _Port} = cowboy_req:peer(Req),
            list_to_binary(inet:ntoa(Ip));
        RealIp ->
            RealIp
    end.

%% --- reCAPTCHA v3 verification -------------------------------------------

verify_recaptcha(<<>>, _RemoteIp) ->
    false;
verify_recaptcha(Token, RemoteIp) ->
    {ok, Cfg} = application:get_env(wlt, recaptcha),
    Secret   = proplists:get_value(secret_key, Cfg),
    MinScore = proplists:get_value(min_score, Cfg, 0.5),
    Body = uri_string:compose_query([
        {"secret", binary_to_list(Secret)},
        {"response", binary_to_list(Token)},
        {"remoteip", binary_to_list(RemoteIp)}
    ]),
    HttpOpts = [{ssl, [
        {verify, verify_peer},
        {cacerts, public_key:cacerts_get()},
        {depth, 3},
        {customize_hostname_check,
         [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}
    ]}],
    %% "connection: close" avoids reusing a pooled keep-alive connection to
    %% Google, which has been observed to occasionally trigger a noisy (but
    %% harmless) ssl connection-supervisor crash report on reuse.
    Request = {"https://www.google.com/recaptcha/api/siteverify",
               [{"connection", "close"}],
               "application/x-www-form-urlencoded", Body},
    case httpc:request(post, Request, HttpOpts, []) of
        {ok, {{_, 200, _}, _Headers, RespBody}} ->
            check_response(RespBody, MinScore);
        Other ->
            error_logger:error_msg(
                "[contact] recaptcha siteverify request failed: ~p~n", [Other]),
            false
    end.

check_response(RespBody, MinScore) ->
    try jsone:decode(iolist_to_binary(RespBody)) of
        Json ->
            Success    = maps:get(<<"success">>, Json, false),
            Score      = maps:get(<<"score">>, Json, 0.0),
            ErrorCodes = maps:get(<<"error-codes">>, Json, []),
            Hostname   = maps:get(<<"hostname">>, Json, undefined),
            error_logger:info_msg(
                "[contact] recaptcha result: success=~p score=~p (min ~p) "
                "hostname=~p error-codes=~p~n",
                [Success, Score, MinScore, Hostname, ErrorCodes]),
            Success =:= true andalso Score >= MinScore
    catch
        _:_ ->
            error_logger:error_msg(
                "[contact] recaptcha response was not valid JSON: ~p~n",
                [RespBody]),
            false
    end.

%% --- Mail delivery via the local MTA's sendmail --------------------------

send_mail(FirstName, LastName, FromEmail, Message) ->
    {ok, Cfg} = application:get_env(wlt, contact),
    SendmailPath = proplists:get_value(sendmail_path, Cfg, "/usr/sbin/sendmail"),
    ToEmail   = proplists:get_value(to_email, Cfg),
    FromAddr  = proplists:get_value(from_email, Cfg),
    Name      = header_safe(<<FirstName/binary, " ", LastName/binary>>),
    ReplyTo   = header_safe(FromEmail),
    Subject   = <<"Website contact form: ", Name/binary>>,
    Mail = iolist_to_binary([
        "To: ", ToEmail, "\r\n",
        "From: ", FromAddr, "\r\n",
        "Reply-To: ", ReplyTo, "\r\n",
        "Subject: ", Subject, "\r\n",
        "Content-Type: text/plain; charset=utf-8\r\n",
        "\r\n",
        "Name: ", Name, "\r\n",
        "Email: ", ReplyTo, "\r\n",
        "\r\n",
        Message, "\r\n"
    ]),
    deliver(SendmailPath, Mail).

%% Strips CR/LF from header field values to prevent header injection.
header_safe(Bin) ->
    re:replace(Bin, "[\r\n]+", " ", [global, {return, binary}]).

%% Handing the message to sendmail is what matters for "sent" -- once it's
%% queued with the local MTA, delivery is effectively guaranteed and the
%% sendmail process's own exit can lag well behind that (observed >10s in
%% production, long enough to collide with nginx's proxy_read_timeout). So
%% the request handler only waits on the fast, synchronous is_regular check;
%% the port is opened and waited on in a detached process purely so real
%% failures still get logged, without making the user wait for them.
deliver(SendmailPath, Mail) ->
    case filelib:is_regular(SendmailPath) of
        false ->
            error_logger:error_msg(
                "[contact] sendmail not found at ~s~n", [SendmailPath]),
            {error, sendmail_not_found};
        true ->
            spawn(fun() -> deliver_async(SendmailPath, Mail) end),
            ok
    end.

deliver_async(SendmailPath, Mail) ->
    Port = open_port({spawn_executable, SendmailPath},
                      [{args, ["-t", "-i"]}, binary, exit_status,
                       stderr_to_stdout]),
    port_command(Port, Mail),
    Port ! {self(), close},
    receive
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, N}} ->
            error_logger:error_msg(
                "[contact] sendmail exited with status ~p~n", [N])
    after 30000 ->
        error_logger:error_msg(
            "[contact] sendmail did not exit within 30s~n", [])
    end.
