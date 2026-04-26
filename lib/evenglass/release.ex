defmodule Evenglass.Release do
  @moduledoc """
  Tasks invoked from `bin/evenglass eval` inside a mix release container,
  since Mix tasks are not available at runtime.

  Usage:
      docker compose exec app /app/bin/evenglass eval "Evenglass.Release.migrate()"
  """

  @app :evenglass

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
