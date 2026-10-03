defmodule EventbusWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import EventbusWeb.ChannelCase

      # The default endpoint for testing
      @endpoint EventbusWeb.Endpoint
    end
  end

  setup tags do
    Eventbus.DataCase.setup_sandbox(tags)
    :ok
  end
end
