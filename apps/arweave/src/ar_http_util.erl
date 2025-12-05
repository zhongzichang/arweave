-module(ar_http_util).

-export([get_tx_content_type/1, arweave_peer/1]).

-include_lib("arweave/include/ar.hrl").
-include_lib("arweave_config/include/arweave_config.hrl").

-define(PRINTABLE_ASCII_REGEX, "^[ -~]*$").

%%%===================================================================
%%% Public interface.
%%%===================================================================

get_tx_content_type(#tx { tags = Tags }) ->
	case lists:keyfind(<<"Content-Type">>, 1, Tags) of
		{<<"Content-Type">>, ContentType} ->
			case is_valid_content_type(ContentType) of
				true -> {valid, ContentType};
				false -> invalid
			end;
		false ->
			none
	end.

arweave_peer(Req) ->
	{ok, Config} = application:get_env(arweave, config),
	ArweavePeerPort = get_peer_port(Req),
	#{ peer := {PeerIpV4, _TcpPeerPort} } = Req,

	HttpHeaderClientIpV4 = get_client_ipv4_from_http_header(Req),

	ProxyIPs = [peer_to_ip_addr(Peer) || Peer <- Config#config.proxy_peers],

	{IpV4_1, IpV4_2, IpV4_3, IpV4_4} = case {HttpHeaderClientIpV4, Config#config.proxy_header, lists:member(PeerIpV4, ProxyIPs)} of
		{undefined, true, true} ->
			get_client_ipv4_from_proxy_header(Req);
		{undefined, _, _} ->
			PeerIpV4;
		{_,_,_} ->
			HttpHeaderClientIpV4
	end,

	{IpV4_1, IpV4_2, IpV4_3, IpV4_4, ArweavePeerPort}.


%%%===================================================================
%%% Private functions.
%%%===================================================================

get_client_ipv4_from_http_header(Req) ->
	Ips = cowboy_req:parse_header(<<"x-forwarded-for">>, Req),
	ClientIp = case {Ips, is_list(Ips)} of
		{undefined, _} -> undefined;
		{_, true} -> hd(Ips);
		_ -> undefined
	end,
	case ClientIp of
		[Head | _Tail] when is_binary(Head) -> parse_ipv4(Head);
		Binary when is_binary(Binary) -> parse_ipv4(Binary);
		_ -> undefined
	end.

get_client_ipv4_from_proxy_header(Req) ->
	#{ proxy_header := #{src_address := SourceIpV4} } = Req,
	case SourceIpV4 of
		undefined -> 
			get_client_ipv4_from_peer(Req);
		_ -> 
			case is_binary(SourceIpV4) of
				true -> parse_ipv4(SourceIpV4);
				false -> SourceIpV4
			end
	end.

get_client_ipv4_from_peer(Req) ->
	#{peer := {IP, _Port}} = Req,
	IP.

parse_ipv4(Binary) ->
	Str = binary_to_list(Binary),
	case inet:parse_ipv4strict_address(Str) of
		{ok, IpV4} -> IpV4;
		_ -> undefined
	end.

get_peer_port(Req) ->
	case cowboy_req:header(<<"x-p2p-port">>, Req) of
		undefined -> ?DEFAULT_HTTP_IFACE_PORT;
		Binary -> binary_to_integer(Binary)
	end.

peer_to_ip_addr({A, B, C, D, _}) -> {A, B, C, D}.

is_valid_content_type(ContentType) ->
	case re:run(
		ContentType,
		?PRINTABLE_ASCII_REGEX,
		[dollar_endonly, {capture, none}]
	) of
		match -> true;
		nomatch -> false
	end.
