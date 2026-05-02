defmodule EvenglassWeb.PCUserLive.LoginTest do
  use EvenglassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Evenglass.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pc_users/log-in")

      assert html =~ "Log in"
      assert html =~ "Register"
      assert html =~ "Log in with email"
    end
  end

  describe "pc_user login - magic link" do
    test "sends magic link email when pc_user exists", %{conn: conn} do
      pc_user = pc_user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", pc_user: %{email: pc_user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/pc_users/log-in")

      assert html =~ "If your email is in our system"

      assert Evenglass.Repo.get_by!(Evenglass.Accounts.PCUserToken, pc_user_id: pc_user.id).context ==
               "login"
    end

    test "does not disclose if pc_user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", pc_user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/pc_users/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "pc_user login - password" do
    test "redirects if pc_user logs in with valid credentials", %{conn: conn} do
      pc_user = pc_user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in")

      form =
        form(lv, "#login_form_password",
          pc_user: %{email: pc_user.email, password: valid_pc_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in")

      form =
        form(lv, "#login_form_password", pc_user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/pc_users/log-in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pc_users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/pc_users/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      pc_user = pc_user_fixture()
      %{pc_user: pc_user, conn: log_in_pc_user(conn, pc_user)}
    end

    test "shows login page with email filled in", %{conn: conn, pc_user: pc_user} do
      {:ok, _lv, html} = live(conn, ~p"/pc_users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="pc_user[email]" id="login_form_magic_email" value="#{pc_user.email}")
    end
  end
end
