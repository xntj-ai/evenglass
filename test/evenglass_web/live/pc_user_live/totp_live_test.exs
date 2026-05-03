defmodule EvenglassWeb.PCUserLive.TotpLiveTest do
  @moduledoc """
  Mount + render coverage for the TOTP setup + verify LiveViews.

  These pages run in the half-authenticated `:require_pending_2fa` flow,
  so the on_mount only assigns `:pending_pc_user`, NOT `:current_scope`.
  An earlier version of the templates referenced `@current_scope` and
  crashed at render time with KeyError — controller tests that only
  asserted `redirected_to/1` never exercised the render path and missed
  the regression. These tests do, by calling `live/2` (which runs both
  mount AND the initial render).
  """

  use EvenglassWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Evenglass.AccountsFixtures

  describe "GET /pc_users/totp/setup" do
    test "renders the QR + form when the half-auth marker is present", %{conn: conn} do
      pc_user = pc_user_fixture() |> set_password()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{
          "pc_user_pending_2fa_id" => pc_user.id,
          "pc_user_pending_2fa_at" => System.system_time(:second)
        })

      {:ok, _lv, html} = live(conn, ~p"/pc_users/totp/setup")

      assert html =~ "Set up two-factor authentication"
      assert html =~ "6-digit code"
      # QR svg is non-trivial; just check the wrapper rendered.
      assert html =~ "<svg"
    end

    test "redirects to log-in without a pending 2FA marker", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/pc_users/log-in"}}} =
               live(conn, ~p"/pc_users/totp/setup")
    end
  end

  describe "GET /pc_users/totp/verify" do
    test "renders the OTP form for an enrolled user mid-2FA", %{conn: conn} do
      pc_user = pc_user_fixture() |> set_password()
      {:ok, pc_user} = Evenglass.Accounts.setup_totp(pc_user)
      otp = NimbleTOTP.verification_code(pc_user.totp_secret)
      {:ok, pc_user} = Evenglass.Accounts.confirm_totp(pc_user, otp)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{
          "pc_user_pending_2fa_id" => pc_user.id,
          "pc_user_pending_2fa_at" => System.system_time(:second)
        })

      {:ok, _lv, html} = live(conn, ~p"/pc_users/totp/verify")

      assert html =~ "Two-factor authentication"
      assert html =~ "6-digit code"
    end

    test "redirects an unenrolled user to /pc_users/totp/setup", %{conn: conn} do
      pc_user = pc_user_fixture() |> set_password()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{
          "pc_user_pending_2fa_id" => pc_user.id,
          "pc_user_pending_2fa_at" => System.system_time(:second)
        })

      assert {:error, {:redirect, %{to: "/pc_users/totp/setup"}}} =
               live(conn, ~p"/pc_users/totp/verify")
    end
  end
end
