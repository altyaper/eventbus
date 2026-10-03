defmodule EventbusWeb.TopicEventController do
  use EventbusWeb, :controller

  alias Eventbus.{Events, Topics}

  def create(%{assigns: %{current_app: app}} = conn, %{"name" => name}) do
    if Topics.valid_name?(name) do
      case Topics.get_or_create_app_topic(app, name) do
        {:ok, _topic} ->
          {:ok, event} = Events.publish(name, conn.body_params)

          conn
          |> put_status(:accepted)
          |> json(event)

        {:error, :forbidden} ->
          error(conn, :forbidden, "topic belongs to another application")

        # The app was deleted between authenticating and creating the topic.
        {:error, %Ecto.Changeset{}} ->
          error(conn, :unauthorized, "unauthorized")
      end
    else
      error(conn, :unprocessable_entity, "invalid topic name")
    end
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end
end
