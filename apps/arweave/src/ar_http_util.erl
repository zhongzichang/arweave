-module(ar_http_util).

-export([get_tx_content_type/1, arweave_peer/1]).

-include_lib("arweave/include/ar.hrl").

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

	IpV4_S1 = cowboy_req:header(<<"x-real-ip">>, Req),
	IpV4_S2 = case IpV4_S1 of
		undefined -> cowboy_req:header(<<"x-forwarded-for">>, Req);
		_ -> IpV4_S1
	end,
	{IpV4_Peer, _TcpPeerPort} = cowboy_req:peer(Req),

	{IpV4_1, IpV4_2, IpV4_3, IpV4_4} = case IpV4_S2 of
		undefined -> IpV4_Peer;
		_ ->
			%[FirstIp] = IpV4_S2,
			StrIp = binary_to_list(IpV4_S2),
			{ok, IP} = inet:parse_ipv4strict_address(StrIp),
			IP
	end,
	ArweavePeerPort =
		case cowboy_req:header(<<"x-p2p-port">>, Req) of
			undefined -> ?DEFAULT_HTTP_IFACE_PORT;
			Binary -> binary_to_integer(Binary)
		end,
	{IpV4_1, IpV4_2, IpV4_3, IpV4_4, ArweavePeerPort}.

%%%===================================================================
%%% Private functions.
%%%===================================================================

is_valid_content_type(ContentType) ->
	case re:run(
		ContentType,
		?PRINTABLE_ASCII_REGEX,
		[dollar_endonly, {capture, none}]
	) of
		match -> true;
		nomatch -> false
	end.
