defmodule Eventbus.TopicTokens.Revocation do
  @moduledoc """
  A full revocation of one of an app's users: topic tokens minted for them
  before `revoked_at` are refused.
  """

  use Ecto.Schema

  schema "topic_revocations" do
    field :user_id, :string
    field :revoked_at, :utc_datetime_usec

    belongs_to :application, Eventbus.Applications.App
  end
end
