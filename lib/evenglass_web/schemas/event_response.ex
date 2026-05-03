defmodule EvenglassWeb.Schemas.EventResponse do
  @moduledoc "POST /api/g2/events 201 body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "EventResponse",
    type: :object,
    required: [:id, :direction, :type, :device_id, :inserted_at],
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      direction: %Schema{type: :string, enum: ["up", "down"]},
      type: %Schema{type: :string},
      payload: %Schema{type: :object, additionalProperties: true},
      device_id: %Schema{type: :string, format: :uuid},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  })
end
