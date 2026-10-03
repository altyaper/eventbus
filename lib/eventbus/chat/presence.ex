defmodule Eventbus.Chat.Presence do
  @moduledoc """
  Who is connected to each chat room, tracked by the room channel. Keys are
  the app's user ids; each connection (tab, device) adds a meta, so a user is
  online while any of them is. Ephemeral: nothing is written to the database.
  """

  use Phoenix.Presence, otp_app: :eventbus, pubsub_server: Eventbus.PubSub
end
