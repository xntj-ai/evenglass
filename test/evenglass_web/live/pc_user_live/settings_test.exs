defmodule EvenglassWeb.PCUserLive.SettingsTest do
  use EvenglassWeb.ConnCase, async: true

  alias Evenglass.Accounts
  import Phoenix.LiveViewTest
  import Evenglass.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_pc_user(pc_user_fixture())
        |> live(~p"/pc_users/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "redirects if pc_user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/pc_users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/pc_users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if pc_user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_pc_user(pc_user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/pc_users/settings")
        |> follow_redirect(conn, ~p"/pc_users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      pc_user = pc_user_fixture()
      %{conn: log_in_pc_user(conn, pc_user), pc_user: pc_user}
    end

    test "updates the pc_user email", %{conn: conn, pc_user: pc_user} do
      new_email = unique_pc_user_email()

      {:ok, lv, _html} = live(conn, ~p"/pc_users/settings")

      result =
        lv
        |> form("#email_form", %{
          "pc_user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_pc_user_by_email(pc_user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "pc_user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, pc_user: pc_user} do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/settings")

      result =
        lv
        |> form("#email_form", %{
          "pc_user" => %{"email" => pc_user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      pc_user = pc_user_fixture()
      %{conn: log_in_pc_user(conn, pc_user), pc_user: pc_user}
    end

    test "updates the pc_user password", %{conn: conn, pc_user: pc_user} do
      new_password = valid_pc_user_password()

      {:ok, lv, _html} = live(conn, ~p"/pc_users/settings")

      form =
        form(lv, "#password_form", %{
          "pc_user" => %{
            "email" => pc_user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      # update_password disconnects sessions and re-runs the login flow,
      # which routes through the TOTP gate. Fresh fixture has no enrolled
      # TOTP, so the immediate landing page is /pc_users/totp/setup. The
      # final destination (/pc_users/settings) is preserved via
      # :pc_user_return_to and reached after TOTP setup completes. The
      # session token itself is not rotated until complete_log_in_pc_user/1
      # runs at the end of the 2FA flow.
      assert redirected_to(new_password_conn) == ~p"/pc_users/totp/setup"

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_pc_user_by_email_and_password(pc_user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "pc_user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/settings")

      result =
        lv
        |> form("#password_form", %{
          "pc_user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      pc_user = pc_user_fixture()
      email = unique_pc_user_email()

      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_pc_user_update_email_instructions(
            %{pc_user | email: email},
            pc_user.email,
            url
          )
        end)

      %{conn: log_in_pc_user(conn, pc_user), token: token, email: email, pc_user: pc_user}
    end

    test "updates the pc_user email once", %{
      conn: conn,
      pc_user: pc_user,
      token: token,
      email: email
    } do
      {:error, redirect} = live(conn, ~p"/pc_users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/pc_users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_pc_user_by_email(pc_user.email)
      assert Accounts.get_pc_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/pc_users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/pc_users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, pc_user: pc_user} do
      {:error, redirect} = live(conn, ~p"/pc_users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/pc_users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_pc_user_by_email(pc_user.email)
    end

    test "redirects if pc_user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/pc_users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/pc_users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
