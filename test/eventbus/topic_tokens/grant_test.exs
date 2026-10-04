defmodule Eventbus.TopicTokens.GrantTest do
  use ExUnit.Case, async: true

  alias Eventbus.TopicTokens.Grant

  test "valid?/2 accepts exact names and .* patterns inside the app" do
    assert Grant.valid?("acme", "acme.user.9f3c")
    assert Grant.valid?("acme", "acme.board.ab12.*")
    assert Grant.valid?("acme", "acme.*")
  end

  test "valid?/2 rejects patterns outside the app or malformed" do
    refute Grant.valid?("acme", "acme")
    refute Grant.valid?("acme", "other.board")
    refute Grant.valid?("acme", "acmeco.board")
    refute Grant.valid?("acme", "other.*")
    refute Grant.valid?("acme", "*")
    refute Grant.valid?("acme", "acme.*.logs")
    refute Grant.valid?("acme", "acme.board*")
    refute Grant.valid?("acme", "acme.Board")
    refute Grant.valid?("acme", nil)
  end

  test "matches?/2 on exact names" do
    assert Grant.matches?("acme.board", "acme.board")
    refute Grant.matches?("acme.board", "acme.board.x")
    refute Grant.matches?("acme.board", "acme.boards")
  end

  test "matches?/2 on .* patterns matches every topic below, not the prefix itself" do
    assert Grant.matches?("acme.board.*", "acme.board.x")
    assert Grant.matches?("acme.board.*", "acme.board.x.y")
    refute Grant.matches?("acme.board.*", "acme.board")
    refute Grant.matches?("acme.board.*", "acme.boardroom.x")
  end
end
