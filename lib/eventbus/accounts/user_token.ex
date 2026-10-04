defmodule Eventbus.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  alias Eventbus.Accounts.UserToken

  @rand_size 32
  @hash_algorithm :sha256

  @session_validity_in_days 60
  @confirm_validity_in_days 7
  @reset_password_validity_in_days 1

  # Emailed links of one kind can be requested at most once per this window.
  @email_cooldown_in_seconds 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    # The email an emailed token went to; it stops working if that changes.
    field :sent_to, :string
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

  @doc """
  Builds a token for an emailed link (`"confirm"` or `"reset_password"`).
  Returns the url-safe token for the link and the row to insert, which only
  holds its hash: a leaked database row can't be turned back into a link.
  """
  def build_email_token(user, context) when context in ~w(confirm reset_password) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: :crypto.hash(@hash_algorithm, token),
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Query returning the user for an emailed token that is unexpired and was
  sent to the user's current email. `:error` for a malformed token.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)

        {:ok,
         from(token in by_token_and_context_query(hashed, context),
           join: user in assoc(token, :user),
           where: token.inserted_at > ago(^validity_in_days(context), "day"),
           where: token.sent_to == user.email,
           select: user
         )}

      :error ->
        :error
    end
  end

  defp validity_in_days("confirm"), do: @confirm_validity_in_days
  defp validity_in_days("reset_password"), do: @reset_password_validity_in_days

  @doc """
  Query for whether the user was sent a `context` link within the cooldown.
  """
  def recently_sent_query(user, context) do
    from t in UserToken,
      where: t.user_id == ^user.id and t.context == ^context,
      where: t.inserted_at > ago(@email_cooldown_in_seconds, "second")
  end

  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  def session_validity_in_days, do: @session_validity_in_days
end
