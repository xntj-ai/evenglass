defmodule EvenglassWeb.Plugs.AuthenticatedAPI do
  @moduledoc """
  Bearer device_token verification plug for authenticated `/api/g2/*` endpoints.

  Reads the `Authorization: Bearer <token>` header, verifies it via
  `Evenglass.Auth.Token.verify_device_token/1`, ensures the device is not
  revoked and the token's `jti` matches the device's currently-stored `jti`
  (revocation check), then assigns:

    * `:device`    — the active `%Evenglass.Devices.Device{}` row
    * `:device_id` — `device.id` (binary_id string)

  On any failure, halts with HTTP 401 + `%{error: <reason>}` JSON body.
  Reasons: `missing_bearer | invalid_token | expired_token | device_revoked
            | device_not_found | stale_jti | unauthorized`.
  """

  import Plug.Conn

  alias Evenglass.Auth.Token
  alias Evenglass.Devices

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- read_bearer(conn),
         {:ok, %{device_id: id, jti: jti}} <- Token.verify_device_token(token),
         {:ok, device} <- Devices.fetch_active_device(id),
         true <- device.jti == jti do
      conn
      |> assign(:device, device)
      |> assign(:device_id, device.id)
    else
      {:error, :missing_bearer} -> reject(conn, "missing_bearer")
      {:error, :invalid} -> reject(conn, "invalid_token")
      {:error, :expired} -> reject(conn, "expired_token")
      {:error, :revoked} -> reject(conn, "device_revoked")
      {:error, :not_found} -> reject(conn, "device_not_found")
      false -> reject(conn, "stale_jti")
      _ -> reject(conn, "unauthorized")
    end
  end

  defp read_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp reject(conn, reason) do
    conn
    |> put_resp_content_type("application/json")
    |> put_status(:unauthorized)
    |> resp(401, Jason.encode!(%{error: reason}))
    |> halt()
  end
end
