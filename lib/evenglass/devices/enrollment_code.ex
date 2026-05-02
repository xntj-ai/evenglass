defmodule Evenglass.Devices.EnrollmentCode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "enrollment_codes" do
    field :code, :string
    field :glasses_serial, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :used_by_device, Evenglass.Devices.Device, foreign_key: :used_by_device_id

    timestamps(type: :utc_datetime)
  end

  def changeset(ec, attrs) do
    ec
    |> cast(attrs, [
      :code,
      :glasses_serial,
      :expires_at,
      :used_at,
      :used_by_device_id
    ])
    |> validate_required([:code, :expires_at])
    |> unique_constraint(:code)
  end
end
