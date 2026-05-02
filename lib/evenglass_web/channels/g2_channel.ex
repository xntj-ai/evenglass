defmodule EvenglassWeb.G2Channel do
  @moduledoc """
  Per-device topic for bidirectional realtime traffic.

  Topic pattern: `"g2:device:<device_id>"`.

  ## Authorization

    * Role `:device` — may join only its own topic; `device_id` in the topic
      must equal `socket.assigns.device_id` (set during `UserSocket.connect/3`).
    * Role `:pc_admin` — may join any device topic for monitoring/control.
    * All other cases reject with `unauthorized`.

  ## Message contracts (forward-looking)

  Currently exposes a `ping` request/reply for client liveness checks. Task 4.1
  will add `event` (server → client) for downstream commands and a metrics
  channel; task 1.5 will add command relay from PC admins.
  """

  use Phoenix.Channel

  @impl true
  def join("g2:device:" <> id, _payload, %{assigns: %{role: :device, device_id: my_id}} = socket)
      when id == my_id do
    {:ok, %{role: "device", device_id: my_id}, socket}
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
