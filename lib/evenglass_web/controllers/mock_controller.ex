defmodule EvenglassWeb.MockController do
  use EvenglassWeb, :controller

  alias Evenglass.{Sessions, Events}

  @devices ~w(MOCK_DEVICE_A MOCK_DEVICE_B)
  @up_types ~w(touch battery text)
  @down_types ~w(display_text display_image set_brightness)

  @doc "POST /api/mock — fabricates a random event for development."
  def create(conn, _params) do
    direction = Enum.random(~w(up down))
    type = Enum.random(if direction == "up", do: @up_types, else: @down_types)
    device_id = Enum.random(@devices)

    session = Sessions.touch_session_by_device_id!(device_id)
    payload = build_payload(type)

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

  defp build_payload("touch"), do: %{position: Enum.random(["left", "right"]), duration_ms: :rand.uniform(2000)}
  defp build_payload("battery"), do: %{level: :rand.uniform(100), charging: Enum.random([true, false])}
  defp build_payload("text"), do: %{text: "Mock " <> Integer.to_string(:rand.uniform(10_000))}
  defp build_payload("display_text"), do: %{text: "Hello G2 ##{:rand.uniform(10_000)}", duration_ms: 3000}
  defp build_payload("display_image"), do: %{url: "https://example.com/img-#{:rand.uniform(100)}.png"}
  defp build_payload("set_brightness"), do: %{level: :rand.uniform(100)}
end
