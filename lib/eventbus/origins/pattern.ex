defmodule Eventbus.Origins.Pattern do
  @moduledoc """
  An allowed-origin pattern, in the same format as `PHX_EXTRA_ORIGINS`:

    * `example.com` or `//example.com` - any scheme and port
    * `localhost:5173` - any scheme, that port only
    * `https://example.com` - that scheme, host and (default) port only
    * `*.example.com` - any subdomain of example.com (not the apex)
  """

  defstruct [:scheme, :host, :port]

  @host_format ~r/^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/

  @doc """
  Parses a pattern string. Returns `{:ok, pattern}` or `:error`.
  """
  def parse(input) when is_binary(input) do
    input = input |> String.trim() |> String.downcase() |> String.replace_suffix("/", "")

    uri =
      if String.contains?(input, "://") do
        URI.parse(input)
      else
        URI.parse("//" <> String.trim_leading(input, "//"))
      end

    with %URI{host: host, path: nil, query: nil, fragment: nil, userinfo: nil} <- uri,
         true <- uri.scheme in [nil, "http", "https"],
         true <- is_binary(host) and Regex.match?(@host_format, host) do
      {:ok, %__MODULE__{scheme: uri.scheme, host: host, port: uri.port}}
    else
      _invalid -> :error
    end
  end

  def parse(_input), do: :error

  @doc """
  Whether the browser origin `uri` is allowed by `pattern`.
  """
  def matches?(%__MODULE__{} = pattern, %URI{} = uri) do
    (is_nil(pattern.scheme) or pattern.scheme == uri.scheme) and
      (is_nil(pattern.port) or pattern.port == uri.port) and
      host_matches?(pattern.host, uri.host)
  end

  defp host_matches?("*." <> domain, host) when is_binary(host),
    do: String.ends_with?(host, "." <> domain)

  defp host_matches?(pattern_host, host), do: pattern_host == host

  @doc """
  The canonical string form, used for storage and display.
  """
  def to_string(%__MODULE__{scheme: nil, host: host, port: nil}), do: host
  def to_string(%__MODULE__{scheme: nil, host: host, port: port}), do: "#{host}:#{port}"

  def to_string(%__MODULE__{scheme: scheme, host: host, port: port}) do
    URI.to_string(%URI{scheme: scheme, host: host, port: port})
  end
end
