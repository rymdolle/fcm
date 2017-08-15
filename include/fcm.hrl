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

-record(fcm_key, {token :: fcm:token(),
                  id    :: fcm:id()}).

-record(fcm_message, {id           :: fcm:message_id(),
                      to           :: fcm:id() | [fcm:id()],
                      sent = false :: boolean(),
                      content      :: list(),
                      results      :: list()}).
