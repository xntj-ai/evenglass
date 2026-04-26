defmodule Evenglass.Sessions do
  @moduledoc "Session context — one session per G2 device (MAC address)."

  import Ecto.Query
  alias Evenglass.Repo
  alias Evenglass.Sessions.Session

  @doc """
  Atomically upserts a session by device_id, refreshing last_seen_at on hit.
  """
  def touch_session_by_device_id!(device_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Session{device_id: device_id, last_seen_at: now}
    |> Repo.insert!(
      on_conflict: [set: [last_seen_at: now, updated_at: now]],
      conflict_target: :device_id,
      returning: true
    )
  end

  def list_sessions do
    Repo.all(from s in Session, order_by: [desc: s.last_seen_at])
  end
end
