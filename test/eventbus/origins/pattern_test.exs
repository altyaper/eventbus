defmodule Eventbus.Origins.PatternTest do
  use ExUnit.Case, async: true

  alias Eventbus.Origins.Pattern

  defp allows?(pattern, origin) do
    {:ok, pattern} = Pattern.parse(pattern)
    Pattern.matches?(pattern, URI.parse(origin))
  end

  defp canonical(input) do
    {:ok, pattern} = Pattern.parse(input)
    Pattern.to_string(pattern)
  end

  test "a bare host allows any scheme and port" do
    assert allows?("changologs.com", "https://changologs.com")
    assert allows?("//changologs.com", "http://changologs.com:8080")
    refute allows?("changologs.com", "https://evil.com")
    refute allows?("changologs.com", "https://app.changologs.com")
  end

  test "host:port allows only that port" do
    assert allows?("localhost:5173", "http://localhost:5173")
    refute allows?("localhost:5173", "http://localhost:3000")
  end

  test "a full origin is exact, including the default port" do
    assert allows?("https://changologs.com", "https://changologs.com")
    refute allows?("https://changologs.com", "http://changologs.com")
    refute allows?("https://changologs.com", "https://changologs.com:8443")
  end

  test "a wildcard allows subdomains but not the apex" do
    assert allows?("*.example.com", "https://app.example.com")
    assert allows?("*.example.com", "https://a.b.example.com")
    refute allows?("*.example.com", "https://example.com")
    refute allows?("*.example.com", "https://notexample.com")
  end

  test "IP addresses work" do
    assert allows?("192.168.1.50", "http://192.168.1.50:4000")
  end

  test "canonical form is lowercase without trailing slash or default port" do
    assert canonical("  HTTPS://Changologs.com/ ") == "https://changologs.com"
    assert canonical("//Example.com") == "example.com"
    assert canonical("localhost:5173") == "localhost:5173"
    assert canonical("http://localhost:5173") == "http://localhost:5173"
  end

  test "rejects things that aren't origins" do
    for input <- [
          "",
          "   ",
          "https://",
          "ftp://x.com",
          "https://x.com/path",
          "x.com?a=1",
          "user@x.com",
          "exa mple.com",
          "*",
          "*.",
          "https://*"
        ] do
      assert Pattern.parse(input) == :error, "expected #{inspect(input)} to be rejected"
    end
  end
end
