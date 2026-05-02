defmodule EvenglassWeb.G2Controller do
  @moduledoc """
  G2 ↔ PC event/command relay.

  - `POST /api/g2/events`    — Hub App (authenticated via device_token) reports
                               an upstream event. `device_id` is sourced from
                               `conn.assigns.device_id` (set by
                               `EvenglassWeb.Plugs.AuthenticatedAPI`), NOT
                               from the request body — preventing spoofing.
  - `POST /api/g2/commands`  — PC issues a downstream command. Currently
                               unauthenticated; `device_id` comes from the
                               request body. Task 1.5 introduces PC user auth
                               and the `:authenticated_admin_api` pipeline.
  """

  use EvenglassWeb, :controller

  alias Evenglass.{Sessions, Events, Devices}

  def create_event(%{assigns: %{device: device, device_id: device_id}} = conn, params) do
    case params do
      %{"type" => type} when is_binary(type) ->
        payload = Map.get(params, "payload", %{})

        Devices.touch_device!(device)
        session = Sessions.touch_session_by_device_id!(device_id)

        event =
          Events.create_event!(%{
            session_id: session.id,
            direction: "up",
            type: type,
            payload: payload
          })

        conn
        |> put_status(:created)
        |> json(payload_response(event, device_id))

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "type (string) is required; payload (object) is optional"})
    end
  end

  def create_command(conn, %{"device_id" => device_id, "type" => type} = params)
      when is_binary(device_id) and is_binary(type) do
    payload = Map.get(params, "payload", %{})

    session = Sessions.touch_session_by_device_id!(device_id)

    event =
      Events.create_event!(%{
        session_id: session.id,
        direction: "down",
        type: type,
        payload: payload
      })

    conn
    |> put_status(:created)
    |> json(payload_response(event, device_id))
  end

  def create_command(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "device_id (string) and type (string) are required; payload (object) is optional"
    })
  end

  defp payload_response(event, device_id) do
    %{
      id: event.id,
      direction: event.direction,
      type: event.type,
      payload: event.payload,
      device_id: device_id,
      inserted_at: event.inserted_at
    }
  end
end
