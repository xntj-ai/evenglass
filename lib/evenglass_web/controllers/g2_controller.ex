defmodule EvenglassWeb.G2Controller do
  @moduledoc """
  G2 ↔ PC event/command relay.

  - `POST /api/g2/events`    — Hub App (authenticated via device_token) reports
                               an upstream event. `device_id` is sourced from
                               `conn.assigns.device_id` (set by
                               `EvenglassWeb.Plugs.AuthenticatedAPI`), NOT
                               from the request body — preventing spoofing.
                               Rate-limited 600 / 60s / device.
  - `POST /api/g2/commands`  — PC issues a downstream command. Gated on
                               2FA-completed admin session (`:require_pc_admin_api`).
                               Rate-limited 120 / 60s / pc_user.
  """

  use EvenglassWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Evenglass.{Sessions, Events, Devices, RateLimit}

  alias EvenglassWeb.Schemas.{
    CommandRequest,
    ErrorResponse,
    EventRequest,
    EventResponse
  }

  tags(["g2-relay"])

  @events_scale_ms 60_000
  @events_limit 600
  @commands_scale_ms 60_000
  @commands_limit 120

  operation(:create_event,
    summary: "Hub App reports an upstream event from G2",
    description: """
    Append an upstream event to the device's session. `device_id` is taken
    from the bearer token, not the request body, so a compromised Hub App
    cannot impersonate other devices.

    Set `Idempotency-Key: <ulid>` to deduplicate retries: a second POST with
    the same key returns the original event row (HTTP 201, identical `id`)
    without inserting a duplicate.
    """,
    security: [%{"BearerAuth" => []}],
    parameters: [
      idempotency_key: [
        in: :header,
        name: "Idempotency-Key",
        description: "Optional ULID-shaped client-generated key for at-most-once semantics.",
        schema: %OpenApiSpex.Schema{
          type: :string,
          pattern: ~r/^[A-Za-z0-9_\-]{1,128}$/
        },
        required: false
      ]
    ],
    request_body: {"Event payload", "application/json", EventRequest},
    responses: %{
      201 => {"Event accepted", "application/json", EventResponse},
      400 => {"Malformed body", "application/json", ErrorResponse},
      401 => {"Bearer missing/invalid", "application/json", ErrorResponse},
      429 => {"Per-device rate limit (600/min) hit", "application/json", ErrorResponse}
    }
  )

  def create_event(%{assigns: %{device: device, device_id: device_id}} = conn, params) do
    with_rate_limit(conn, "events:device:#{device_id}", @events_scale_ms, @events_limit, fn ->
      case params do
        %{"type" => type} when is_binary(type) ->
          payload = Map.get(params, "payload", %{})
          idempotency_key = read_idempotency_key(conn)

          Devices.touch_device!(device)
          session = Sessions.touch_session_by_device_id!(device_id)

          event =
            Events.create_event_idempotent!(%{
              session_id: session.id,
              direction: "up",
              type: type,
              payload: payload,
              idempotency_key: idempotency_key
            })

          conn
          |> put_status(:created)
          |> json(payload_response(event, device_id))

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "type (string) is required; payload (object) is optional"})
      end
    end)
  end

  # Returns the validated Idempotency-Key header (1–128 ASCII chars,
  # ULID-friendly) or nil. Anything malformed is treated as no key — this
  # avoids leaking validation errors back to clients while still letting
  # well-behaved clients deduplicate retries.
  defp read_idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [val | _] when is_binary(val) ->
        trimmed = String.trim(val)

        if trimmed != "" and byte_size(trimmed) <= 128 and
             String.match?(trimmed, ~r/^[A-Za-z0-9_\-]+$/) do
          trimmed
        else
          nil
        end

      _ ->
        nil
    end
  end

  operation(:create_command,
    summary: "PC admin issues a downstream command to a device",
    description: """
    Append a downstream command for the named device. Authenticated by the
    PC admin browser session cookie + 2FA gate (NOT by `BearerAuth`).
    Rate-limited 120/min/admin user.
    """,
    request_body: {"Command payload", "application/json", CommandRequest},
    responses: %{
      201 => {"Command accepted", "application/json", EventResponse},
      400 => {"Malformed body", "application/json", ErrorResponse},
      401 => {"Admin session missing or 2FA not completed", "application/json", ErrorResponse},
      429 => {"Per-user rate limit (120/min) hit", "application/json", ErrorResponse}
    }
  )

  def create_command(conn, %{"device_id" => device_id, "type" => type} = params)
      when is_binary(device_id) and is_binary(type) do
    user_id = conn.assigns.current_scope.pc_user.id

    with_rate_limit(conn, "commands:user:#{user_id}", @commands_scale_ms, @commands_limit, fn ->
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
    end)
  end

  def create_command(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "device_id (string) and type (string) are required; payload (object) is optional"
    })
  end

  defp with_rate_limit(conn, key, scale_ms, limit, fun) do
    case RateLimit.hit(key, scale_ms, limit) do
      {:allow, _count} ->
        fun.()

      {:deny, retry_after_ms} ->
        conn
        |> put_resp_header("retry-after", to_string(div(retry_after_ms, 1000) + 1))
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited", retry_after_ms: retry_after_ms})
    end
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
