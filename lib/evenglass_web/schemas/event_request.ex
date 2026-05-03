defmodule EvenglassWeb.Schemas.EventRequest do
  @moduledoc "POST /api/g2/events request body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "EventRequest",
    type: :object,
    required: [:type],
    properties: %{
      type: %Schema{
        type: :string,
        description: "Event kind, e.g. `tap`, `gesture`, `audio_chunk_meta`."
      },
      payload: %Schema{
        type: :object,
        description: "Free-form JSON payload. Server stores verbatim and re-broadcasts to admin.",
        additionalProperties: true
      }
    },
    example: %{"type" => "tap", "payload" => %{"button" => "right", "ts" => 1_777_793_700}}
  })
end
