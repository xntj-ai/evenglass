defmodule EvenglassWeb.Admin.EventsLive do
  use EvenglassWeb, :live_view

  alias Evenglass.Events

  @max_events 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:max_events, @max_events)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    device_filter = params["device"]

    events =
      case device_filter do
        nil -> Events.list_recent_events(@max_events)
        device_id -> Events.list_recent_events_for_device(device_id, @max_events)
      end

    {:noreply,
     socket
     |> assign(:device_filter, device_filter)
     |> stream(:events, events, reset: true, limit: @max_events)}
  end

  @impl true
  def handle_info({:event_created, event}, socket) do
    if matches_filter?(event, socket.assigns.device_filter) do
      {:noreply, stream_insert(socket, :events, event, at: 0)}
    else
      {:noreply, socket}
    end
  end

  defp matches_filter?(_event, nil), do: true
  defp matches_filter?(event, device_id), do: event.session.device_id == device_id

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-semibold">Event Stream</h1>
        <div class="flex items-center gap-3 text-sm">
          <.link navigate={~p"/admin/devices"} class="link link-primary">devices →</.link>
          <span class="opacity-70">last {@max_events} events · auto-refreshing</span>
        </div>
      </div>

      <div :if={@device_filter} class="mb-4 flex items-center gap-2">
        <span class="badge badge-warning">Filter: {@device_filter}</span>
        <.link patch={~p"/admin/events"} class="link link-sm">clear</.link>
      </div>

      <div class="overflow-x-auto rounded-lg border border-base-300">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>Time (UTC)</th>
              <th>Device</th>
              <th>Direction</th>
              <th>Type</th>
              <th>Payload</th>
            </tr>
          </thead>
          <tbody id="events" phx-update="stream">
            <tr :for={{dom_id, event} <- @streams.events} id={dom_id}>
              <td class="font-mono text-xs">{Calendar.strftime(event.inserted_at, "%H:%M:%S")}</td>
              <td class="font-mono text-xs">{event.session.device_id}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  event.direction == "up" && "badge-success",
                  event.direction == "down" && "badge-info"
                ]}>
                  {event.direction}
                </span>
              </td>
              <td>{event.type}</td>
              <td class="font-mono text-xs max-w-md truncate">{Jason.encode!(event.payload)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
