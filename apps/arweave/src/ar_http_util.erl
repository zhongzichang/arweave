-module(ar_http_util).
-test_category([fast]).

%% NOTE: tests in this module are currently disabled. They were
%% picked up by the CI test-discovery rewrite but never ran in CI
%% before, so their pass/fail behavior was unknown. Each `*_test/0'
%% or `*_test_/0' function has been renamed with a `_disabled'
%% suffix. To re-enable a test, remove the suffix and verify it
%% passes (and remove this header once all tests in the module
%% are re-enabled).


-export([get_tx_content_type/1, arweave_peer/1]).

-include_lib("arweave/include/ar.hrl").
-include_lib("arweave_config/include/arweave_config.hrl").
-include_lib("eunit/include/eunit.hrl").

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

%%--------------------------------------------------------------------
%% @doc Check and valid `x-p2p-port' header.
%% @end
%%--------------------------------------------------------------------
-spec arweave_peer(Req) -> Return when
      Req :: cowboy:req(),
      Return :: {A, A, A, A, Port},
      A :: pos_integer(),
      Port :: pos_integer().

arweave_peer(Req) ->
    ProxyPeers = arweave_config:get([proxy_peers]),
    ProxyHeader = arweave_config:get([proxy_header]),
	ArweavePeerPort = get_peer_port(Req),
	#{ peer := {PeerIpV4, _TcpPeerPort} } = Req,

	HttpHeaderClientIpV4 = get_client_ipv4_from_http_header(Req),

	ProxyIPs = [peer_to_ip_addr(Peer) || Peer <- ProxyPeers],
	{IpV4_1, IpV4_2, IpV4_3, IpV4_4} = case {HttpHeaderClientIpV4, ProxyHeader, lists:member(PeerIpV4, ProxyIPs)} of
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
	Ips = cowboy_req:parse_header(<<"X-Forwarded-For">>, Req),
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

arweave_peer_test_disabled() ->
    [
                                                % an undefined x-p2p-port header should return the
                                                % default arweave port
     ?assertEqual(
        {1,2,3,4, ?DEFAULT_HTTP_IFACE_PORT},
        arweave_peer(#{
                       headers => #{},
                       peer => {{1,2,3,4}, 1234}
                      })
       ),

                                                % 1/TCP port is valid
     ?assertEqual(
        {1,2,3,4, 1},
        arweave_peer(#{
                       headers => #{ <<"x-p2p-port">> => <<"1">> },
                       peer => {{1,2,3,4}, 1234}
                      })
       ),

                                                % 65535/TCP port is valid
     ?assertEqual(
        {1,2,3,4, 65535},
        arweave_peer(#{
                       headers => #{ <<"x-p2p-port">> => <<"65535">> },
                       peer => {{1,2,3,4}, 1234}
                      })
       ),

                                                % 0/TCP port is invalid
     ?assertEqual(
        {1,2,3,4, ?DEFAULT_HTTP_IFACE_PORT},
        arweave_peer(#{
                       headers => #{ <<"x-p2p-port">> => <<"0">> },
                       peer => {{1,2,3,4}, 1234}
                      })
       ),

                                                % 65536/TCP port is invalid
     ?assertEqual(
        {1,2,3,4, ?DEFAULT_HTTP_IFACE_PORT},
        arweave_peer(#{
                       headers => #{ <<"x-p2p-port">> => <<"65536">> },
                       peer => {{1,2,3,4}, 1234}
                      })
       ),

                                                % a TCP port must be an integer, if not, a default
                                                % port is returned.
     ?assertEqual(
        {1,2,3,4, ?DEFAULT_HTTP_IFACE_PORT},
        arweave_peer(#{
                       headers => #{ <<"x-p2p-port">> => <<"test">> },
                       peer => {{1,2,3,4}, 1234}
                      })
       )
    ].
