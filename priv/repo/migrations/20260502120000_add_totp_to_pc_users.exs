defmodule Evenglass.Repo.Migrations.AddTotpToPcUsers do
  use Ecto.Migration

  def change do
    alter table(:pc_users) do
      add :totp_secret, :binary
      add :totp_confirmed_at, :utc_datetime
    end
  end
end
