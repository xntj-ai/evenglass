defmodule EvenglassWeb.Schemas.WhoamiResponse do
  @moduledoc "GET /api/g2/whoami 200 body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WhoamiResponse",
    type: :object,
    required: [:device_id],
    properties: %{
      device_id: %Schema{type: :string, format: :uuid},
      glasses_serial: %Schema{type: :string, nullable: true},
      last_seen_at: %Schema{type: :string, format: :"date-time", nullable: true}
    }
  })
end
