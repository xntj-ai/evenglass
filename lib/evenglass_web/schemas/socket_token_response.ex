defmodule EvenglassWeb.Schemas.SocketTokenResponse do
  @moduledoc "POST /api/g2/socket-token 200 body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "SocketTokenResponse",
    type: :object,
    required: [:channel_token, :expires_in],
    properties: %{
      channel_token: %Schema{
        type: :string,
        description:
          "Short-lived (2h) credential for `wss://.../socket`. Pass as the `token` " <>
            "param when establishing the channel connection."
      },
      expires_in: %Schema{
        type: :integer,
        description: "Token lifetime in seconds (2h = 7,200)."
      }
    }
  })
end
