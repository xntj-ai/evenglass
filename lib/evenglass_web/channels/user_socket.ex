defmodule EvenglassWeb.UserSocket do
  @moduledoc """
  WebSocket entrypoint for Hub Apps and PC admins.

  A successful `connect/3` requires a `channel_token` in the connect params,
  verified via `Evenglass.Auth.Token.verify_channel_token/1` (max age 2h).
  Two role variants:

    * `:device` — payload `%{device_id, role: :device}`. Stored as
      `socket.assigns.device_id` + `:role`. Issued by `/api/g2/socket-token`.
    * `:pc_admin` — payload `%{pc_user_id, role: :pc_admin}`. Stored as
      `socket.assigns.pc_user_id` + `:role`. Issued by `/api/pc/socket-token`.

  Channel-level authorization (e.g. who can join `g2:device:<id>`) is enforced
  by individual channel modules using these assigns.
  """

  use Phoenix.Socket

  alias Evenglass.Auth.Token

  channel "g2:device:*", EvenglassWeb.G2Channel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Token.verify_channel_token(token) do
      {:ok, %{device_id: id, role: :device}} ->
        {:ok,
         socket
         |> assign(:device_id, id)
         |> assign(:role, :device)}

      {:ok, %{pc_user_id: uid, role: :pc_admin}} ->
        {:ok,
         socket
         |> assign(:pc_user_id, uid)
         |> assign(:role, :pc_admin)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Identifying the socket allows Phoenix to disconnect all sockets for a given
  # principal when needed (e.g. after revocation). The id format is intentionally
  # `user_socket:<device_id>` for devices and `pc_socket:<pc_user_id>` for PC
  # admins, so callers can `EvenglassWeb.Endpoint.broadcast(<id>, "disconnect", %{})`
  # to terminate every active connection for that principal.
  @impl true
  def id(%{assigns: %{role: :device, device_id: id}}), do: "user_socket:#{id}"
  def id(%{assigns: %{role: :pc_admin, pc_user_id: uid}}), do: "pc_socket:#{uid}"
end
