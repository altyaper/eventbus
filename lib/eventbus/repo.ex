defmodule Eventbus.Repo do
  use Ecto.Repo,
    otp_app: :eventbus,
    adapter: Ecto.Adapters.Postgres
end
