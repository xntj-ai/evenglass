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
