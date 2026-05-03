defmodule Evenglass.RateLimit do
  @moduledoc """
  ETS-backed token-bucket rate limiter (Hammer 7.x).

  Buckets used across the app:

    * `enroll:ip:<ip>`              — 5 / 60s   (POST /api/g2/enroll)
    * `events:device:<device_id>`   — 600 / 60s (POST /api/g2/events)
    * `commands:user:<user_id>`     — 120 / 60s (POST /api/g2/commands)
    * `chan-join:device:<id>`       — 10 / 60s  (Channel `g2:device:*` join)
    * `admin-login:<ip>:<email>`    — 5 / 900s  (POST /pc_users/log-in)

  Started in `Evenglass.Application`'s supervision tree. Counter table is
  process-local to the BEAM node; restart drops all counters (fine for
  single-node prod and ephemeral test runs).
  """

  use Hammer, backend: :ets
end
