defmodule EvenglassWeb.PCUserAuth do
  use EvenglassWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Evenglass.Accounts
  alias Evenglass.Accounts.{PCUser, Scope}

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in PCUserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_evenglass_web_pc_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  # How long the half-authenticated state (password verified, awaiting TOTP)
  # may sit in the session before we force the user back to the password page.
  @two_factor_pending_max_age_seconds 10 * 60

  @doc """
  Stages a half-authenticated session: the user has cleared the first factor
  (password or magic link) but still owes us a TOTP. We park the pc_user_id
  plus the user's remember-me preference under dedicated session keys (NOT
  `:pc_user_token`) and redirect to the appropriate TOTP page.

  Critical: this MUST be called instead of `log_in_pc_user/3` from any code
  path that has only verified the first factor. Otherwise 2FA can be bypassed.
  """
  def initiate_two_factor(conn, %PCUser{} = pc_user, params \\ %{}) do
    conn
    |> renew_session(pc_user)
    |> put_session(:pc_user_pending_2fa_id, pc_user.id)
    |> put_session(:pc_user_pending_2fa_at, System.system_time(:second))
    |> put_session(:pc_user_pending_2fa_remember_me, params["remember_me"] == "true")
    |> redirect(to: two_factor_path_for(pc_user))
  end

  defp two_factor_path_for(%PCUser{totp_confirmed_at: %DateTime{}}), do: ~p"/pc_users/totp/verify"
  defp two_factor_path_for(%PCUser{}), do: ~p"/pc_users/totp/setup"

  @doc """
  Promotes the half-authenticated session to a full session after a successful
  TOTP. Reads the pending pc_user_id + remember-me preference from the session,
  loads the user, issues a real session token, and clears the 2FA marker.

  Returns a redirected conn pointing at the user's stored return path (if any)
  or `signed_in_path/1`.
  """
  def complete_log_in_pc_user(conn) do
    pc_user_id = get_session(conn, :pc_user_pending_2fa_id)
    remember_me = get_session(conn, :pc_user_pending_2fa_remember_me)
    pc_user = pc_user_id && Accounts.get_pc_user!(pc_user_id)
    pc_user_return_to = get_session(conn, :pc_user_return_to)

    conn
    |> clear_pending_two_factor()
    |> create_or_extend_session(pc_user, %{"remember_me" => to_string(remember_me)})
    |> redirect(to: pc_user_return_to || signed_in_path(conn))
  end

  @doc """
  Reads the pending 2FA marker. Returns `{:ok, pc_user}` if a non-expired pending
  state exists, otherwise `:error`. Used by Controllers + LiveViews to gate the
  TOTP setup/verify pages without duplicating the session-key logic.
  """
  def fetch_pending_two_factor(conn_or_session) do
    pending_id = get_session_value(conn_or_session, :pc_user_pending_2fa_id)
    pending_at = get_session_value(conn_or_session, :pc_user_pending_2fa_at)
    now = System.system_time(:second)

    cond do
      is_nil(pending_id) or is_nil(pending_at) ->
        :error

      now - pending_at > @two_factor_pending_max_age_seconds ->
        :error

      true ->
        case Accounts.get_pc_user!(pending_id) do
          %PCUser{} = pc_user -> {:ok, pc_user}
          _ -> :error
        end
    end
  end

  defp get_session_value(%Plug.Conn{} = conn, key), do: get_session(conn, key)
  defp get_session_value(session, key) when is_map(session), do: session[Atom.to_string(key)]

  defp clear_pending_two_factor(conn) do
    conn
    |> delete_session(:pc_user_pending_2fa_id)
    |> delete_session(:pc_user_pending_2fa_at)
    |> delete_session(:pc_user_pending_2fa_remember_me)
  end

  @doc """
  Logs the pc_user in directly without a 2FA challenge. Reserved for callers
  that have already enforced both factors (e.g. `complete_log_in_pc_user/1`).
  Public-facing login paths must go through `initiate_two_factor/3`.
  """
  def log_in_pc_user(conn, pc_user, params \\ %{}) do
    pc_user_return_to = get_session(conn, :pc_user_return_to)

    conn
    |> create_or_extend_session(pc_user, params)
    |> redirect(to: pc_user_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the pc_user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_pc_user(conn) do
    pc_user_token = get_session(conn, :pc_user_token)
    pc_user_token && Accounts.delete_pc_user_session_token(pc_user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      EvenglassWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the pc_user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_pc_user(conn, _opts) do
    with {token, conn} <- ensure_pc_user_token(conn),
         {pc_user, token_inserted_at} <- Accounts.get_pc_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_pc_user(pc_user))
      |> maybe_reissue_pc_user_session_token(pc_user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_pc_user(nil))
    end
  end

  defp ensure_pc_user_token(conn) do
    if token = get_session(conn, :pc_user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:pc_user_remember_me, true)}
      else
        nil
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_pc_user_session_token(conn, pc_user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, pc_user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, pc_user, params) do
    token = Accounts.generate_pc_user_session_token(pc_user)
    remember_me = get_session(conn, :pc_user_remember_me)

    conn
    |> renew_session(pc_user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the pc_user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, pc_user) when conn.assigns.current_scope.pc_user.id == pc_user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _pc_user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _pc_user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:pc_user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:pc_user_token, token)
    |> put_session(:live_socket_id, pc_user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      EvenglassWeb.Endpoint.broadcast(pc_user_session_topic(token), "disconnect", %{})
    end)
  end

  defp pc_user_session_topic(token), do: "pc_users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on pc_user_token, or nil if
      there's no pc_user_token or no matching pc_user.

    * `:require_authenticated` - Authenticates the pc_user from the session,
      and assigns the current_scope to socket assigns based
      on pc_user_token.
      Redirects to login page if there's no logged pc_user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule EvenglassWeb.PageLive do
        use EvenglassWeb, :live_view

        on_mount {EvenglassWeb.PCUserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{EvenglassWeb.PCUserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.pc_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/pc_users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(socket.assigns.current_scope.pc_user, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must re-authenticate to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/pc_users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_pending_2fa, _params, session, socket) do
    case fetch_pending_two_factor(session) do
      {:ok, pc_user} ->
        {:cont, Phoenix.Component.assign(socket, :pending_pc_user, pc_user)}

      :error ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(
            :error,
            "Your login session expired — please sign in again."
          )
          |> Phoenix.LiveView.redirect(to: ~p"/pc_users/log-in")

        {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      {pc_user, _} =
        if pc_user_token = session["pc_user_token"] do
          Accounts.get_pc_user_by_session_token(pc_user_token)
        end || {nil, nil}

      Scope.for_pc_user(pc_user)
    end)
  end

  @doc "Returns the path to redirect to after log in."
  # An admin in a sudo-mode re-auth flow already had a session — keep them in
  # settings so update-password etc. can complete. Anyone else lands on the
  # devices admin view (the canonical entrypoint to the operator UI).
  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{pc_user: %PCUser{}}}}) do
    ~p"/pc_users/settings"
  end

  def signed_in_path(_), do: ~p"/admin/devices"

  @doc """
  Plug for routes that require the pc_user to be authenticated.
  """
  def require_authenticated_pc_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.pc_user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/pc_users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :pc_user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
