defmodule Evenglass.Devices do
  @moduledoc """
  Device registration & management.

  Provides enrollment-code issuance, single-use code consumption (which atomically
  creates a Device row), token-id (jti) bookkeeping for revocation, and last-seen
  tracking. Authentication and Phoenix.Token signing live in the auth controller —
  this context only owns persistence.
  """

  import Ecto.Query
  alias Evenglass.Repo
  alias Evenglass.Devices.{Device, EnrollmentCode}

  @code_length 6
  @code_ttl_seconds 10 * 60

  ## Devices ─────────────────────────────────────────────────────────────────

  def get_device(id), do: Repo.get(Device, id)
  def get_device!(id), do: Repo.get!(Device, id)

  @doc "Returns the device only when it is not revoked."
  def fetch_active_device(id) do
    case get_device(id) do
      %Device{revoked_at: nil} = d -> {:ok, d}
      %Device{} -> {:error, :revoked}
      nil -> {:error, :not_found}
    end
  end

  def create_device!(attrs) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert!()
  end

  def touch_device!(%Device{} = d) do
    d
    |> Device.changeset(%{last_seen_at: now()})
    |> Repo.update!()
  end

  def set_jti!(%Device{} = d, jti) when is_binary(jti) do
    d
    |> Device.changeset(%{jti: jti})
    |> Repo.update!()
  end

  def revoke!(%Device{} = d) do
    d
    |> Device.changeset(%{revoked_at: now(), jti: nil})
    |> Repo.update!()
  end

  ## Enrollment codes ────────────────────────────────────────────────────────

  @doc """
  Issues a single-use 6-digit enrollment code valid for 10 minutes.
  `glasses_serial` is optional — if provided, the code is pre-bound and consumption
  must match.
  """
  def generate_enrollment_code!(attrs \\ %{}) do
    code = generate_numeric_code(@code_length)

    expires_at =
      DateTime.add(DateTime.utc_now(), @code_ttl_seconds, :second) |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.put(:code, code)
      |> Map.put(:expires_at, expires_at)

    %EnrollmentCode{}
    |> EnrollmentCode.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Atomically validates and consumes an enrollment code, creating the corresponding
  Device row in the same transaction.

  Returns `{:ok, %Device{}}` on success, or `{:error, reason}` where reason is
  `:invalid_or_expired` | `:glasses_serial_mismatch`.
  """
  def consume_enrollment_code(code, glasses_serial \\ nil)
      when is_binary(code) do
    Repo.transaction(fn ->
      now = now()

      ec =
        from(e in EnrollmentCode,
          where: e.code == ^code and e.expires_at > ^now and is_nil(e.used_at),
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      cond do
        is_nil(ec) ->
          Repo.rollback(:invalid_or_expired)

        ec.glasses_serial && glasses_serial && ec.glasses_serial != glasses_serial ->
          Repo.rollback(:glasses_serial_mismatch)

        true ->
          device =
            create_device!(%{
              glasses_serial: ec.glasses_serial || glasses_serial,
              last_seen_at: now
            })

          ec
          |> EnrollmentCode.changeset(%{used_at: now, used_by_device_id: device.id})
          |> Repo.update!()

          device
      end
    end)
  end

  @doc "Lists currently usable enrollment codes (not expired, not used)."
  def list_active_codes do
    now = now()

    from(e in EnrollmentCode,
      where: e.expires_at > ^now and is_nil(e.used_at),
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  ## Helpers ─────────────────────────────────────────────────────────────────

  # Cryptographically uniform numeric code — :rand state is recoverable from
  # a few outputs, which would let an observer predict future enrollment
  # codes after the admin issues several in succession.
  defp generate_numeric_code(len) do
    max = trunc(:math.pow(10, len))

    :crypto.strong_rand_bytes(8)
    |> :binary.decode_unsigned()
    |> rem(max)
    |> Integer.to_string()
    |> String.pad_leading(len, "0")
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
