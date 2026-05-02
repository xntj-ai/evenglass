defmodule Evenglass.Repo.Migrations.CreatePcUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:pc_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pc_users, [:email])

    create table(:pc_users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :pc_user_id, references(:pc_users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:pc_users_tokens, [:pc_user_id])
    create unique_index(:pc_users_tokens, [:context, :token])
  end
end
