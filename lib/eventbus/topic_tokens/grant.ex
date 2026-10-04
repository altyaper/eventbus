defmodule Eventbus.TopicTokens.Grant do
  @moduledoc """
  A topic pattern in a topic token: an exact topic name, or a name ending in
  `.*` that matches every topic below it (`a.b.*` matches `a.b.c` and
  `a.b.c.d`, not `a.b`). Patterns must stay inside the minting app's
  `"<slug>."` namespace; `"<slug>.*"` grants the whole app.
  """

  alias Eventbus.Topics.Topic

  @doc """
  Whether `pattern` is a well-formed grant for the app with `slug`.
  """
  def valid?(slug, pattern) when is_binary(slug) and is_binary(pattern) do
    case base(pattern) do
      {:prefix, ^slug} -> true
      {_kind, base} -> Topic.valid_name?(base) and String.starts_with?(base, slug <> ".")
    end
  end

  def valid?(_slug, _pattern), do: false

  @doc """
  Whether `pattern` matches the topic `name`.
  """
  def matches?(pattern, name) do
    case base(pattern) do
      {:prefix, base} -> String.starts_with?(name, base <> ".")
      {:exact, base} -> name == base
    end
  end

  defp base(pattern) do
    case String.split_at(pattern, -2) do
      {base, ".*"} -> {:prefix, base}
      _exact -> {:exact, pattern}
    end
  end
end
