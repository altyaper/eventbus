defmodule EventbusWeb.TopicEventController do
  use EventbusWeb, :controller

  alias Eventbus.{Events, Topics}

  def create(conn, %{"name" => name}) do
    payload = conn.body_params

    if Topics.valid_name?(name) do
      {:ok, event} = Events.publish(name, payload)

      conn
      |> put_status(:accepted)
      |> json(event)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "invalid topic name"})
    end
  end
end
