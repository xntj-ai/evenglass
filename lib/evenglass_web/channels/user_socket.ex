defmodule EvenglassWeb.UserSocket do
  @moduledoc """
  WebSocket entrypoint for Hub Apps and PC admins.

  A successful `connect/3` requires a `channel_token` in the connect params,
  verified via `Evenglass.Auth.Token.verify_channel_token/1` (max age 2h),
  yielding `%{device_id, role}`. Both fields are stored in `socket.assigns`
  for downstream channel-level authorization.

  Token issuance:
    * `:device` role tokens come from `POST /api/g2/socket-token` (Hub App).
    * `:pc_admin` role tokens will come from PC admin login (task 1.5).
  """

  use Phoenix.Socket

  alias Evenglass.Auth.Token

  channel "g2:device:*", EvenglassWeb.G2Channel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Token.verify_channel_token(token) do
      {:ok, %{device_id: id, role: role}} ->
        {:ok,
         socket
         |> assign(:device_id, id)
         |> assign(:role, role)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Identifying the socket allows Phoenix to disconnect all sockets for a given
  # device when needed (e.g. after revocation). The id format is intentionally
  # `user_socket:<device_id>` so callers can `EvenglassWeb.Endpoint.broadcast(
  # "user_socket:#{device_id}", "disconnect", %{})` to terminate every active
  # connection for that device.
  @impl true
  def id(%{assigns: %{device_id: id}}), do: "user_socket:#{id}"
end
