defmodule EvenglassWeb.Schemas.CommandRequest do
  @moduledoc "POST /api/g2/commands request body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CommandRequest",
    type: :object,
    required: [:device_id, :type],
    properties: %{
      device_id: %Schema{
        type: :string,
        format: :uuid,
        description: "Target device. Must already be enrolled."
      },
      type: %Schema{
        type: :string,
        description: "Command kind, e.g. `display_text`, `clear`, `audio_play`."
      },
      payload: %Schema{
        type: :object,
        additionalProperties: true,
        description: "Command-specific parameters. Forwarded verbatim to the device."
      }
    },
    example: %{
      "device_id" => "0193f8e0-1234-7000-89ab-cdef01234567",
      "type" => "display_text",
      "payload" => %{"line1" => "Hello G2"}
    }
  })
end
