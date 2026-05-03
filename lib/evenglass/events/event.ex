defmodule Evenglass.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @directions ~w(up down)

  schema "events" do
    field :direction, :string
    field :type, :string
    field :payload, :map, default: %{}
    field :idempotency_key, :string
    # inserted_at filled by DB default; read_after_writes pulls it back into the struct
    field :inserted_at, :utc_datetime, read_after_writes: true

    belongs_to :session, Evenglass.Sessions.Session
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:session_id, :direction, :type, :payload, :idempotency_key])
    |> validate_required([:session_id, :direction, :type])
    |> validate_inclusion(:direction, @directions)
    |> validate_length(:idempotency_key, max: 128)
    |> unique_constraint(:idempotency_key)
    |> assoc_constraint(:session)
  end
end
