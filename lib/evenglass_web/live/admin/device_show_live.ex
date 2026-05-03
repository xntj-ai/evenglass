defmodule EvenglassWeb.Admin.DeviceShowLive do
  @moduledoc """
  Per-device admin view: metadata + recent events + revoke button.

  Revoking clears the device's `jti` (so any outstanding `device_token`
  fails the `jti == device.jti` check inside `Plugs.AuthenticatedAPI`)
  and broadcasts `disconnect` on the device's `user_socket:<id>` topic
  so any active Channel connection drops immediately.
  """

  use EvenglassWeb, :live_view

  alias Evenglass.{Devices, Events}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Devices.get_device(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Device not found.")
         |> push_navigate(to: ~p"/admin/devices")}

      device ->
        if connected?(socket), do: Events.subscribe()

        {:ok,
         socket
         |> assign(:page_title, "Device #{String.slice(device.id, 0, 8)}")
         |> assign(:device, device)
         |> assign(:events, Events.list_recent_events_for_device(device.id, 20))}
    end
  end

  @impl true
  def handle_info({:event_created, event}, socket) do
    if event.session && event.session.device_id == socket.assigns.device.id do
      {:noreply,
       update(socket, :events, fn current ->
         [event | current] |> Enum.take(20)
       end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke", _params, %{assigns: %{device: device}} = socket) do
    revoked = Devices.revoke!(device)
    EvenglassWeb.Endpoint.broadcast("user_socket:#{device.id}", "disconnect", %{})

    {:noreply,
     socket
     |> assign(:device, revoked)
     |> put_flash(:info, "Device revoked. Active connections will drop within seconds.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-semibold">
          Device <span class="font-mono text-base opacity-70">{@device.id}</span>
        </h1>
        <.link navigate={~p"/admin/devices"} class="link link-primary text-sm">
          ← back to devices
        </.link>
      </div>

      <div class="rounded-lg border border-base-300 p-6">
        <dl class="grid grid-cols-1 gap-y-3 sm:grid-cols-3 sm:gap-x-6">
          <dt class="text-sm font-medium opacity-70">Glasses serial</dt>
          <dd class="sm:col-span-2 font-mono text-sm">
            {@device.glasses_serial || "—"}
          </dd>

          <dt class="text-sm font-medium opacity-70">Last seen</dt>
          <dd class="sm:col-span-2 font-mono text-xs">
            <%= if @device.last_seen_at do %>
              {Calendar.strftime(@device.last_seen_at, "%Y-%m-%d %H:%M:%S")} UTC
            <% else %>
              never
            <% end %>
          </dd>

          <dt class="text-sm font-medium opacity-70">Status</dt>
          <dd class="sm:col-span-2">
            <%= if @device.revoked_at do %>
              <span class="badge badge-error">
                revoked at {Calendar.strftime(@device.revoked_at, "%Y-%m-%d %H:%M:%S")} UTC
              </span>
            <% else %>
              <span class="badge badge-success">active</span>
            <% end %>
          </dd>

          <dt class="text-sm font-medium opacity-70">Token jti</dt>
          <dd class="sm:col-span-2 font-mono text-xs opacity-80">
            {@device.jti || "—"}
          </dd>
        </dl>

        <div class="mt-6 border-t border-base-300 pt-6">
          <%= if @device.revoked_at do %>
            <p class="text-sm opacity-70">Already revoked.</p>
          <% else %>
            <button
              phx-click="revoke"
              data-confirm="Revoke this device? Any active Hub App will be disconnected and must re-enroll."
              class="btn btn-error btn-sm"
            >
              Revoke device
            </button>
          <% end %>
        </div>
      </div>

      <h2 class="mt-8 mb-3 text-lg font-semibold">Recent events</h2>
      <div :if={@events == []} class="alert">
        <span>No events for this device yet.</span>
      </div>
      <div :if={@events != []} class="overflow-x-auto rounded-lg border border-base-300">
        <table class="table table-sm table-zebra">
          <thead>
            <tr>
              <th>Time (UTC)</th>
              <th>Direction</th>
              <th>Type</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ev <- @events}>
              <td class="font-mono text-xs">
                {Calendar.strftime(ev.inserted_at, "%H:%M:%S")}
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  ev.direction == "up" && "badge-info",
                  ev.direction == "down" && "badge-warning"
                ]}>
                  {ev.direction}
                </span>
              </td>
              <td class="font-mono text-xs">{ev.type}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
