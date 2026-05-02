defmodule EvenglassWeb.Api.AuthController do
  @moduledoc """
  Hub App authentication endpoints.

    * `POST /api/g2/enroll`        — Public. Exchange a single-use enrollment_code
                                     for a device_token (90d).
    * `POST /api/g2/refresh`       — Authenticated. Sliding renewal: trade current
                                     device_token for a fresh one with a rotated
                                     `jti`. Old token effectively revoked.
    * `GET  /api/g2/whoami`        — Authenticated. Returns device metadata.
    * `POST /api/g2/socket-token`  — Authenticated. Issues a 2h channel_token
                                     for WSS connect.

  Authenticated routes go through `EvenglassWeb.Plugs.AuthenticatedAPI` which
  verifies the Bearer device_token and assigns `:device` and `:device_id`.
  """

  use EvenglassWeb, :controller

  alias Evenglass.Auth.Token
  alias Evenglass.Devices

  ## Public ──────────────────────────────────────────────────────────────────

  def enroll(conn, %{"code" => code} = params) when is_binary(code) do
    glasses_serial = params["glasses_serial"]

    case Devices.consume_enrollment_code(code, glasses_serial) do
      {:ok, device} ->
        jti = generate_jti()
        device = Devices.set_jti!(device, jti)
        token = Token.sign_device_token(%{device_id: device.id, jti: jti})

        conn
        |> put_status(:created)
        |> json(%{
          device_id: device.id,
          device_token: token,
          expires_in: Token.device_max_age()
        })

      {:error, :invalid_or_expired} ->
        reject(conn, "invalid_or_expired_code")

      {:error, :glasses_serial_mismatch} ->
        reject(conn, "glasses_serial_mismatch")
    end
  end

  def enroll(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "code (string) is required"})
  end

  ## Authenticated ───────────────────────────────────────────────────────────

  def refresh(%{assigns: %{device: device}} = conn, _params) do
    new_jti = generate_jti()
    device = Devices.set_jti!(device, new_jti)
    new_token = Token.sign_device_token(%{device_id: device.id, jti: new_jti})

    json(conn, %{
      device_token: new_token,
      expires_in: Token.device_max_age()
    })
  end

  def whoami(%{assigns: %{device: device}} = conn, _params) do
    json(conn, %{
      device_id: device.id,
      glasses_serial: device.glasses_serial,
      last_seen_at: device.last_seen_at
    })
  end

  def socket_token(%{assigns: %{device: device}} = conn, _params) do
    ct = Token.sign_channel_token(%{device_id: device.id, role: :device})

    json(conn, %{
      channel_token: ct,
      expires_in: Token.channel_max_age()
    })
  end

  ## Helpers ─────────────────────────────────────────────────────────────────

  defp reject(conn, reason) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: reason})
  end

  defp generate_jti do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
