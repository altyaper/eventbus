defmodule Eventbus.Accounts.UserNotifier do
  @moduledoc """
  The account emails: plain text, one link each. The sender comes from the
  `:mail_from` config (`MAIL_FROM` in production), either a bare address or
  `"Name <address>"`.
  """

  import Swoosh.Email

  alias Eventbus.Mailer

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your eventbus email", """
    Hi,

    Confirm your email to create more apps and lift the 5-topic limit on
    your sandbox app:

    #{url}

    The link works for 7 days. If you didn't sign up for eventbus, ignore
    this email.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your eventbus password", """
    Hi,

    Someone asked to reset the password for this eventbus account. Choose a
    new one here:

    #{url}

    The link works for 24 hours. Resetting logs out every session. If it
    wasn't you, ignore this email and your password stays the same.
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(sender())
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp sender do
    case Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, Application.fetch_env!(:eventbus, :mail_from)) do
      [_, name, address] -> {name, address}
      nil -> {"eventbus", String.trim(Application.fetch_env!(:eventbus, :mail_from))}
    end
  end
end
