defmodule EvenglassWeb.G2Controller do
  @moduledoc """
  G2 ↔ PC event/command relay.

  - POST /api/g2/events    → mobile-side reports an upstream event from G2
  - POST /api/g2/commands  → PC-side issues a downstream command to G2
  """

  use EvenglassWeb, :controller

  alias Evenglass.{Sessions, Events}

  def create_event(conn, params), do: relay(conn, params, "up")
  def create_command(conn, params), do: relay(conn, params, "down")

  defp relay(conn, %{"device_id" => device_id, "type" => type} = params, direction)
       when is_binary(device_id) and is_binary(type) do
    payload = Map.get(params, "payload", %{})

    session = Sessions.touch_session_by_device_id!(device_id)

    event =
      Events.create_event!(%{
        session_id: session.id,
        direction: direction,
        type: type,
        payload: payload
      })

    conn
    |> put_status(:created)
    |> json(%{
      id: event.id,
      direction: event.direction,
      type: event.type,
      payload: event.payload,
      device_id: device_id,
      inserted_at: event.inserted_at
    })
  end

  defp relay(conn, _params, _direction) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "device_id (string) and type (string) are required; payload (object) is optional"})
  end
end
