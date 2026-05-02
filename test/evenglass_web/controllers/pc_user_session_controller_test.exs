defmodule EvenglassWeb.PCUserSessionControllerTest do
  use EvenglassWeb.ConnCase, async: true

  import Evenglass.AccountsFixtures
  alias Evenglass.Accounts

  setup do
    %{unconfirmed_pc_user: unconfirmed_pc_user_fixture(), pc_user: pc_user_fixture()}
  end

  describe "POST /pc_users/log-in - email and password" do
    test "stages a half-authenticated session and redirects to TOTP setup", %{
      conn: conn,
      pc_user: pc_user
    } do
      pc_user = set_password(pc_user)

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"email" => pc_user.email, "password" => valid_pc_user_password()}
        })

      # 2FA gate: only the pending marker is set, the real session token is NOT.
      assert get_session(conn, :pc_user_pending_2fa_id) == pc_user.id
      refute get_session(conn, :pc_user_token)

      # Fresh user has no TOTP secret yet → routed to setup
      assert redirected_to(conn) == ~p"/pc_users/totp/setup"
    end

    test "captures remember-me preference in pending session", %{conn: conn, pc_user: pc_user} do
      pc_user = set_password(pc_user)

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{
            "email" => pc_user.email,
            "password" => valid_pc_user_password(),
            "remember_me" => "true"
          }
        })

      assert get_session(conn, :pc_user_pending_2fa_remember_me) == true
      # Cookie is not written yet — that happens at complete_log_in_pc_user
      refute conn.resp_cookies["_evenglass_web_pc_user_remember_me"]
      assert redirected_to(conn) == ~p"/pc_users/totp/setup"
    end

    test "preserves pc_user_return_to across the 2FA gate", %{conn: conn, pc_user: pc_user} do
      pc_user = set_password(pc_user)

      conn =
        conn
        |> init_test_session(pc_user_return_to: "/foo/bar")
        |> post(~p"/pc_users/log-in", %{
          "pc_user" => %{
            "email" => pc_user.email,
            "password" => valid_pc_user_password()
          }
        })

      # Goes to TOTP first; the return_to survives in session and is honored
      # by complete_log_in_pc_user/1 once 2FA succeeds.
      assert redirected_to(conn) == ~p"/pc_users/totp/setup"
      assert get_session(conn, :pc_user_return_to) == "/foo/bar"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, pc_user: pc_user} do
      conn =
        post(conn, ~p"/pc_users/log-in?mode=password", %{
          "pc_user" => %{"email" => pc_user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/pc_users/log-in"
      refute get_session(conn, :pc_user_pending_2fa_id)
    end
  end

  describe "POST /pc_users/log-in - magic link" do
    test "stages a half-authenticated session and redirects to TOTP setup", %{
      conn: conn,
      pc_user: pc_user
    } do
      {token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"token" => token}
        })

      assert get_session(conn, :pc_user_pending_2fa_id) == pc_user.id
      refute get_session(conn, :pc_user_token)
      assert redirected_to(conn) == ~p"/pc_users/totp/setup"
    end

    test "confirms unconfirmed pc_user before 2FA gate", %{
      conn: conn,
      unconfirmed_pc_user: pc_user
    } do
      {token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)
      refute pc_user.confirmed_at

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"token" => token},
          "_action" => "confirmed"
        })

      # User account got confirmed even though full login is gated on TOTP
      assert Accounts.get_pc_user!(pc_user.id).confirmed_at

      assert get_session(conn, :pc_user_pending_2fa_id) == pc_user.id
      refute get_session(conn, :pc_user_token)
      assert redirected_to(conn) == ~p"/pc_users/totp/setup"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Pc user confirmed successfully."
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/pc_users/log-in"
      refute get_session(conn, :pc_user_pending_2fa_id)
    end
  end

  describe "POST /pc_users/totp/setup" do
    setup %{conn: conn, pc_user: pc_user} do
      pc_user = set_password(pc_user)
      {:ok, pc_user} = Accounts.setup_totp(pc_user)
      conn = put_pending_2fa(conn, pc_user)
      %{conn: conn, pc_user: pc_user}
    end

    test "completes login on first valid OTP", %{conn: conn, pc_user: pc_user} do
      otp = NimbleTOTP.verification_code(pc_user.totp_secret)

      conn = post(conn, ~p"/pc_users/totp/setup", %{"totp" => %{"code" => otp}})

      assert get_session(conn, :pc_user_token)
      refute get_session(conn, :pc_user_pending_2fa_id)
      assert redirected_to(conn) == ~p"/admin/devices"
      assert Accounts.get_pc_user!(pc_user.id).totp_confirmed_at
    end

    test "rejects an invalid OTP without enrolling", %{conn: conn, pc_user: pc_user} do
      conn = post(conn, ~p"/pc_users/totp/setup", %{"totp" => %{"code" => "000000"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't match"
      assert redirected_to(conn) == ~p"/pc_users/totp/setup"
      refute Accounts.get_pc_user!(pc_user.id).totp_confirmed_at
    end
  end

  describe "POST /pc_users/totp/verify" do
    setup %{conn: conn, pc_user: pc_user} do
      pc_user = set_password(pc_user)
      {:ok, pc_user} = Accounts.setup_totp(pc_user)
      otp = NimbleTOTP.verification_code(pc_user.totp_secret)
      {:ok, pc_user} = Accounts.confirm_totp(pc_user, otp)
      conn = put_pending_2fa(conn, pc_user)
      %{conn: conn, pc_user: pc_user}
    end

    test "completes login on a valid OTP", %{conn: conn, pc_user: pc_user} do
      otp = NimbleTOTP.verification_code(pc_user.totp_secret)

      conn = post(conn, ~p"/pc_users/totp/verify", %{"totp" => %{"code" => otp}})

      assert get_session(conn, :pc_user_token)
      refute get_session(conn, :pc_user_pending_2fa_id)
      assert redirected_to(conn) == ~p"/admin/devices"
    end

    test "rejects an invalid OTP", %{conn: conn} do
      conn = post(conn, ~p"/pc_users/totp/verify", %{"totp" => %{"code" => "000000"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't match"
      assert redirected_to(conn) == ~p"/pc_users/totp/verify"
    end

    test "expired pending session bounces back to log-in", %{conn: conn, pc_user: pc_user} do
      otp = NimbleTOTP.verification_code(pc_user.totp_secret)

      # Force the pending marker to be 11 minutes old (past the 10-min limit)
      stale_at = System.system_time(:second) - 11 * 60

      conn =
        conn
        |> init_test_session(%{
          "pc_user_pending_2fa_id" => pc_user.id,
          "pc_user_pending_2fa_at" => stale_at
        })
        |> post(~p"/pc_users/totp/verify", %{"totp" => %{"code" => otp}})

      assert redirected_to(conn) == ~p"/pc_users/log-in"
      refute get_session(conn, :pc_user_token)
    end
  end

  describe "DELETE /pc_users/log-out" do
    test "logs the pc_user out", %{conn: conn, pc_user: pc_user} do
      conn = conn |> log_in_pc_user(pc_user) |> delete(~p"/pc_users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :pc_user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the pc_user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/pc_users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :pc_user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end

  ## Helpers

  defp put_pending_2fa(conn, pc_user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{
      "pc_user_pending_2fa_id" => pc_user.id,
      "pc_user_pending_2fa_at" => System.system_time(:second)
    })
  end
end
