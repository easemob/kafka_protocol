-module(kpro_produce_request_tests).

-include_lib("eunit/include/eunit.hrl").
-include("kpro.hrl").

-define(TOPIC, <<"test-topic">>).
-define(PARTI, 0).
-define(HOST, "localhost").
-define(TIMEOUT, 5000).
-define(MIN_MAGIC_2_VSN, 3).

-define(ASSERT_RESPONSE_NO_ERROR(Vsn, Rsp),
        begin
          #kpro_rsp{ tag = produce_response
                   , vsn = Vsn
                   , msg = [ {responses, [Response]}
                           | _
                           ]
                   } = Rsp,
          [ {topic, ?TOPIC}
          , {partition_responses, [PartitionRsp]}
          | _
          ] = Response,
          ?assertMatch([ {partition, ?PARTI}
                       , {error_code, no_error}
                       , {base_offset, _}
                       | _
                       ], PartitionRsp)
        end).

magic_v0_basic_test_() ->
  {Min, Max} = query_api_versions(),
  MkTestFun =
    fun(Vsn) ->
        fun() ->
          with_connection(
            fun(Pid) ->
              Req = make_req(Vsn),
              {ok, Rsp} = kpro:request_sync(Pid, Req, ?TIMEOUT),
              ?ASSERT_RESPONSE_NO_ERROR(Vsn, Rsp)
            end)
        end
    end,
  MkTest =
    fun(Vsn) ->
        {"batch magic version 0 in produce request version " ++
         integer_to_list(Vsn), MkTestFun(Vsn)}
    end,
  [MkTest(Vsn) || Vsn <- lists:seq(Min, Max)].

%% Timestamp within batch may not have to be monotonic.
non_monotoic_ts_in_batch_test() ->
  {_, Vsn} = query_api_versions(),
  case Vsn < ?MIN_MAGIC_2_VSN of
    true ->
      %% Nothing to test for kafka < 0.11
      ok;
    false ->
      Ts = kpro_lib:get_now_ts() - 1000,
      Msgs = [ #{ts => Ts,
                 value => make_value(?LINE)
                }
             , #{ts => Ts - 1000,
                 value => make_value(?LINE)
                }
             , #{ts => Ts + 1000,
                 value => make_value(?LINE)
                }
             ],
      Req = kpro_req_lib:produce(Vsn, ?TOPIC, ?PARTI, Msgs,
                                 _RequiredAcks = -1, _AckTimeout = 1000,
                                 no_compression),
      with_connection(
        fun(Pid) ->
          {ok, Rsp} = kpro:request_sync(Pid, Req, ?TIMEOUT),
          ?ASSERT_RESPONSE_NO_ERROR(Vsn, Rsp)
        end)
  end.

make_req(Vsn) ->
  Batch = make_batch(Vsn),
  kpro_req_lib:produce(Vsn, ?TOPIC, ?PARTI, Batch,
                       _RequiredAcks = 1,
                       _AckTimeout = 1000,
                       no_compression).

query_api_versions() ->
  {ok, Versions} =
    with_connection(fun(Pid) -> kpro:query_api_versions(Pid, 1000) end),
  {_, MinMax} = lists:keyfind(produce_request, 1, Versions),
  MinMax.

with_connection(Fun) ->
  kpro_test_lib:with_connection(Fun).

% Produce requests since v3 are only allowed to
% contain record batches with magic v2
% magic 0-1 have tuple list as batch input
% magic 2 has map list as batch input
make_batch(Vsn) when Vsn < ?MIN_MAGIC_2_VSN ->
  [ {<<"key1">>, make_value(Vsn)}
  , {<<"key2">>, make_value(Vsn)}
  ];
make_batch(Vsn) ->
  F = fun(I) ->
          #{ key => iolist_to_binary("key" ++ integer_to_list(I))
           , value => make_value(Vsn)
           }
      end,
  [F(1), F(2)].

make_value(Random) ->
  term_to_binary({Random, os:system_time()}).

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
