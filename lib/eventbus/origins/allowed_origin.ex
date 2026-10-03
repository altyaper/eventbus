defmodule Eventbus.Origins.AllowedOrigin do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eventbus.Origins.Pattern

  schema "allowed_origins" do
    field :origin, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates the origin and stores it in canonical form, so `HTTPS://X.com/`
  and `https://x.com` are the same row.
  """
  def changeset(allowed_origin, attrs) do
    allowed_origin
    |> cast(attrs, [:origin])
    |> validate_required([:origin])
    |> canonicalize_origin()
    |> unique_constraint(:origin, message: "is already allowed")
  end

  defp canonicalize_origin(changeset) do
    case get_change(changeset, :origin) do
      nil ->
        changeset

      origin ->
        case Pattern.parse(origin) do
          {:ok, pattern} ->
            put_change(changeset, :origin, Pattern.to_string(pattern))

          :error ->
            add_error(
              changeset,
              :origin,
              "must look like example.com, https://example.com, localhost:5173 or *.example.com"
            )
        end
    end
  end
end
