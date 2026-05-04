defmodule EvenglassWeb.Api.PcAuthController do
  @moduledoc """
  PC admin authentication endpoints (separate from Hub App `/api/g2/*` flow).

    * `POST /api/pc/socket-token` — Authenticated. Issues a 2h `:pc_admin`
      channel_token for WSS connect. Bound to the calling PC admin's
      `pc_user_id`, NOT to a particular device — PC admins may join any
      `g2:device:<id>` topic for monitoring/control (G2Channel enforces this).

  Authentication is the existing browser session cookie + 2FA gate
  (`:authenticated_admin_api` pipeline → `require_pc_admin_api`). PC clients
  (e.g. voice-input) authenticate by logging in via the regular login flow,
  capturing the `_evenglass_web_pc_user_token` cookie, and replaying it on
  this endpoint.
  """

  use EvenglassWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Evenglass.Auth.Token

  alias EvenglassWeb.Schemas.{ErrorResponse, SocketTokenResponse}

  tags(["pc-auth"])

  operation(:socket_token,
    summary: "Issues a 2-hour pc_admin channel token for WSS connect",
    description: """
    PC admin clients call this just before opening
    `wss://.../socket?token=<channel_token>`. The token carries the
    authenticated admin's `pc_user_id` and `role: :pc_admin`. Channel join
    authorization for `g2:device:<id>` topics is enforced by `G2Channel`,
    which currently allows any `:pc_admin` socket to join any device topic.
    """,
    responses: %{
      200 => {"Channel token issued", "application/json", SocketTokenResponse},
      401 => {"Admin session missing or 2FA not completed", "application/json", ErrorResponse}
    }
  )

  def socket_token(%{assigns: %{current_scope: %{pc_user: pc_user}}} = conn, _params) do
    ct = Token.sign_channel_token(%{pc_user_id: pc_user.id, role: :pc_admin})

    json(conn, %{
      channel_token: ct,
      expires_in: Token.channel_max_age()
    })
  end
end
