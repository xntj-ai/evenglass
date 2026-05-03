defmodule EvenglassWeb.PCUserLive.TotpVerify do
  @moduledoc """
  TOTP challenge for users who have already enrolled.

  Mounted only when the session carries a valid `pc_user_pending_2fa_id`
  marker. On submit, the form posts to `POST /pc_users/totp/verify` which
  calls `Accounts.verify_totp/2` and, on success, finalizes the session
  via `PCUserAuth.complete_log_in_pc_user/1`.

  If the half-authenticated user somehow reaches this page without an
  enrolled TOTP secret (shouldn't happen — `initiate_two_factor` routes
  unenrolled users to `:setup`), we redirect them to setup.
  """

  use EvenglassWeb, :live_view

  alias Evenglass.Accounts.PCUser

  on_mount {EvenglassWeb.PCUserAuth, :require_pending_2fa}

  @impl true
  def mount(_params, _session, socket) do
    pc_user = socket.assigns.pending_pc_user

    if PCUser.totp_enrolled?(pc_user) do
      {:ok,
       socket
       |> assign(:pc_user, pc_user)
       |> assign(:form, to_form(%{"code" => ""}, as: "totp"))
       |> assign(:trigger_submit, false)}
    else
      {:ok, redirect(socket, to: ~p"/pc_users/totp/setup")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Pending 2FA pages have no logged-in scope yet — Layouts.app's
         current_scope attr defaults to nil, which is exactly right here. --%>
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Two-factor authentication
            <:subtitle>Open your authenticator app and enter the 6-digit code.</:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="totp_verify_form"
          action={~p"/pc_users/totp/verify"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            field={@form[:code]}
            type="text"
            label="6-digit code"
            inputmode="numeric"
            autocomplete="one-time-code"
            pattern="[0-9]{6}"
            maxlength="6"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full" phx-disable-with="Verifying...">
            Verify and continue
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("submit", %{"totp" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "totp"), trigger_submit: true)}
  end
end
