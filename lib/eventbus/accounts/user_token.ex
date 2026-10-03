defmodule Eventbus.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  alias Eventbus.Accounts.UserToken

  @rand_size 32
  @session_validity_in_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :user, Eventbus.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a random session token. The raw token goes into the (signed) session
  cookie; the row lets us revoke it by deleting it.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Query returning the user for a session token that hasn't expired.
  """
  def verify_session_token_query(token) do
    from token in by_token_and_context_query(token, "session"),
      join: user in assoc(token, :user),
      where: token.inserted_at > ago(@session_validity_in_days, "day"),
      select: user
  end

  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  def session_validity_in_days, do: @session_validity_in_days
end
