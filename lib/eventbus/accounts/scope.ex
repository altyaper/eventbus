defmodule Eventbus.Accounts.Scope do
  @moduledoc """
  The caller's scope, assigned as `@current_scope` in conns and LiveViews.
  Holds the logged-in user; `nil` scope means nobody is logged in.
  """

  alias Eventbus.Accounts.User

  defstruct user: nil

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil

  def superadmin?(%__MODULE__{user: %User{role: "superadmin"}}), do: true
  def superadmin?(_scope), do: false

  @doc """
  Whether the user confirmed their email. Unconfirmed users can't create
  apps and their sandbox app is limited to a few topics.
  """
  def confirmed?(%__MODULE__{user: %User{confirmed_at: %DateTime{}}}), do: true
  def confirmed?(_scope), do: false
end
