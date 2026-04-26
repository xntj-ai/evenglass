defmodule Evenglass.Repo do
  use Ecto.Repo,
    otp_app: :evenglass,
    adapter: Ecto.Adapters.Postgres
end
