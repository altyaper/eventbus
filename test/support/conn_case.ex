defmodule EventbusWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EventbusWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint EventbusWeb.Endpoint

      use EventbusWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EventbusWeb.ConnCase
    end
  end

  setup tags do
    Eventbus.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that logs in the test's default user, a confirmed member who
  owns every app fixture created without an explicit owner.

      setup :register_and_log_in_user
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Eventbus.AccountsFixtures.default_user()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Like `register_and_log_in_user/1`, but the user hasn't confirmed their
  email yet.
  """
  def register_and_log_in_unconfirmed_user(%{conn: conn}) do
    user =
      Eventbus.AccountsFixtures.put_default_user(
        Eventbus.AccountsFixtures.user_fixture(confirmed: false)
      )

    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given user into the conn by storing a session token.
  """
  def log_in_user(conn, user) do
    token = Eventbus.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
