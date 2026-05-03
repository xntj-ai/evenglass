defmodule EvenglassWeb.G2Channel do
  @moduledoc """
  Per-device topic for bidirectional realtime traffic.

  Topic pattern: `"g2:device:<device_id>"`.

  ## Authorization

    * Role `:device` — may join only its own topic; `device_id` in the topic
      must equal `socket.assigns.device_id` (set during `UserSocket.connect/3`).
      Joins are rate-limited 10 / 60s / device.
    * Role `:pc_admin` — may join any device topic for monitoring/control.
      Not rate-limited (trusted operator session).
    * All other cases reject with `unauthorized`.

  ## Message contracts

    * `ping` (in) — request/reply liveness check.
    * `audio_chunk` (in, device-only) — Hub App pushes a batched PCM chunk:
      `%{seq, pcm_b64, frames, bytes, sample_rate, format}`. Server does **not**
      persist PCM. It accumulates frame/byte counts per socket and writes one
      `audio_meta` event to `events` table per ~1s window for admin observability,
      then `broadcast_from!`s the chunk to the topic so subscribed PC clients
      (`:pc_admin` role) can pull bytes for downstream STT (milestone D1b).

  Future: task 1.5 will add command relay from PC admins (`down` direction).
  """

  use Phoenix.Channel

  alias Evenglass.{Events, RateLimit, Sessions}

  @join_scale_ms 60_000
  @join_limit 10

  # Audio metadata is flushed to the events table once this much real time
  # has elapsed since the last flush, capping the DB write rate at ≈1Hz/device.
  @audio_meta_window_ms 1_000

  @impl true
  def join("g2:device:" <> id, _payload, %{assigns: %{role: :device, device_id: my_id}} = socket)
      when id == my_id do
    case RateLimit.hit("chan-join:device:#{my_id}", @join_scale_ms, @join_limit) do
      {:allow, _count} ->
        session = Sessions.touch_session_by_device_id!(my_id)

        socket =
          socket
          |> assign(:session_id, session.id)
          |> assign(:audio_acc, fresh_audio_acc())

        {:ok, %{role: "device", device_id: my_id}, socket}

      {:deny, retry_after_ms} ->
        {:error, %{reason: "rate_limited", retry_after_ms: retry_after_ms}}
    end
  end

  def join("g2:device:" <> id, _payload, %{assigns: %{role: :pc_admin}} = socket) do
    {:ok, %{role: "pc_admin", device_id: id}, socket}
  end

  def join(_topic, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: true, ts: System.system_time(:millisecond)}}, socket}
  end

  def handle_in(
        "audio_chunk",
        payload,
        %{assigns: %{role: :device, session_id: session_id}} = socket
      ) do
    socket = accumulate_audio(socket, payload, session_id)

    # Re-emit to other subscribers on the same topic so PC clients can ingest.
    # `broadcast_from!` skips the sender, so the Hub App doesn't echo to itself.
    broadcast_from!(socket, "audio_chunk", payload)

    {:noreply, socket}
  end

  def handle_in("audio_chunk", _payload, socket) do
    {:reply, {:error, %{reason: "audio_chunk_device_only"}}, socket}
  end

  ## Audio accumulator ────────────────────────────────────────────────────────

  defp fresh_audio_acc do
    %{frames: 0, bytes: 0, sample_rate: nil, format: nil, window_started_ms: nil}
  end

  defp accumulate_audio(socket, payload, session_id) do
    now_ms = System.monotonic_time(:millisecond)
    acc = socket.assigns.audio_acc

    next = %{
      frames: acc.frames + read_int(payload, "frames", 1),
      bytes: acc.bytes + read_int(payload, "bytes", 0),
      sample_rate: read_int(payload, "sample_rate", 16_000),
      format: Map.get(payload, "format", "pcm_s16le"),
      window_started_ms: acc.window_started_ms || now_ms
    }

    if now_ms - next.window_started_ms >= @audio_meta_window_ms do
      flush_audio_meta!(session_id, next, now_ms)
      assign(socket, :audio_acc, fresh_audio_acc())
    else
      assign(socket, :audio_acc, next)
    end
  end

  defp flush_audio_meta!(session_id, acc, now_ms) do
    Events.create_event!(%{
      session_id: session_id,
      direction: "up",
      type: "audio_meta",
      payload: %{
        frames: acc.frames,
        bytes: acc.bytes,
        sample_rate: acc.sample_rate,
        format: acc.format,
        window_ms: now_ms - acc.window_started_ms
      }
    })
  end

  defp read_int(payload, key, default) do
    case Map.get(payload, key) do
      n when is_integer(n) and n >= 0 -> n
      _ -> default
    end
  end
end
