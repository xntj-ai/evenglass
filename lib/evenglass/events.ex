defmodule Evenglass.Events do
  @moduledoc "Event context — append-only log of G2 ↔ PC events. Broadcasts via PubSub on insert."

  import Ecto.Query
  alias Evenglass.Repo
  alias Evenglass.Events.Event

  @topic "events:all"

  def subscribe do
    Phoenix.PubSub.subscribe(Evenglass.PubSub, @topic)
  end

  def create_event!(attrs) do
    event =
      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert!()
      |> Repo.preload(:session)

    Phoenix.PubSub.broadcast(Evenglass.PubSub, @topic, {:event_created, event})
    event
  end

  @doc """
  Idempotent event insert keyed on `:idempotency_key`.

    * If `attrs.idempotency_key` is nil/missing, falls back to `create_event!/1`.
    * If a row with that key already exists, returns it unchanged (no broadcast,
      no second insert).
    * Otherwise inserts and broadcasts. Race-condition safe via the partial
      unique index on `events(idempotency_key) WHERE NOT NULL` — concurrent
      inserts collapse to one row, with the loser doing a second lookup.
  """
  def create_event_idempotent!(attrs) do
    key = Map.get(attrs, :idempotency_key) || Map.get(attrs, "idempotency_key")

    case key && get_event_by_idempotency_key(key) do
      %Event{} = existing ->
        existing

      _ ->
        try_insert_event(attrs, key)
    end
  end

  defp try_insert_event(attrs, key) do
    case %Event{} |> Event.changeset(attrs) |> Repo.insert() do
      {:ok, event} ->
        event = Repo.preload(event, :session)
        Phoenix.PubSub.broadcast(Evenglass.PubSub, @topic, {:event_created, event})
        event

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        cond do
          # Lost the race: another request already inserted with this key.
          # Look up and return the winner without broadcasting.
          key && Keyword.has_key?(errors, :idempotency_key) ->
            get_event_by_idempotency_key(key) ||
              raise "idempotency_key #{inspect(key)} insert failed but lookup returned nil"

          true ->
            raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
        end
    end
  end

  defp get_event_by_idempotency_key(key) do
    Repo.one(from e in Event, where: e.idempotency_key == ^key, preload: [:session])
  end

  def list_recent_events(limit \\ 50) do
    Repo.all(
      from e in Event,
        order_by: [desc: e.inserted_at],
        limit: ^limit,
        preload: [:session]
    )
  end

  def list_recent_events_for_device(device_id, limit \\ 50) do
    Repo.all(
      from e in Event,
        join: s in assoc(e, :session),
        where: s.device_id == ^device_id,
        order_by: [desc: e.inserted_at],
        limit: ^limit,
        preload: [session: s]
    )
  end
end
