defmodule EvenglassWeb.Schemas.ErrorResponse do
  @moduledoc "Generic JSON error envelope used by all `/api/g2/*` endpoints on 4xx."
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ErrorResponse",
    type: :object,
    required: [:error],
    properties: %{
      error: %Schema{
        type: :string,
        description:
          "Stable machine-readable error code, e.g. `invalid_or_expired_code`, " <>
            "`missing_bearer`, `device_revoked`, `rate_limited`, `unauthorized`."
      },
      retry_after_ms: %Schema{
        type: :integer,
        nullable: true,
        description:
          "Set on `rate_limited` responses; matches the `Retry-After` header (seconds rounded up)."
      }
    },
    example: %{"error" => "invalid_or_expired_code"}
  })
end
