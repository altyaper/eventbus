defmodule Eventbus.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EventbusWeb.Telemetry,
      Eventbus.Repo,
      {DNSCluster, query: Application.get_env(:eventbus, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eventbus.PubSub},
      Eventbus.Chat.Presence,
      # Resolves (or generates) the API key before we serve requests
      Eventbus.Settings,
      # Start to serve requests, typically the last entry
      EventbusWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    warn_if_emails_are_only_logged()

    opts = [strategy: :one_for_one, name: Eventbus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp warn_if_emails_are_only_logged do
    if Application.get_env(:eventbus, Eventbus.Mailer)[:adapter] == Swoosh.Adapters.Logger do
      require Logger

      Logger.warning(
        "RESEND_API_KEY is not set: account emails are only logged, not sent. " <>
          "Copy confirmation and reset links from these logs."
      )
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EventbusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
