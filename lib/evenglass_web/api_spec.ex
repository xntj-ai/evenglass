defmodule EvenglassWeb.ApiSpec do
  @moduledoc """
  Authoritative OpenAPI 3.1 spec for the public `/api/g2/*` surface.

  Hub Apps and admin tooling consume this spec via `GET /api/openapi.json`.
  Type-generation for the hub-app TypeScript client (task 2) reads the same
  document via `openapi-typescript`. Edit operation annotations on the
  controllers, not this module — `Paths.from_router/1` walks the router and
  collects each `operation/2` declaration.
  """

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  alias EvenglassWeb.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "evenglass G2 ↔ PC relay API",
        version: "0.1.0",
        description: """
        Realtime relay between Even Realities G2 glasses and PC business
        logic. Hub Apps authenticate with a `device_token` (Bearer);
        admin browser sessions authenticate via cookie + 2FA.
        """
      },
      servers: [
        %Server{url: "https://g2.xntj.tv", description: "Production"}
      ],
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "BearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description:
              "device_token issued by `POST /api/g2/enroll`. Carries " <>
                "`{device_id, jti}` and is valid for 90 days; `jti` rotates " <>
                "on refresh and clearing it revokes the device."
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
