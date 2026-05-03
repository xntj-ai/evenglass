defmodule EvenglassWeb.Schemas.RefreshResponse do
  @moduledoc "POST /api/g2/refresh 200 body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "RefreshResponse",
    type: :object,
    required: [:device_token, :expires_in],
    properties: %{
      device_token: %Schema{type: :string},
      expires_in: %Schema{type: :integer}
    }
  })
end
