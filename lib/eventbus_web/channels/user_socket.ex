defmodule EventbusWeb.UserSocket do
  use Phoenix.Socket

  channel "topic:*", EventbusWeb.TopicChannel

  # Keeps the browser's origin (copied into a header by the endpoint) so the
  # channel can check it per app on join. `nil` means no Origin header.
  @impl true
  def connect(_params, socket, connect_info) do
    {:ok, assign(socket, :origin, origin(connect_info))}
  end

  defp origin(%{x_headers: headers}) do
    case List.keyfind(headers, EventbusWeb.OriginHeader.header(), 0) do
      {_key, origin} -> URI.parse(origin)
      nil -> nil
    end
  end

  defp origin(_connect_info), do: nil

  @impl true
  def id(_socket), do: nil
end
