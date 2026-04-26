{:ok, _} = Application.ensure_all_started(:phoenix)
{:ok, _} = PhoenixSsg.TestSupport.Endpoint.start_link()
ExUnit.start()
