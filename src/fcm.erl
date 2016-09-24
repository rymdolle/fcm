%%% Copyright (c) 2016 Olle Mattsson <olle@rymdis.com>
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.

-module(fcm).

-include_lib("fcm/include/fcm.hrl").

-behaviour(gen_server).

-export([start/0, start/1]).
-export([stop/0]).

-export([push/2, push_to_ids/2, push_to_id/2]).
-export([retry/1, abort/1, abort/2]).

%% gen_server callbacks
-export([start_push/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([register/2, register/1]).
-export([delete_token/1]).
-export([update_token/2, update_id/2]).
-export([is_registered/1]).
-export([get_tokens/1, get_id/1]).

-export([save_message/1, get_message/1]).

-export_type([token/0, id/0]).
-type token() :: binary().
-type id()    :: any().

-export_type([message_id/0]).
-type message_id() :: any().

-record(state, {message        :: #fcm_message{},
                tries = 0      :: integer(),
                timer          :: timer:tref() | undefined,
                retry_messages :: list()}).

start() ->
    start(temporary).
start(Type) ->
    case application:ensure_all_started(fcm, Type) of
        {ok, _} ->
            ok;
        Other ->
            Other
    end.

stop() ->
    application:stop(fcm).

%% Start new request
-spec push(token() | [token()],
           proplists:proplist() | map()) ->
                  supervisor:startchild_ret().
push(Tokens, Content) when is_list(Tokens) ->
    Message = #fcm_message{to = Tokens,
                           content = Content},
    Child = #{id => make_ref(),
              restart => temporary,
              start => {fcm, start_push, [Message]}},
    supervisor:start_child(fcm_sup, Child);
push(Token, Content) ->
    push([Token], Content).

-spec push_to_ids([id()], proplists:proplist() | map()) ->
                         supervisor:startchild_ret().
push_to_ids(Ids, Content) when is_list(Ids) ->
    Tokens = lists:foldl(fun(Id, Acc) -> get_tokens(Id) ++ Acc end, [], Ids),
    push(Tokens, Content).

-spec push_to_id(id(), proplists:proplist() | map()) ->
                        supervisor:startchild_ret().
push_to_id(Id, Content) ->
    push_to_ids([Id], Content).


%% Override retry timer
-spec retry(pid()) -> ok.
retry(Pid) ->
    gen_server:cast(Pid, retry).

%% Abort all resends
-spec abort(pid()) -> [#fcm_message{}].
abort(Pid) ->
    gen_server:call(Pid, abort).
-spec abort(pid(), pos_integer() | infinity) -> [#fcm_message{}].
abort(Pid, Timeout) ->
    gen_server:call(Pid, abort, Timeout).



-spec register(token()) -> boolean().
register(Token) ->
    Transaction =
        fun() ->
                case is_registered(Token) of
                    true  -> false;
                    false -> mnesia:write(#fcm_key{token = Token})
                end
        end,
    case mnesia:transaction(Transaction) of
        {atomic, ok} ->
            true;
        _ ->
            false
    end.

-spec register(token(), id()) -> boolean().
register(Token, Id) ->
    Transaction =
        fun() ->
                case is_registered(Token) of
                    true  -> false;
                    false -> mnesia:write(#fcm_key{token = Token, id = Id})
                end
        end,
    case mnesia:transaction(Transaction) of
        {atomic, ok} ->
            true;
        _ ->
            false
    end.

-spec is_registered(token()) -> boolean().
is_registered(Token) ->
    Transaction =
        fun() ->
                [] /= mnesia:read(fcm_key, Token)
        end,
    case mnesia:transaction(Transaction) of
        {atomic, Result} ->
            Result;
        _ ->
            false
    end.


-spec update_token(token(), token()) -> boolean().
update_token(OldToken, NewToken) ->
    Transaction =
        fun() ->
                case mnesia:wread({fcm_key, OldToken}) of
                    [Key] -> mnesia:write(Key#fcm_key{token = NewToken});
                    _     -> false
                end
        end,
    case mnesia:transaction(Transaction) of
        {atomic, ok} ->
            true;
        _ ->
            false
    end.

-spec delete_token(token()) -> boolean().
delete_token(Token) ->
    Transaction =
        fun() ->
                mnesia:delete({fcm_key, Token})
        end,
    case mnesia:transaction(Transaction) of
        {atomic, ok} ->
            true;
        _ ->
            false
    end.

-spec update_id(token(), id()) -> boolean().
update_id(Token, Id) ->
    Transaction =
        fun() ->
                case mnesia:wread({fcm_key, Token}) of
                    [Key] -> mnesia:write(Key#fcm_key{id = Id});
                    _     -> false
                end
        end,
    case mnesia:transaction(Transaction) of
        {atomic, ok} ->
            true;
        _ ->
            false
    end.

-spec get_id(token()) -> id() | undefined.
get_id(Token) ->
    Transaction =
        fun() ->
                mnesia:read(fcm_key, Token)
        end,
    case mnesia:transaction(Transaction) of
        {atomic, [#fcm_key{id = Id}]} ->
            Id;
        _ ->
            undefined
    end.

-spec get_tokens(id()) -> [token()].
get_tokens(UserId) ->
    Transaction =
        fun() ->
                mnesia:select(fcm_key, [{#fcm_key{id = UserId,
                                                  token = '$1',
                                                  _ = '_'},
                                         [],
                                         ['$1']}])
        end,
    case mnesia:transaction(Transaction) of
        {atomic, Tokens} ->
            Tokens;
        _ ->
            []
    end.

-spec save_message(#fcm_message{}) -> boolean().
save_message(Message = #fcm_message{}) ->
    Transaction =
        fun() ->
                case mnesia:read(fcm_key, Message#fcm_message.id) of
                    [] -> mnesia:write(Message);
                    _  -> false
                end
        end,
    case mnesia:transaction(Transaction) of
        {atomic, ok} ->
            Message#fcm_message.id;
        _ ->
            false
    end.

-spec get_message(message_id()) -> #fcm_message{} | undefined.
get_message(Id) ->
    Transaction =
        fun() ->
                mnesia:read(fcm_message, Id)
        end,
    case mnesia:transaction(Transaction) of
        {atomic, [Message]} ->
            Message;
        _ ->
            undefined
    end.

%% Local start function
start_push(Message) ->
    gen_server:start_link(?MODULE, [Message], []).

%% Callbacks
init([Message]) ->
    lager:debug("Starting worker"),
    case send(Message) of
        {ok, _ReqId} ->
            {ok, #state{message = Message}};
        {error, Reason} ->
            {error, Reason}
    end.

handle_call(abort, _From, State) ->
    timer:cancel(State#state.timer),
    lager:debug("Message aborted ~p", [lager:pr(State, ?MODULE)]),
    AbortedIds =
        lists:map(fun(Message) ->
                          Id = crypto:hash(sha, term_to_binary(Message)),
                          fcm:save_message(Message#fcm_message{id = Id,
                                                               results = [aborted]}),
                          Id
                  end,
                  State#state.retry_messages),
    {stop, aborted, AbortedIds, State}.

handle_cast(retry, State) ->
    timer:cancel(State#state.timer),
    lists:foreach(fun resend/1, State#state.retry_messages),
    {noreply, State#state{tries = State#state.tries+1,
                          retry_messages = []}}.

handle_info({http, {_ReqId, {{_, 200, _}, Headers, Body}}}, State) ->
    Json = jsx:decode(Body, [return_maps]),
    lager:debug("Return json ~p", [Json]),
    Failures = maps:get(<<"failure">>, Json),
    CannonicalIds = maps:get(<<"canonical_ids">>, Json),
    if Failures == 0 andalso CannonicalIds == 0 ->
            lager:debug("Sent successfully"),
            {stop, normal, State};
       true ->
            RetryMessages = get_retry_messages(State#state.message, Json),
            Timeout = proplists:get_value("retry-after", Headers),
            TimeoutInSeconds = timeout_in_seconds(Timeout, State#state.tries),
            {ok, Timer} = timer:apply_after(timer:seconds(TimeoutInSeconds),
                                            ?MODULE, retry, [self()]),
            {noreply, State#state{retry_messages = RetryMessages,
                                  timer = Timer}}
    end;
handle_info({http, {_ReqId, {{_, Code, _}, Headers, Body}}}, State)
  when Code >= 500 andalso Code < 600 ->
    OrigMessage = State#state.message,
    RetryMessages =
        try jsx:decode(Body, [return_maps]) of
            Json ->
                lager:debug("Return json ~p", [Json]),
                get_retry_messages(State#state.message, Json)
        catch Error:Reason ->
                lager:error("Response not json. ~p\nStacktrace:\n~p",
                            [Body,
                             lager:pr_stacktrace(erlang:get_stacktrace(),
                                                 {Error,Reason})]),
                if is_list(OrigMessage#fcm_message.to) ->
                        lists:map(fun(To) ->
                                          OrigMessage#fcm_message{to = To}
                                  end, OrigMessage#fcm_message.to);
                   true ->
                        [OrigMessage]
                end
        end,
    Timeout = proplists:get_value("retry-after", Headers),
    TimeoutInSeconds = timeout_in_seconds(Timeout, State#state.tries),
    {ok, Timer} = timer:apply_after(timer:seconds(TimeoutInSeconds),
                                    ?MODULE, retry, [self()]),
    {noreply, State#state{retry_messages = RetryMessages,
                          timer = Timer}};
handle_info({http, {_ReqId, {{_, 400, _}, _Headers, Body}}}, State) ->
    lager:error("Bad request: ~p\nMessage: ~p",
                [Body, lager:pr(State, ?MODULE)]),
    {stop, {error, bad_request}, State};
handle_info({http, {_ReqId, {{_, 401, _}, _Headers, _Body}}}, State) ->
    lager:error("Unauthorized - ~p",
                [lager:pr(State, ?MODULE)]),
    {stop, {error, unauthorized}, State};
handle_info({http, {_ReqId, {{_, Code, _}, Headers, Body}}}, State) ->
    lager:error("Status code: ~b\nHeaders: ~p\nBody: ~p", [Code, Headers, Body]),
    {stop, {error, bad_return}, State};
handle_info({http, {_ReqId, {error, Reason}}}, State) ->
    lager:error("httpc error ~p", [Reason]),
    {stop, {error, {httpc, Reason}}, State}.

terminate(_Reason, State) ->
    lager:debug("Exiting worker ~p", [lager:pr(State, ?MODULE)]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Local functions
send_url() ->
    application:get_env(fcm, send_url, "https://fcm.googleapis.com/fcm/send").

send(Message) ->
    send(Message, self()).

send(Message = #fcm_message{to = [To]}, Pid) ->
    send(Message#fcm_message{to = To}, Pid);
send(#fcm_message{to = To, content = Content}, Pid) ->
    case application:get_env(api_key) of
        {ok, ApiKey} ->
            Headers = [{"authorization", io_lib:format("key=~s", [ApiKey])}],
            ToKey =
                if is_list(To) -> <<"registration_ids">>;
                   true        -> <<"to">>
                end,
            FCM =
                if is_map(Content)  -> Content#{ToKey => To};
                   is_list(Content) -> [{ToKey, To}|Content]
                end,
            Json = jsx:encode(FCM),
            httpc:request(post, {send_url(), Headers, "application/json", Json}, [],
                          [{sync, false}, {receiver, Pid}]);
        undefined ->
            lager:error("No defined api key"),
            {error, "Undefined API key"}
    end.

resend(Message = #fcm_message{}) ->
    Self = self(),
    spawn(fun() ->
                  %% Sleep for 1-5 seconds to not encounter the same error
                  %% again if there was an internal error at googles side
                  Min = 1, Max = 5,
                  timer:sleep(rand:uniform(Max-Min)+Min),
                  send(Message, Self)
          end).

get_retry_messages(Message, Json) when is_map(Json) ->
    Results = maps:get(<<"results">>, Json),
    MulticastId = maps:get(<<"multicast_id">>, Json),
    fcm:save_message(Message#fcm_message{id = MulticastId,
                                         results = Results}),
    ResultsWithTo = lists:zip(Message#fcm_message.to, Results),
    RetryTokens = parse_results(ResultsWithTo),
    lists:map(fun(Token) ->
                      Message#fcm_message{to = Token}
              end, RetryTokens).


parse_results(Results) ->
    parse_results(Results, []).

parse_results([], Acc) ->
    Acc;
parse_results([{OldToken,
                #{<<"message_id">> := _MessageId,
                  <<"registration_id">> := NewToken}}|Rest], Acc) ->
    lager:debug("Token changed"),
    fcm:update_token(OldToken, NewToken),
    parse_results(Rest, Acc);
parse_results([{_Token,
                #{<<"message_id">> := MessageId}}|Rest], Acc) ->
    lager:debug("Success sending message ~p", [MessageId]),
    parse_results(Rest, Acc);
parse_results([{Token,
                #{<<"error">> := <<"NotRegistered">>}}|Rest], Acc) ->
    lager:warning("Token not registered, deleting"),
    fcm:delete_token(Token),
    parse_results(Rest, Acc);
parse_results([{Token,
                #{<<"error">> := <<"Unavailable">>}}|Rest], Acc) ->
    parse_results(Rest, [Token|Acc]);
parse_results([{Token,
                #{<<"error">> := <<"InternalServerError">>}}|Rest], Acc) ->
    lager:warning("Internal server error, try again later"),
    parse_results(Rest, [Token|Acc]);
parse_results([{_Token,
                #{<<"error">> := Error}}|Rest], Acc) ->
    lager:error("Unrecoverable error: ~p", [Error]),
    parse_results(Rest, Acc);
parse_results([_|Rest], Acc) ->
    parse_results(Rest, Acc).

timeout_in_seconds(undefined, Tries) ->
    round(math:pow(2,Tries));
timeout_in_seconds(Timeout, Tries) ->
    try list_to_integer(Timeout) of
        Seconds -> Seconds
    catch
        _:_ ->
            try httpd_util:convert_request_date(Timeout) of
                Date ->
                    calendar:datetime_to_gregorian_seconds(Date) -
                        calendar:datetime_to_gregorian_seconds(erlang:universaltime())
            catch _:_ ->
                    timeout_in_seconds(undefined, Tries)
            end
    end.
