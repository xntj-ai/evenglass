defmodule EvenglassWeb.PCUserSessionController do
  use EvenglassWeb, :controller

  alias Evenglass.Accounts
  alias EvenglassWeb.PCUserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Pc user confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"pc_user" => %{"token" => token} = pc_user_params}, info) do
    case Accounts.login_pc_user_by_magic_link(token) do
      {:ok, {pc_user, tokens_to_disconnect}} ->
        PCUserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> PCUserAuth.log_in_pc_user(pc_user, pc_user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/pc_users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"pc_user" => pc_user_params}, info) do
    %{"email" => email, "password" => password} = pc_user_params

    if pc_user = Accounts.get_pc_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> PCUserAuth.log_in_pc_user(pc_user, pc_user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/pc_users/log-in")
    end
  end

  def update_password(conn, %{"pc_user" => pc_user_params} = params) do
    pc_user = conn.assigns.current_scope.pc_user
    true = Accounts.sudo_mode?(pc_user)
    {:ok, {_pc_user, expired_tokens}} = Accounts.update_pc_user_password(pc_user, pc_user_params)

    # disconnect all existing LiveViews with old sessions
    PCUserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:pc_user_return_to, ~p"/pc_users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> PCUserAuth.log_out_pc_user()
  end
end
