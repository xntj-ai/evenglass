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
     |> assign(:max_events, @max_events)
     |> stream(:events, Events.list_recent_events(@max_events), limit: @max_events)}
  end

  @impl true
  def handle_info({:event_created, event}, socket) do
    {:noreply, stream_insert(socket, :events, event, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-2xl font-semibold">Event Stream</h1>
        <div class="text-sm opacity-70">
          Last {@max_events} events · auto-refreshing
        </div>
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
