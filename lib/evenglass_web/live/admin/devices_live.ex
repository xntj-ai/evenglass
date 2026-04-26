defmodule EvenglassWeb.Admin.DevicesLive do
  use EvenglassWeb, :live_view

  alias Evenglass.Sessions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Evenglass.Events.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Devices")
     |> assign_devices()}
  end

  @impl true
  def handle_info({:event_created, _event}, socket) do
    # New event may have created a new session or refreshed last_seen_at;
    # cheapest correct path is reload the small device list.
    {:noreply, assign_devices(socket)}
  end

  defp assign_devices(socket), do: assign(socket, :devices, Sessions.list_sessions())

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-semibold">Devices</h1>
        <.link navigate={~p"/admin/events"} class="link link-primary text-sm">
          all events →
        </.link>
      </div>

      <div :if={@devices == []} class="alert">
        <span>No devices yet — POST to <code>/api/g2/events</code> to register one.</span>
      </div>

      <div :if={@devices != []} class="overflow-x-auto rounded-lg border border-base-300">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>Device ID</th>
              <th>Last Seen (UTC)</th>
              <th>Events</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={device <- @devices}>
              <td class="font-mono text-sm">{device.device_id}</td>
              <td class="font-mono text-xs">
                {Calendar.strftime(device.last_seen_at || device.inserted_at, "%Y-%m-%d %H:%M:%S")}
              </td>
              <td>
                <.link
                  navigate={~p"/admin/events?device=#{device.device_id}"}
                  class="link link-primary"
                >
                  view stream →
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
