defmodule EvenglassWeb.PCUserSessionControllerTest do
  use EvenglassWeb.ConnCase, async: true

  import Evenglass.AccountsFixtures
  alias Evenglass.Accounts

  setup do
    %{unconfirmed_pc_user: unconfirmed_pc_user_fixture(), pc_user: pc_user_fixture()}
  end

  describe "POST /pc_users/log-in - email and password" do
    test "logs the pc_user in", %{conn: conn, pc_user: pc_user} do
      pc_user = set_password(pc_user)

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"email" => pc_user.email, "password" => valid_pc_user_password()}
        })

      assert get_session(conn, :pc_user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ pc_user.email
      assert response =~ ~p"/pc_users/settings"
      assert response =~ ~p"/pc_users/log-out"
    end

    test "logs the pc_user in with remember me", %{conn: conn, pc_user: pc_user} do
      pc_user = set_password(pc_user)

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{
            "email" => pc_user.email,
            "password" => valid_pc_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_evenglass_web_pc_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the pc_user in with return to", %{conn: conn, pc_user: pc_user} do
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

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, pc_user: pc_user} do
      conn =
        post(conn, ~p"/pc_users/log-in?mode=password", %{
          "pc_user" => %{"email" => pc_user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/pc_users/log-in"
    end
  end

  describe "POST /pc_users/log-in - magic link" do
    test "logs the pc_user in", %{conn: conn, pc_user: pc_user} do
      {token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"token" => token}
        })

      assert get_session(conn, :pc_user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ pc_user.email
      assert response =~ ~p"/pc_users/settings"
      assert response =~ ~p"/pc_users/log-out"
    end

    test "confirms unconfirmed pc_user", %{conn: conn, unconfirmed_pc_user: pc_user} do
      {token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)
      refute pc_user.confirmed_at

      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :pc_user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Pc user confirmed successfully."

      assert Accounts.get_pc_user!(pc_user.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ pc_user.email
      assert response =~ ~p"/pc_users/settings"
      assert response =~ ~p"/pc_users/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/pc_users/log-in", %{
          "pc_user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/pc_users/log-in"
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
end
