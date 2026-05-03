defmodule EvenglassWeb.PCUserSessionController do
  use EvenglassWeb, :controller

  alias Evenglass.{Accounts, RateLimit}
  alias EvenglassWeb.PCUserAuth
  alias EvenglassWeb.Plugs.RateLimit, as: RateLimitPlug

  # 5 attempts / 15min, keyed on (client_ip, email). Combined key prevents
  # a single attacker from grinding multiple accounts from one IP, while
  # still letting legitimate users on the same NAT log in independently.
  @login_scale_ms 900_000
  @login_limit 5

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Pc user confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login → first factor satisfied; route into TOTP flow
  defp create(conn, %{"pc_user" => %{"token" => token} = pc_user_params}, info) do
    case Accounts.login_pc_user_by_magic_link(token) do
      {:ok, {pc_user, tokens_to_disconnect}} ->
        PCUserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> PCUserAuth.initiate_two_factor(pc_user, pc_user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/pc_users/log-in")
    end
  end

  # email + password login → first factor satisfied; route into TOTP flow
  defp create(conn, %{"pc_user" => pc_user_params}, _info) do
    %{"email" => email, "password" => password} = pc_user_params
    email_norm = email |> to_string() |> String.downcase() |> String.trim()
    ip = RateLimitPlug.client_ip(conn)
    rl_key = "admin-login:#{ip}:#{email_norm}"

    case RateLimit.hit(rl_key, @login_scale_ms, @login_limit) do
      {:allow, _count} ->
        if pc_user = Accounts.get_pc_user_by_email_and_password(email, password) do
          PCUserAuth.initiate_two_factor(conn, pc_user, pc_user_params)
        else
          # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
          conn
          |> put_flash(:error, "Invalid email or password")
          |> put_flash(:email, String.slice(email, 0, 160))
          |> redirect(to: ~p"/pc_users/log-in")
        end

      {:deny, retry_after_ms} ->
        mins = div(retry_after_ms, 60_000) + 1

        conn
        |> put_flash(:error, "Too many login attempts. Try again in #{mins} minute(s).")
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

  ## Second factor — TOTP

  @doc """
  Confirms the first OTP after enrollment, persists `totp_confirmed_at`, and
  promotes the half-authenticated session to a full session.
  """
  def setup_totp(conn, %{"totp" => %{"code" => code}}) do
    case PCUserAuth.fetch_pending_two_factor(conn) do
      {:ok, pc_user} ->
        case Accounts.confirm_totp(pc_user, String.trim(code)) do
          {:ok, _pc_user} ->
            conn
            |> put_flash(:info, "Two-factor authentication is now enabled.")
            |> PCUserAuth.complete_log_in_pc_user()

          {:error, :invalid_otp} ->
            conn
            |> put_flash(:error, "That code didn't match — try again.")
            |> redirect(to: ~p"/pc_users/totp/setup")

          {:error, :no_secret} ->
            # Setup page should have populated the secret on mount; if it didn't,
            # bounce the user back so a fresh secret can be generated.
            conn
            |> put_flash(:error, "Setup state lost — please re-scan the QR.")
            |> redirect(to: ~p"/pc_users/totp/setup")
        end

      :error ->
        conn
        |> put_flash(:error, "Your login session expired — please sign in again.")
        |> redirect(to: ~p"/pc_users/log-in")
    end
  end

  @doc "Verifies an OTP from a previously-enrolled user, completing login."
  def verify_totp(conn, %{"totp" => %{"code" => code}}) do
    with {:ok, pc_user} <- PCUserAuth.fetch_pending_two_factor(conn),
         true <- Accounts.verify_totp(pc_user, String.trim(code)) do
      PCUserAuth.complete_log_in_pc_user(conn)
    else
      :error ->
        conn
        |> put_flash(:error, "Your login session expired — please sign in again.")
        |> redirect(to: ~p"/pc_users/log-in")

      false ->
        conn
        |> put_flash(:error, "That code didn't match — try again.")
        |> redirect(to: ~p"/pc_users/totp/verify")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> PCUserAuth.log_out_pc_user()
  end
end
