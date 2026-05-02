defmodule EvenglassWeb.PCUserLive.ConfirmationTest do
  use EvenglassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Evenglass.AccountsFixtures

  alias Evenglass.Accounts

  setup do
    %{unconfirmed_pc_user: unconfirmed_pc_user_fixture(), confirmed_pc_user: pc_user_fixture()}
  end

  describe "Confirm pc_user" do
    test "renders confirmation page for unconfirmed pc_user", %{
      conn: conn,
      unconfirmed_pc_user: pc_user
    } do
      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_login_instructions(pc_user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/pc_users/log-in/#{token}")
      assert html =~ "Confirm and stay logged in"
    end

    test "renders login page for confirmed pc_user", %{conn: conn, confirmed_pc_user: pc_user} do
      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_login_instructions(pc_user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/pc_users/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Keep me logged in on this device"
    end

    test "renders login page for already logged in pc_user", %{
      conn: conn,
      confirmed_pc_user: pc_user
    } do
      conn = log_in_pc_user(conn, pc_user)

      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_login_instructions(pc_user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/pc_users/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Log in"
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_pc_user: pc_user} do
      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_login_instructions(pc_user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in/#{token}")

      form = form(lv, "#confirmation_form", %{"pc_user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "PCUser confirmed successfully"

      assert Accounts.get_pc_user!(pc_user.id).confirmed_at
      # we are logged in now
      assert get_session(conn, :pc_user_token)
      assert redirected_to(conn) == ~p"/"

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/pc_users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/pc_users/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "logs confirmed pc_user in without changing confirmed_at", %{
      conn: conn,
      confirmed_pc_user: pc_user
    } do
      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_login_instructions(pc_user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in/#{token}")

      form = form(lv, "#login_form", %{"pc_user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Welcome back!"

      assert Accounts.get_pc_user!(pc_user.id).confirmed_at == pc_user.confirmed_at

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/pc_users/log-in/#{token}")
        |> follow_redirect(conn, ~p"/pc_users/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "raises error for invalid token", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/pc_users/log-in/invalid-token")
        |> follow_redirect(conn, ~p"/pc_users/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end
  end
end
