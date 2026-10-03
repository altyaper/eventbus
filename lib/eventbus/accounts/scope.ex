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
end
