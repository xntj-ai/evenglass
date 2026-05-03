defmodule EvenglassWeb.Admin.NewDeviceLive do
  @moduledoc """
  Generates a single-use 6-digit enrollment code for a new Hub App pairing.

  The admin types the optional G2 serial, clicks "Generate", and reads off
  the displayed code to the operator who is sitting in front of the Hub
  App's first-launch screen. The code is valid for 10 minutes; a fresh
  click invalidates the previous one for this admin (the previous one is
  not deleted, but the UI no longer shows it — operators should re-issue
  if they lose the screen).
  """

  use EvenglassWeb, :live_view

  alias Evenglass.Devices

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New device")
     |> assign(:code, nil)
     |> assign(:expires_at, nil)
     |> assign(:glasses_serial, "")}
  end

  @impl true
  def handle_event("generate", params, socket) do
    serial =
      params
      |> Map.get("glasses_serial", "")
      |> to_string()
      |> String.trim()

    attrs = if serial == "", do: %{}, else: %{glasses_serial: serial}

    code = Devices.generate_enrollment_code!(attrs)

    {:noreply,
     socket
     |> assign(:code, code.code)
     |> assign(:expires_at, code.expires_at)
     |> assign(:glasses_serial, serial)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, socket |> assign(:code, nil) |> assign(:expires_at, nil)}
  end

  defp expires_in_minutes(nil), do: nil

  defp expires_in_minutes(%DateTime{} = expires_at) do
    diff = DateTime.diff(expires_at, DateTime.utc_now(), :second)
    max(0, div(diff, 60))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-semibold">New device</h1>
        <.link navigate={~p"/admin/devices"} class="link link-primary text-sm">
          ← back to devices
        </.link>
      </div>

      <form phx-submit="generate" class="space-y-4">
        <label class="form-control w-full">
          <div class="label">
            <span class="label-text">Glasses serial (optional)</span>
            <span class="label-text-alt opacity-60">binds the code to one G2 unit</span>
          </div>
          <input
            type="text"
            name="glasses_serial"
            value={@glasses_serial}
            placeholder="G2-ABCD-1234"
            class="input input-bordered w-full font-mono"
          />
        </label>

        <button type="submit" class="btn btn-primary">Generate enrollment code</button>
      </form>

      <div :if={@code} class="mt-8 rounded-lg border border-primary/40 bg-primary/5 p-6">
        <div class="text-sm uppercase tracking-wide text-primary/80">
          Read this to the operator
        </div>
        <div class="mt-2 font-mono text-5xl tracking-widest">{@code}</div>
        <div class="mt-3 text-sm opacity-70">
          Expires in {expires_in_minutes(@expires_at)} min · single-use
          <span :if={@glasses_serial != ""} class="ml-2 badge badge-outline">
            bound to {@glasses_serial}
          </span>
        </div>
        <div class="mt-4">
          <button phx-click="clear" class="btn btn-sm btn-ghost">Hide</button>
        </div>
      </div>
    </div>
    """
  end
end
