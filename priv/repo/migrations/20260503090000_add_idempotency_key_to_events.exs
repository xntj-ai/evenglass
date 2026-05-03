defmodule Evenglass.Repo.Migrations.AddIdempotencyKeyToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :idempotency_key, :text
    end

    # Partial unique index — only keys that are present must be unique.
    # Hub Apps that don't send Idempotency-Key continue to insert freely.
    create unique_index(:events, [:idempotency_key], where: "idempotency_key IS NOT NULL")
  end
end
