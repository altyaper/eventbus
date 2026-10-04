defmodule EventbusWeb.ChatFallbackController do
  @moduledoc """
  Turns the chat contexts' errors into JSON responses for the chat API and
  the topic token API. Another app's room or user is a 404, never a 403.
  """

  use EventbusWeb, :controller

  alias Eventbus.Chat.Serializer

  def call(conn, {:error, :not_found}), do: error(conn, :not_found, "not found")

  def call(conn, {:error, :forbidden}), do: error(conn, :forbidden, "forbidden")

  def call(conn, {:error, :direct_room}),
    do: error(conn, :unprocessable_entity, "direct rooms always have their two members")

  def call(conn, {:error, :same_user}),
    do: error(conn, :unprocessable_entity, "a direct room needs two different users")

  def call(conn, {:error, :invalid}), do: error(conn, :unprocessable_entity, "invalid request")

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid", errors: Serializer.errors(changeset)})
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end
end
