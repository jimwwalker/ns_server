%% @author Northscale <info@northscale.com>
%% @copyright 2009 NorthScale, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%      http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% Run an orchestrator and vbucket supervisor per bucket

-module(ns_bucket_sup_sup).

-behaviour(supervisor).

-export([start_link/0, notify/1]).

-export([init/1]).


%% API

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% buckets key got updated
notify(Config) ->
    ChildSpecs = child_specs(Config),
    CurrentChildren = [Bucket || {Bucket, Pid, _, _} <- supervisor:which_children(?MODULE), Pid /= undefined],
    ZombieChildren = [Child || Child <- CurrentChildren, not lists:keymember(Child, 1, ChildSpecs)],
    lists:foreach(fun (Id) -> supervisor:terminate_child(?MODULE, Id) end, ZombieChildren),
    NewChildSpecs = [ChildSpec || ChildSpec = {Bucket, _} <- ChildSpecs, not lists:member(Bucket, CurrentChildren)],
    lists:foreach(fun (ChildSpec) -> supervisor:start_child(?MODULE, ChildSpec) end, NewChildSpecs),
    lists:foreach(fun ({Bucket, BucketConfig}) -> ns_bucket_sup:notify(Bucket, BucketConfig) end,
                  proplists:get_value(configs, Config)).


%% supervisor callbacks

init([]) ->
    {ok, {{one_for_all, 3, 10},
          child_specs()}}.


%% Internal functions
child_specs() ->
    Configs = ns_bucket:get_buckets(),
    ChildSpecs = child_specs(Configs),
    error_logger:info_msg("~p:child_specs(): ChildSpecs = ~p~n", [?MODULE, ChildSpecs]),
    ChildSpecs.

child_specs(Configs) ->
    [child_spec(B) || {B, _} <- Configs].

child_spec(Bucket) ->
    {Bucket, {ns_bucket_sup, start_link, [Bucket]},
     permanent, infinity, supervisor, [ns_bucket_sup]}.
