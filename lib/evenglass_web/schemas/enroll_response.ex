defmodule EvenglassWeb.Schemas.EnrollResponse do
  @moduledoc "POST /api/g2/enroll 201 body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "EnrollResponse",
    type: :object,
    required: [:device_id, :device_token, :expires_in],
    properties: %{
      device_id: %Schema{type: :string, format: :uuid},
      device_token: %Schema{
        type: :string,
        description: "Phoenix.Token-signed Bearer credential. Store securely on the Hub App side."
      },
      expires_in: %Schema{
        type: :integer,
        description: "Token lifetime in seconds (90 days = 7,776,000)."
      }
    }
  })
end
