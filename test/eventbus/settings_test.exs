defmodule Eventbus.SettingsTest do
  # Not async: cache_api_key!/0 touches global app env and :persistent_term.
  use Eventbus.DataCase, async: false

  alias Eventbus.Settings

  describe "get_or_create_api_key/0" do
    test "generates a key once and keeps returning it" do
      key = Settings.get_or_create_api_key()

      assert "eb_" <> _ = key
      assert byte_size(key) > 40
      assert Settings.get_or_create_api_key() == key
    end
  end

  describe "cache_api_key!/0" do
    setup do
      configured = Application.get_env(:eventbus, :api_key)

      on_exit(fn ->
        Application.put_env(:eventbus, :api_key, configured)
        Settings.cache_api_key!()
      end)
    end

    test "prefers an explicitly configured key" do
      Application.put_env(:eventbus, :api_key, "from-env")
      assert Settings.cache_api_key!() == "from-env"
      assert Settings.api_key() == "from-env"
    end

    test "falls back to the stored key when none is configured" do
      Application.delete_env(:eventbus, :api_key)
      stored = Settings.get_or_create_api_key()

      assert Settings.cache_api_key!() == stored
      assert Settings.api_key() == stored
    end
  end
end
