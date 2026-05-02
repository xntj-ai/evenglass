defmodule Evenglass.Repo.Migrations.CreateDevicesAndEnrollmentCodes do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :glasses_serial, :string
      add :jti, :string
      add :revoked_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:devices, [:glasses_serial], where: "glasses_serial IS NOT NULL")
    create index(:devices, [:jti])
    create index(:devices, [:revoked_at])

    create table(:enrollment_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :glasses_serial, :string
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      add :used_by_device_id,
          references(:devices, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:enrollment_codes, [:code])
    create index(:enrollment_codes, [:expires_at])
  end
end
