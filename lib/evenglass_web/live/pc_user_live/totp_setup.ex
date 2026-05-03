defmodule EvenglassWeb.PCUserLive.TotpSetup do
  @moduledoc """
  First-time TOTP enrollment.

  Mounted only when the session carries a valid `pc_user_pending_2fa_id`
  marker (enforced by `PCUserAuth.on_mount(:require_pending_2fa, ...)`),
  meaning the user has just cleared their first factor.

  On mount we ensure the user has a stored `totp_secret` (generating one
  if absent — `Accounts.setup_totp/1` is idempotent over an unconfirmed
  enrollment, so a reload shows the same QR). We render a QR code, the
  base32 secret as fallback, and a 6-digit form. The form submits to
  `POST /pc_users/totp/setup` which calls `Accounts.confirm_totp/2` and,
  on success, finalizes the session via `PCUserAuth.complete_log_in_pc_user/1`.
  """

  use EvenglassWeb, :live_view

  alias Evenglass.Accounts

  on_mount {EvenglassWeb.PCUserAuth, :require_pending_2fa}

  @impl true
  def mount(_params, _session, socket) do
    pc_user = socket.assigns.pending_pc_user

    case Accounts.setup_totp(pc_user) do
      {:ok, pc_user} ->
        {:ok,
         socket
         |> assign(:pc_user, pc_user)
         |> assign(:totp_uri, Accounts.totp_uri(pc_user))
         |> assign(:totp_base32, Accounts.totp_base32(pc_user))
         |> assign(:qr_svg, qr_svg(Accounts.totp_uri(pc_user)))
         |> assign(:form, to_form(%{"code" => ""}, as: "totp"))
         |> assign(:trigger_submit, false)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Could not set up two-factor authentication.")
         |> redirect(to: ~p"/pc_users/log-in")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Pending 2FA pages have no logged-in scope yet — Layouts.app's
         current_scope attr defaults to nil, which is exactly right here. --%>
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-md space-y-6">
        <div class="text-center">
          <.header>
            Set up two-factor authentication
            <:subtitle>
              Scan the QR code with an authenticator app (1Password, Authy, Google Authenticator, …)
              and enter the 6-digit code below to finish enrollment.
            </:subtitle>
          </.header>
        </div>

        <div class="flex justify-center bg-white p-4 rounded-lg">
          {Phoenix.HTML.raw(@qr_svg)}
        </div>

        <div class="text-xs text-base-content/70 break-all text-center">
          <p class="font-medium mb-1">Or paste this secret manually:</p>
          <code>{@totp_base32}</code>
        </div>

        <.form
          for={@form}
          id="totp_setup_form"
          action={~p"/pc_users/totp/setup"}
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
            Confirm and finish login
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

  ## Helpers

  defp qr_svg(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(color: "#000", background_color: "#fff", width: 220)
  end
end
