defmodule EventbusWeb.ConfirmController do
  use EventbusWeb, :controller

  alias Eventbus.Accounts

  @doc """
  The link from the confirmation email. Works logged in or out.
  """
  def show(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email confirmed. You can now create apps and topics freely.")
        |> redirect(to: after_confirm_path(conn))

      :error ->
        conn
        |> put_flash(:error, "That confirmation link is invalid or has expired.")
        |> redirect(to: after_confirm_path(conn))
    end
  end

  @doc """
  The banner's Resend button.
  """
  def resend(%{assigns: %{current_scope: %{user: user}}} = conn, _params) do
    conn =
      case Accounts.deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}")) do
        {:ok, email} ->
          put_flash(conn, :info, "We sent a new confirmation link to #{email}.")

        {:error, :cooldown} ->
          put_flash(conn, :error, "We just sent you a link. Wait a minute before asking again.")

        {:error, :already_confirmed} ->
          put_flash(conn, :info, "Your email is already confirmed.")
      end

    redirect(conn, to: ~p"/apps")
  end

  def resend(conn, _params) do
    conn
    |> put_flash(:error, "Log in to continue.")
    |> redirect(to: ~p"/login")
  end

  defp after_confirm_path(%{assigns: %{current_scope: %{}}}), do: ~p"/apps"
  defp after_confirm_path(_conn), do: ~p"/login"
end
