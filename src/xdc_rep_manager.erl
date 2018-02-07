%% @author Couchbase <info@couchbase.com>
%% @copyright 2011-2017 Couchbase, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.
%%
%% The XDC Replication Manager (XRM) manages vbucket replication to remote data
%% centers. Each instance of XRM running on a node is responsible for only
%% replicating the node's active vbuckets. Individual vbucket replications are
%% are controlled by adding/deleting replication documents to the _replicator
%% db.
%%
%% A typical XDC replication document will look as follows:
%% {
%%   "_id" : "my_xdc_rep",
%%   "type" : "xdc",
%%   "source" : "bucket0",
%%   "target" : "/remoteClusters/clusterUUID/buckets/bucket0",
%%   "continuous" : true
%% }
%%

-module(xdc_rep_manager).
-behaviour(gen_server).

-export([stats/1, latest_errors/0]).
-export([start_link/0, init/1, handle_call/3, handle_info/2, handle_cast/2]).
-export([code_change/3, terminate/2]).

-include("xdc_replicator.hrl").

start_link() ->
    ?xdcr_info("start XDCR replication manager..."),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

% returns a list of replication stats for the bucket. the format for each
% item in the list is:
% {ReplicationDocId,           & the settings doc id for this replication
%    [{changes_left, Integer}, % amount of work remaining
%     {docs_checked, Integer}, % total number of docs checked on target, survives restarts
%     {docs_written, Integer}, % total number of docs written to target, survives restarts
%     ...
%    ]
% }
stats(Bucket0) ->
    Bucket = list_to_binary(Bucket0),
    Reps = try xdc_replication_sup:get_replications(Bucket)
           catch T:E ->
                   ?xdcr_error("xdcr stats Error:~p", [{T,E,erlang:get_stacktrace()}]),
                   []
           end,
    lists:foldl(
      fun({Id, Pid}, Acc) ->
              case catch xdc_replication:stats(Pid) of
                  {ok, Stats} ->
                      [{Id, Stats} | Acc];
                  Error ->
                      ?xdcr_error("Error getting stats for bucket ~s with"
                                  " id ~s :~p", [Bucket, Id, Error]),
                      Acc
              end
      end, [], Reps).


latest_errors() ->
    Reps = try xdc_replication_sup:get_replications()
           catch T:E ->
                   ?xdcr_error("xdcr stats Error:~p", [{T,E,erlang:get_stacktrace()}]),
                   []
           end,
    lists:foldl(
        fun({Bucket, Id, Pid}, Acc) ->
                case catch xdc_replication:latest_errors(Pid) of
                    {ok, Errors} ->
                        [{Bucket, Id, Errors} | Acc];
                    Error ->
                        ?xdcr_error("Error getting errors for bucket ~s with"
                                   " id ~s :~p", [Bucket, Id, Error]),
                        Acc
                end
        end, [], Reps).


init(_) ->
    proc_lib:init_ack({ok, self()}),

    Self = self(),

    ns_pubsub:subscribe_link(
      ns_config_events,
      fun ({{node, Node, stop_xdcr}, true}) when node() =:= Node ->
              Self ! stop_xdcr;
          (_) ->
              ok
      end),

    gen_server:enter_loop(?MODULE, [], []).

handle_call(Msg, From, State) ->
    ?xdcr_error("replication manager received unexpected call ~p from ~p",
                [Msg, From]),
    {stop, {error, {unexpected_call, Msg}}, State}.

handle_cast(Msg, State) ->
    ?xdcr_error("replication manager received unexpected cast ~p", [Msg]),
    {stop, {error, {unexpected_cast, Msg}}, State}.

handle_info({rep_db_update, Doc}, State) ->
    ?xdcr_debug("Ignoring updated doc ~p since old xdcr is disabled", [Doc]),
    {noreply, State};

handle_info(stop_xdcr, State) ->
    ?xdcr_info("Stop was requested by goxdcr upgrade"),
    xdc_replication_sup:stop_all_replications(),
    ns_config:delete({node, node(), stop_xdcr}),
    {noreply, State};

handle_info(Msg, State) ->
    %% Ignore any other messages but log them
    ?xdcr_info("ignoring unexpected message: ~p", [Msg]),
    {noreply, State}.


terminate(_Reason, _State) ->
    xdc_replication_sup:shutdown().

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
