defmodule EvenglassWeb.PCUserAuthTest do
  use EvenglassWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias Evenglass.Accounts
  alias Evenglass.Accounts.Scope
  alias EvenglassWeb.PCUserAuth

  import Evenglass.AccountsFixtures

  @remember_me_cookie "_evenglass_web_pc_user_remember_me"
  @remember_me_cookie_max_age 60 * 60 * 24 * 14

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, EvenglassWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{pc_user: %{pc_user_fixture() | authenticated_at: DateTime.utc_now(:second)}, conn: conn}
  end

  describe "log_in_pc_user/3" do
    test "stores the pc_user token in the session", %{conn: conn, pc_user: pc_user} do
      conn = PCUserAuth.log_in_pc_user(conn, pc_user)
      assert token = get_session(conn, :pc_user_token)
      assert get_session(conn, :live_socket_id) == "pc_users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_pc_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, pc_user: pc_user} do
      conn = conn |> put_session(:to_be_removed, "value") |> PCUserAuth.log_in_pc_user(pc_user)
      refute get_session(conn, :to_be_removed)
    end

    test "keeps session when re-authenticating", %{conn: conn, pc_user: pc_user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_pc_user(pc_user))
        |> put_session(:to_be_removed, "value")
        |> PCUserAuth.log_in_pc_user(pc_user)

      assert get_session(conn, :to_be_removed)
    end

    test "clears session when pc_user does not match when re-authenticating", %{
      conn: conn,
      pc_user: pc_user
    } do
      other_pc_user = pc_user_fixture()

      conn =
        conn
        |> assign(:current_scope, Scope.for_pc_user(other_pc_user))
        |> put_session(:to_be_removed, "value")
        |> PCUserAuth.log_in_pc_user(pc_user)

      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, pc_user: pc_user} do
      conn =
        conn |> put_session(:pc_user_return_to, "/hello") |> PCUserAuth.log_in_pc_user(pc_user)

      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, pc_user: pc_user} do
      conn =
        conn |> fetch_cookies() |> PCUserAuth.log_in_pc_user(pc_user, %{"remember_me" => "true"})

      assert get_session(conn, :pc_user_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :pc_user_remember_me) == true

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :pc_user_token)
      assert max_age == @remember_me_cookie_max_age
    end

    test "redirects to settings when pc_user is already logged in", %{
      conn: conn,
      pc_user: pc_user
    } do
      conn =
        conn
        |> assign(:current_scope, Scope.for_pc_user(pc_user))
        |> PCUserAuth.log_in_pc_user(pc_user)

      assert redirected_to(conn) == ~p"/pc_users/settings"
    end

    test "writes a cookie if remember_me was set in previous session", %{
      conn: conn,
      pc_user: pc_user
    } do
      conn =
        conn |> fetch_cookies() |> PCUserAuth.log_in_pc_user(pc_user, %{"remember_me" => "true"})

      assert get_session(conn, :pc_user_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :pc_user_remember_me) == true

      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, EvenglassWeb.Endpoint.config(:secret_key_base))
        |> fetch_cookies()
        |> init_test_session(%{pc_user_remember_me: true})

      # the conn is already logged in and has the remember_me cookie set,
      # now we log in again and even without explicitly setting remember_me,
      # the cookie should be set again
      conn = conn |> PCUserAuth.log_in_pc_user(pc_user, %{})
      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :pc_user_token)
      assert max_age == @remember_me_cookie_max_age
      assert get_session(conn, :pc_user_remember_me) == true
    end
  end

  describe "logout_pc_user/1" do
    test "erases session and cookies", %{conn: conn, pc_user: pc_user} do
      pc_user_token = Accounts.generate_pc_user_session_token(pc_user)

      conn =
        conn
        |> put_session(:pc_user_token, pc_user_token)
        |> put_req_cookie(@remember_me_cookie, pc_user_token)
        |> fetch_cookies()
        |> PCUserAuth.log_out_pc_user()

      refute get_session(conn, :pc_user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_pc_user_by_session_token(pc_user_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "pc_users_sessions:abcdef-token"
      EvenglassWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> PCUserAuth.log_out_pc_user()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if pc_user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> PCUserAuth.log_out_pc_user()
      refute get_session(conn, :pc_user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_scope_for_pc_user/2" do
    test "authenticates pc_user from session", %{conn: conn, pc_user: pc_user} do
      pc_user_token = Accounts.generate_pc_user_session_token(pc_user)

      conn =
        conn
        |> put_session(:pc_user_token, pc_user_token)
        |> PCUserAuth.fetch_current_scope_for_pc_user([])

      assert conn.assigns.current_scope.pc_user.id == pc_user.id
      assert conn.assigns.current_scope.pc_user.authenticated_at == pc_user.authenticated_at
      assert get_session(conn, :pc_user_token) == pc_user_token
    end

    test "authenticates pc_user from cookies", %{conn: conn, pc_user: pc_user} do
      logged_in_conn =
        conn |> fetch_cookies() |> PCUserAuth.log_in_pc_user(pc_user, %{"remember_me" => "true"})

      pc_user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> PCUserAuth.fetch_current_scope_for_pc_user([])

      assert conn.assigns.current_scope.pc_user.id == pc_user.id
      assert conn.assigns.current_scope.pc_user.authenticated_at == pc_user.authenticated_at
      assert get_session(conn, :pc_user_token) == pc_user_token
      assert get_session(conn, :pc_user_remember_me)

      assert get_session(conn, :live_socket_id) ==
               "pc_users_sessions:#{Base.url_encode64(pc_user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, pc_user: pc_user} do
      _ = Accounts.generate_pc_user_session_token(pc_user)
      conn = PCUserAuth.fetch_current_scope_for_pc_user(conn, [])
      refute get_session(conn, :pc_user_token)
      refute conn.assigns.current_scope
    end

    test "reissues a new token after a few days and refreshes cookie", %{
      conn: conn,
      pc_user: pc_user
    } do
      logged_in_conn =
        conn |> fetch_cookies() |> PCUserAuth.log_in_pc_user(pc_user, %{"remember_me" => "true"})

      token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      offset_pc_user_token(token, -10, :day)
      {pc_user, _} = Accounts.get_pc_user_by_session_token(token)

      conn =
        conn
        |> put_session(:pc_user_token, token)
        |> put_session(:pc_user_remember_me, true)
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> PCUserAuth.fetch_current_scope_for_pc_user([])

      assert conn.assigns.current_scope.pc_user.id == pc_user.id
      assert conn.assigns.current_scope.pc_user.authenticated_at == pc_user.authenticated_at
      assert new_token = get_session(conn, :pc_user_token)
      assert new_token != token
      assert %{value: new_signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert new_signed_token != signed_token
      assert max_age == @remember_me_cookie_max_age
    end
  end

  describe "on_mount :mount_current_scope" do
    setup %{conn: conn} do
      %{conn: PCUserAuth.fetch_current_scope_for_pc_user(conn, [])}
    end

    test "assigns current_scope based on a valid pc_user_token", %{conn: conn, pc_user: pc_user} do
      pc_user_token = Accounts.generate_pc_user_session_token(pc_user)
      session = conn |> put_session(:pc_user_token, pc_user_token) |> get_session()

      {:cont, updated_socket} =
        PCUserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope.pc_user.id == pc_user.id
    end

    test "assigns nil to current_scope assign if there isn't a valid pc_user_token", %{conn: conn} do
      pc_user_token = "invalid_token"
      session = conn |> put_session(:pc_user_token, pc_user_token) |> get_session()

      {:cont, updated_socket} =
        PCUserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope == nil
    end

    test "assigns nil to current_scope assign if there isn't a pc_user_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        PCUserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_authenticated" do
    test "authenticates current_scope based on a valid pc_user_token", %{
      conn: conn,
      pc_user: pc_user
    } do
      pc_user_token = Accounts.generate_pc_user_session_token(pc_user)
      session = conn |> put_session(:pc_user_token, pc_user_token) |> get_session()

      {:cont, updated_socket} =
        PCUserAuth.on_mount(:require_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope.pc_user.id == pc_user.id
    end

    test "redirects to login page if there isn't a valid pc_user_token", %{conn: conn} do
      pc_user_token = "invalid_token"
      session = conn |> put_session(:pc_user_token, pc_user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: EvenglassWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = PCUserAuth.on_mount(:require_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_scope == nil
    end

    test "redirects to login page if there isn't a pc_user_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: EvenglassWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = PCUserAuth.on_mount(:require_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_sudo_mode" do
    test "allows pc_users that have authenticated in the last 10 minutes", %{
      conn: conn,
      pc_user: pc_user
    } do
      pc_user_token = Accounts.generate_pc_user_session_token(pc_user)
      session = conn |> put_session(:pc_user_token, pc_user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: EvenglassWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:cont, _updated_socket} =
               PCUserAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end

    test "redirects when authentication is too old", %{conn: conn, pc_user: pc_user} do
      eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)
      pc_user = %{pc_user | authenticated_at: eleven_minutes_ago}
      pc_user_token = Accounts.generate_pc_user_session_token(pc_user)
      {pc_user, token_inserted_at} = Accounts.get_pc_user_by_session_token(pc_user_token)
      assert DateTime.compare(token_inserted_at, pc_user.authenticated_at) == :gt
      session = conn |> put_session(:pc_user_token, pc_user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: EvenglassWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, _updated_socket} =
               PCUserAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end
  end

  describe "require_authenticated_pc_user/2" do
    setup %{conn: conn} do
      %{conn: PCUserAuth.fetch_current_scope_for_pc_user(conn, [])}
    end

    test "redirects if pc_user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> PCUserAuth.require_authenticated_pc_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/pc_users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> PCUserAuth.require_authenticated_pc_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :pc_user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> PCUserAuth.require_authenticated_pc_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :pc_user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> PCUserAuth.require_authenticated_pc_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :pc_user_return_to)
    end

    test "does not redirect if pc_user is authenticated", %{conn: conn, pc_user: pc_user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_pc_user(pc_user))
        |> PCUserAuth.require_authenticated_pc_user([])

      refute conn.halted
      refute conn.status
    end
  end

  describe "disconnect_sessions/1" do
    test "broadcasts disconnect messages for each token" do
      tokens = [%{token: "token1"}, %{token: "token2"}]

      for %{token: token} <- tokens do
        EvenglassWeb.Endpoint.subscribe("pc_users_sessions:#{Base.url_encode64(token)}")
      end

      PCUserAuth.disconnect_sessions(tokens)

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: "pc_users_sessions:dG9rZW4x"
      }

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: "pc_users_sessions:dG9rZW4y"
      }
    end
  end
end
