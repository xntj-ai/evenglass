defmodule Evenglass.Repo.Migrations.CreateSessionsAndEvents do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, :string, null: false
      add :last_seen_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:sessions, [:device_id])

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime, null: false, default: fragment("(now() at time zone 'utc')")
    end

    create index(:events, [:session_id, :inserted_at])
    create index(:events, [:inserted_at])
  end
end
