defmodule EvenglassWeb.G2ChannelTest do
  @moduledoc """
  Channel-level tests for `EvenglassWeb.G2Channel`.

  Existing rate-limit + socket connect tests live in
  `EvenglassWeb.RateLimitTest`. This module focuses on the message contracts:
  audio_chunk authorization, the new `start_audio`/`stop_audio` PC→device
  bridge (D1b-1), and PC admin's ability to monitor any device topic.
  """

  use EvenglassWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Evenglass.AccountsFixtures
  import Evenglass.DevicesFixtures

  alias Evenglass.Auth.Token

  @endpoint EvenglassWeb.Endpoint

  describe "audio command bridge — start_audio / stop_audio" do
    setup do
      device = device_fixture()
      device_socket = build_device_socket(device.id)
      pc_user = admin_pc_user_fixture()
      pc_socket = build_pc_admin_socket(pc_user.id)

      {:ok, _, joined_device} =
        subscribe_and_join(device_socket, EvenglassWeb.G2Channel, "g2:device:#{device.id}", %{})

      {:ok, _, joined_pc} =
        subscribe_and_join(pc_socket, EvenglassWeb.G2Channel, "g2:device:#{device.id}", %{})

      %{
        device: device,
        device_channel: joined_device,
        pc_channel: joined_pc
      }
    end

    test "PC admin push start_audio is broadcast on the topic", %{
      device_channel: device_chan,
      pc_channel: pc_chan
    } do
      # handle_in returns {:noreply, socket}, so no Phoenix.Socket.Reply is
      # expected — the contract is purely the side-effect of broadcasting.
      Phoenix.ChannelTest.push(pc_chan, "start_audio", %{"seq" => 7})
      assert_broadcast "start_audio", %{"seq" => 7}, 500

      # Sanity: device channel is still alive after the bridge fires.
      ping_ref = Phoenix.ChannelTest.push(device_chan, "ping", %{})
      assert_reply ping_ref, :ok, %{pong: true}, 500
    end

    test "PC admin push stop_audio is broadcast to device", %{pc_channel: pc_chan} do
      _ref = Phoenix.ChannelTest.push(pc_chan, "stop_audio", %{})
      assert_broadcast "stop_audio", %{}, 500
    end

    test "non-integer seq is stripped from the forwarded payload", %{pc_channel: pc_chan} do
      _ref = Phoenix.ChannelTest.push(pc_chan, "start_audio", %{"seq" => "not-a-number", "evil" => "drop"})
      assert_broadcast "start_audio", forwarded, 500
      assert forwarded == %{}
    end

    test "device role pushing start_audio is rejected with pc_admin_only", %{
      device_channel: device_chan
    } do
      ref = Phoenix.ChannelTest.push(device_chan, "start_audio", %{})
      assert_reply ref, :error, %{reason: "pc_admin_only"}, 500
    end

    test "PC admin pushing audio_chunk is rejected with audio_chunk_device_only", %{
      pc_channel: pc_chan
    } do
      ref =
        Phoenix.ChannelTest.push(pc_chan, "audio_chunk", %{
          "seq" => 1,
          "pcm_b64" => "",
          "frames" => 1,
          "bytes" => 3200,
          "sample_rate" => 16_000,
          "format" => "pcm_s16le"
        })

      assert_reply ref, :error, %{reason: "audio_chunk_device_only"}, 500
    end
  end

  describe "PC admin channel_token end-to-end" do
    test "signed pc_admin channel_token connects + joins arbitrary device topic" do
      pc_user = admin_pc_user_fixture()
      device = device_fixture()
      ct = Token.sign_channel_token(%{pc_user_id: pc_user.id, role: :pc_admin})

      assert {:ok, %Phoenix.Socket{} = socket} =
               Phoenix.ChannelTest.connect(EvenglassWeb.UserSocket, %{"token" => ct})

      assert socket.assigns.pc_user_id == pc_user.id
      assert socket.assigns.role == :pc_admin

      assert {:ok, reply, _joined} =
               subscribe_and_join(
                 socket,
                 EvenglassWeb.G2Channel,
                 "g2:device:#{device.id}",
                 %{}
               )

      assert reply == %{role: "pc_admin", device_id: device.id}
    end
  end

  ## Helpers ────────────────────────────────────────────────────────────────

  defp build_device_socket(device_id) do
    socket(EvenglassWeb.UserSocket, "user_socket:#{device_id}", %{
      role: :device,
      device_id: device_id
    })
  end

  defp build_pc_admin_socket(pc_user_id) do
    socket(EvenglassWeb.UserSocket, "pc_socket:#{pc_user_id}", %{
      role: :pc_admin,
      pc_user_id: pc_user_id
    })
  end
end
