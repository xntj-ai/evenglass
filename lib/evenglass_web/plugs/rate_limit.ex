defmodule EvenglassWeb.Plugs.RateLimit do
  @moduledoc """
  Generic IP-keyed rate-limit plug.

  Usage in router:

      pipeline :rl_enroll do
        plug EvenglassWeb.Plugs.RateLimit,
          bucket: "enroll",
          scale_ms: 60_000,
          limit: 5
      end

  Endpoints that need to key on app-level identifiers (`device_id`,
  `user_id`, `email`) call `Evenglass.RateLimit.hit/3` directly inside
  the controller / channel and reuse `client_ip/1` from this module.

  Client IP precedence:

    1. First entry of `X-Forwarded-For` header (Caddy → 127.0.0.1 only,
       so this is trustworthy in our deploy).
    2. `conn.remote_ip` fallback.
  """

  import Plug.Conn

  alias Evenglass.RateLimit

  def init(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      scale_ms: Keyword.fetch!(opts, :scale_ms),
      limit: Keyword.fetch!(opts, :limit)
    }
  end

  def call(conn, %{bucket: bucket, scale_ms: scale_ms, limit: limit}) do
    key = "#{bucket}:ip:#{client_ip(conn)}"

    case RateLimit.hit(key, scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after_ms} ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("retry-after", to_string(div(retry_after_ms, 1000) + 1))
        |> put_status(:too_many_requests)
        |> resp(
          429,
          Jason.encode!(%{error: "rate_limited", retry_after_ms: retry_after_ms})
        )
        |> halt()
    end
  end

  @doc """
  Extracts the originating client IP as a string. Trusts the first
  `X-Forwarded-For` segment when present (Phoenix sits behind Caddy on
  127.0.0.1 in prod), otherwise falls back to `conn.remote_ip`.
  """
  def client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [xff | _] when is_binary(xff) ->
        xff
        |> String.split(",")
        |> List.first()
        |> String.trim()

      _ ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end
end
