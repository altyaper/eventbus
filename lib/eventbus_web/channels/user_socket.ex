defmodule EventbusWeb.UserSocket do
  use Phoenix.Socket

  alias Eventbus.Chat.Tokens

  channel "topic:*", EventbusWeb.TopicChannel
  channel "chat:*", EventbusWeb.ChatRoomChannel
  channel "chat_user:*", EventbusWeb.ChatUserChannel

  # Keeps the browser's origin (copied into a header by the endpoint) so the
  # channel can check it per app on join. `nil` means no Origin header.
  #
  # A `token` param (minted by an app's backend, see Eventbus.Chat.Tokens)
  # makes this a chat user's socket. Without one the socket stays anonymous
  # and can only listen to topics; a bad or expired token is refused.
  @impl true
  def connect(params, socket, connect_info) do
    socket = assign(socket, :origin, origin(connect_info))

    case params do
      %{"token" => token} ->
        case Tokens.verify(token) do
          {:ok, caller} -> {:ok, assign(socket, :chat_caller, caller)}
          :error -> :error
        end

      _no_token ->
        {:ok, socket}
    end
  end

  defp origin(%{x_headers: headers}) do
    case List.keyfind(headers, EventbusWeb.OriginHeader.header(), 0) do
      {_key, origin} -> URI.parse(origin)
      nil -> nil
    end
  end

  defp origin(_connect_info), do: nil

  # Chat sockets get an id so a user's sockets can be disconnected with
  # `EventbusWeb.Endpoint.broadcast(id, "disconnect", %{})`.
  @impl true
  def id(%{assigns: %{chat_caller: caller}}), do: "chat_socket:#{caller.user.id}"
  def id(_socket), do: nil
end
