-module(ar_pool_job_poller).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1, handle_cast/2, handle_call/3, handle_info/2, terminate/2]).

-include_lib("arweave/include/ar_config.hrl").
-include_lib("arweave/include/ar_pool.hrl").
-include_lib("eunit/include/eunit.hrl").

-record(state, {}).

%%%===================================================================
%%% Public interface.
%%%===================================================================

%% @doc Start the server.
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% Generic server callbacks.
%%%===================================================================

init([]) ->
	case {ar_pool:is_client(), ar_coordination:is_cm_miner()} of
		{true, false} ->
			gen_server:cast(self(), fetch_jobs);
		_ ->
			%% If we are not a CM miner, polling
			%% the pool jobs to us.
			ok
	end,
	{ok, #state{}}.

handle_call(Request, _From, State) ->
	?LOG_WARNING([{event, unhandled_call}, {module, ?MODULE}, {request, Request}]),
	{reply, ok, State}.

handle_cast(fetch_jobs, State) ->
	PrevOutput = (ar_pool:get_latest_job())#job.output,
	{ok, Config} = application:get_env(arweave, config),
	Peer =
		case {Config#config.coordinated_mining, Config#config.cm_exit_peer} of
			{true, not_set} ->
				%% We are a CM exit node.
				ar_pool:pool_peer();
			{true, ExitPeer} ->
				%% We are a CM miner.
				ExitPeer;
			_ ->
				%% We are a standalone pool client (a non-CM miner and a pool client).
				ar_pool:pool_peer()
		end,
	case ar_http_iface_client:get_jobs(Peer, PrevOutput) of
		{ok, Jobs} ->
			ar_pool:cache_jobs(Jobs),
			push_jobs_to_cm_peers(Jobs),
			ar_util:cast_after(?FETCH_JOBS_FREQUENCY_MS, self(), fetch_jobs);
		{error, Error} ->
			?LOG_WARNING([{event, failed_to_fetch_pool_jobs},
					{error, io_lib:format("~p", [Error])}]),
			ar_util:cast_after(?FETCH_JOBS_RETRY_MS, self(), fetch_jobs)
	end,
	{noreply, State};

handle_cast(Cast, State) ->
	?LOG_WARNING([{event, unhandled_cast}, {module, ?MODULE}, {cast, Cast}]),
	{noreply, State}.

handle_info(Message, State) ->
	?LOG_WARNING([{event, unhandled_info}, {module, ?MODULE}, {message, Message}]),
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

%%%===================================================================
%%% Private functions.
%%%===================================================================

push_jobs_to_cm_peers(Jobs) ->
	{ok, Config} = application:get_env(arweave, config),
	Peers = Config#config.cm_peers,
	Payload = ar_serialize:jsonify(ar_serialize:jobs_to_json_struct(Jobs)),
	push_jobs_to_cm_peers(Payload, Peers).

push_jobs_to_cm_peers(_Payload, []) ->
	ok;
push_jobs_to_cm_peers(Payload, [Peer | Peers]) ->
	spawn(fun() -> ar_http_iface_client:post_pool_jobs(Peer, Payload) end),
	push_jobs_to_cm_peers(Payload, Peers).
