defmodule EvenglassWeb.G2Channel do
  @moduledoc """
  Per-device topic for bidirectional realtime traffic.

  Topic pattern: `"g2:device:<device_id>"`.

  ## Authorization

    * Role `:device` — may join only its own topic; `device_id` in the topic
      must equal `socket.assigns.device_id` (set during `UserSocket.connect/3`).
      Joins are rate-limited 10 / 60s / device.
    * Role `:pc_admin` — may join any device topic for monitoring/control.
      Not rate-limited (trusted operator session).
    * All other cases reject with `unauthorized`.

  ## Message contracts (forward-looking)

  Currently exposes a `ping` request/reply for client liveness checks. Task 4.1
  will add `event` (server → client) for downstream commands and a metrics
  channel; task 1.5 will add command relay from PC admins.
  """

  use Phoenix.Channel

  alias Evenglass.RateLimit

  @join_scale_ms 60_000
  @join_limit 10

  @impl true
  def join("g2:device:" <> id, _payload, %{assigns: %{role: :device, device_id: my_id}} = socket)
      when id == my_id do
    case RateLimit.hit("chan-join:device:#{my_id}", @join_scale_ms, @join_limit) do
      {:allow, _count} ->
        {:ok, %{role: "device", device_id: my_id}, socket}

      {:deny, retry_after_ms} ->
        {:error, %{reason: "rate_limited", retry_after_ms: retry_after_ms}}
    end
  end

  def join("g2:device:" <> id, _payload, %{assigns: %{role: :pc_admin}} = socket) do
    {:ok, %{role: "pc_admin", device_id: id}, socket}
  end

  def join(_topic, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: true, ts: System.system_time(:millisecond)}}, socket}
  end
end
