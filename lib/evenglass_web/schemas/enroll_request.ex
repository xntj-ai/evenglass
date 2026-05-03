defmodule EvenglassWeb.Schemas.EnrollRequest do
  @moduledoc "POST /api/g2/enroll request body."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "EnrollRequest",
    type: :object,
    required: [:code],
    properties: %{
      code: %Schema{
        type: :string,
        pattern: ~r/^\d{6}$/,
        description: "Single-use 6-digit enrollment code (10 min TTL)."
      },
      glasses_serial: %Schema{
        type: :string,
        nullable: true,
        description: "Optional G2 serial. If the code was pre-bound to a serial it must match."
      }
    },
    example: %{"code" => "123456", "glasses_serial" => "G2-ABCD-1234"}
  })
end
