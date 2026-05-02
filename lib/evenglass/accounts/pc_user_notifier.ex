defmodule Evenglass.Accounts.PCUserNotifier do
  import Swoosh.Email

  alias Evenglass.Mailer
  alias Evenglass.Accounts.PCUser

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Evenglass", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a pc_user email.
  """
  def deliver_update_email_instructions(pc_user, url) do
    deliver(pc_user.email, "Update email instructions", """

    ==============================

    Hi #{pc_user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(pc_user, url) do
    case pc_user do
      %PCUser{confirmed_at: nil} -> deliver_confirmation_instructions(pc_user, url)
      _ -> deliver_magic_link_instructions(pc_user, url)
    end
  end

  defp deliver_magic_link_instructions(pc_user, url) do
    deliver(pc_user.email, "Log in instructions", """

    ==============================

    Hi #{pc_user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(pc_user, url) do
    deliver(pc_user.email, "Confirmation instructions", """

    ==============================

    Hi #{pc_user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
