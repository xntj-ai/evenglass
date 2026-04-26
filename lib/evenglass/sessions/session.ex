defmodule Evenglass.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :device_id, :string
    field :last_seen_at, :utc_datetime

    has_many :events, Evenglass.Events.Event

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:device_id, :last_seen_at])
    |> validate_required([:device_id])
    |> unique_constraint(:device_id)
  end
end
