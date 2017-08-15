# FCM #

An erlang application for [Firebase Cloud Messaging][]

**fcm** is built with [rebar3](https://rebar3.org)

## Quickstart ##

```
$ erl -s fcm -fcm api_key \"$(cat  ~/.fcm_api_key)\"
...
1> Token = <<"dJKIEHyBL4s:APA91bHcEnjDZx...">>.
2> fcm:push(Token, [{notification, [{title, <<"test">>}, {body, <<"test">>}]}]).
```
And you're off...

## Description ##

**fcm** is an erlang application to use googles [Firebase Cloud Messaging][].

Registration of tokens and user ids to be able to send messages to
multiple devices that is logged in with the same user.

Supply your api key as application env 'api_key' and you should be good to go.

Stores keys and failed messages in mnesia database.

You can also set application env 'send_url' to make it work with [Google Cloud Messaging][].

Automatically deletes tokens that are no longer registeres at gooles servers.

Retrying failed messages after "Retry-After" header if present or incrementing timeout (math:pow(2, Tries)).

Abort unsuccessful messages to try to send again.

Force resend but it is not recomended.

## Guide ##


##### Build #####

```bash
$ rebar3 compile
```


##### Run #####

Be sure to set your api key
```
$ erl -s fcm -fcm api_key \"$(cat  ~/.fcm_api_key)\"
```


##### Create mnesia tables #####
```
...
1> rr("include/fcm.hrl").
[fcm_key,fcm_message]
2> mnesia:create_table(fcm_key, [{attributes, record_info(fields, fcm_key)}]).
{atomic,ok}
3> mnesia:create_table(fcm_message, [{attributes, record_info(fields, fcm_message)}]).
{atomic,ok}
```


##### Register token #####
```
4> Token = <<"dJKIEHyBL4s:APA91bHcEnjDZx...">>.
5> fcm:register(Token, 1).
true
```


##### Push a notification #####
```
6> fcm:push_to_id(1, [{notification, [{title, <<"test title">>}, {body, <<"test body">>}]}]).
{ok,<0.140.0>}
...
08:49:52.723 [debug] Sent successfully
```

## Data types ##

#### `token()` ####

```erlang
token() = binary()
```

#### `id()` ####

```erlang
id() = any()
```

## Exports ##

#### `register/1`, `register/2` ####

```erlang
register(Token)     -> boolean()
register(Token, Id) -> boolean()

  Token = token()
  Id = id()
```

Register a token

#### `push/2` ####

```erlang
push(Tokens, Message) -> {ok, pid()} | {error, Reason}

  Tokens = token() | [token()]
  Message = [Option] | map()
  Option = {Key, Value}
  Key = binary() | atom()
  Value = jsx:json_term()
```

Push a message to devices by their token

Message is a list or map of downstream message that will be converted
to json with [jsx][]

For more information of keys and values see: https://firebase.google.com/docs/cloud-messaging/http-server-ref#send-downstream

#### `push_to_ids/2`, `push_to_id/2` ####

```erlang
push_to_id(Id, Message)   -> {ok, pid()} | {error, Reason}
push_to_ids(Ids, Message) -> {ok, pid()} | {error, Reason}

  Id = id()
  Ids = [Id]
  Message = [Option] | map()
  Option = {Key, Value}
  Key = binary() | atom()
  Value = jsx:json_term()
```

Push a message to users by their ids

See [`push/2`](#push2)

#### `abort/1`, `abort/2` ####

```erlang
abort(Pid) -> [Message]
abort(Pid, Timeout) -> [Message]

  Pid = pid()
  Timeout = pos_integer() | infinity
  Message = #fcm_message{}
```

Abort all resends

#### `retry/1` ####

```erlang
retry(Pid) -> ok

  Pid = pid()
```

Force resend (not recomended)

#### `is_registered/1` ####

```erlang
is_registered(Token) -> boolean()

  Token = token()
```

Check if token is registered

#### `update_token/2` ####

```erlang
update_token(OldToken, NewToken) -> boolean()

  OldToken = NewToken = token()
```

Upadte existing token

#### `delete_token/1` ####

```erlang
delete_token(Token) -> boolean()

  Token = token()
```

Deletes token

#### `update_id/1` ####

```erlang
update_id(Token, Id) -> boolean()

  Token = token()
  Id = id()
```

Update id for token

#### `get_id/1` ####

```erlang
get_id(Token) -> id() | undefined

  Token = token()
```

Get id from token

#### `get_tokens/1` ####

```erlang
get_tokens(Id) -> [token()]

  Id = id()
```

Get tokens trom id

#### `save_message/1` ####

```erlang
save_message(Message) -> MessageId | undefined.

  Message = #fcm_message{}
  MessageId = any()
```

Save message

#### `get_message/1` ####

```erlang
get_message(Id) -> #fcm_message{} | undefined

  Id = any()
```

Get message


[jsx]: https://github.com/talentdeficit/jsx
[Firebase Cloud Messaging]: https://firebase.google.com/docs/cloud-messaging/
[Google Cloud Messaging]: https://developers.google.com/cloud-messaging/
