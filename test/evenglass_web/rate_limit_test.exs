defmodule EvenglassWeb.RateLimitTest do
  @moduledoc """
  Wiring tests for the 5 endpoints rate-limited in milestone-C 1.6.

  Each test pre-fills its own bucket (Hammer 7 ETS table is process-global, so
  isolation is achieved by giving every case a unique key), then issues one
  more request and asserts the deny path. async: false avoids surprising
  scheduling interactions on the shared ETS table.
  """

  use EvenglassWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Evenglass.AccountsFixtures

  alias Evenglass.{Accounts, Devices, RateLimit}
  alias Evenglass.Auth.Token

  @endpoint EvenglassWeb.Endpoint

  describe "POST /api/g2/enroll — 5/60s/IP" do
    test "returns 429 on the 6th attempt from the same IP", %{conn: conn} do
      ip = unique_ip()

      attempt = fn ->
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> post(~p"/api/g2/enroll", %{"code" => "wrong-code"})
      end

      for _ <- 1..5 do
        c = attempt.()
        # Invalid enrollment code path → 401, not yet limited.
        assert c.status == 401
        assert json_response(c, 401)["error"] == "invalid_or_expired_code"
      end

      c = attempt.()
      assert c.status == 429
      assert json_response(c, 429)["error"] == "rate_limited"
      assert [_retry_after] = get_resp_header(c, "retry-after")
    end

    test "different IPs do not share the same bucket", %{conn: conn} do
      ip_a = unique_ip()
      ip_b = unique_ip()

      # Burn IP A's quota.
      for _ <- 1..6 do
        conn
        |> put_req_header("x-forwarded-for", ip_a)
        |> post(~p"/api/g2/enroll", %{"code" => "wrong-code"})
      end

      # IP B still has its full allowance.
      c =
        conn
        |> put_req_header("x-forwarded-for", ip_b)
        |> post(~p"/api/g2/enroll", %{"code" => "wrong-code"})

      assert c.status == 401
    end
  end

  describe "POST /api/g2/events — 600/60s/device" do
    test "returns 429 once the device bucket is full", %{conn: conn} do
      %{device: device, token: token} = setup_authenticated_device()

      # Pre-fill the bucket to its limit, then the 601st hit is denied.
      key = "events:device:#{device.id}"
      Enum.each(1..600, fn _ -> RateLimit.hit(key, 60_000, 600) end)

      c =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/g2/events", %{"type" => "ping"})

      assert c.status == 429
      assert json_response(c, 429)["error"] == "rate_limited"
    end
  end

  describe "POST /api/g2/commands — 120/60s/user" do
    test "returns 429 once the user bucket is full", %{conn: conn} do
      pc_user = totp_enrolled_pc_user()
      conn = log_in_pc_user(conn, pc_user)
      device = create_device()

      key = "commands:user:#{pc_user.id}"
      Enum.each(1..120, fn _ -> RateLimit.hit(key, 60_000, 120) end)

      c =
        post(conn, ~p"/api/g2/commands", %{
          "device_id" => device.id,
          "type" => "ping"
        })

      assert c.status == 429
      assert json_response(c, 429)["error"] == "rate_limited"
    end
  end

  describe "G2Channel join — 10/60s/device" do
    test "rejects the 11th join with reason rate_limited" do
      device_id = Ecto.UUID.generate()

      socket =
        socket(EvenglassWeb.UserSocket, "user_socket:#{device_id}", %{
          role: :device,
          device_id: device_id
        })

      # 10 joins succeed.
      for _ <- 1..10 do
        assert {:ok, _, _joined_socket} =
                 subscribe_and_join(socket, EvenglassWeb.G2Channel, "g2:device:#{device_id}", %{})
      end

      assert {:error, %{reason: "rate_limited"}} =
               subscribe_and_join(socket, EvenglassWeb.G2Channel, "g2:device:#{device_id}", %{})
    end
  end

  describe "UserSocket.connect — real channel_token path" do
    test "valid channel_token assigns device_id + role and lets G2Channel join own topic" do
      %{device: device} = setup_authenticated_device()
      ct = Token.sign_channel_token(%{device_id: device.id, role: :device})

      assert {:ok, %Phoenix.Socket{} = socket} =
               Phoenix.ChannelTest.connect(EvenglassWeb.UserSocket, %{"token" => ct})

      assert socket.assigns.device_id == device.id
      assert socket.assigns.role == :device

      assert {:ok, _, _} =
               subscribe_and_join(socket, EvenglassWeb.G2Channel, "g2:device:#{device.id}", %{})
    end

    test "device A's channel_token cannot join device B's topic" do
      %{device: dev_a} = setup_authenticated_device()
      %{device: dev_b} = setup_authenticated_device()
      ct_a = Token.sign_channel_token(%{device_id: dev_a.id, role: :device})

      assert {:ok, socket} =
               Phoenix.ChannelTest.connect(EvenglassWeb.UserSocket, %{"token" => ct_a})

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, EvenglassWeb.G2Channel, "g2:device:#{dev_b.id}", %{})
    end

    test "missing or malformed token rejects connect" do
      assert :error = Phoenix.ChannelTest.connect(EvenglassWeb.UserSocket, %{})

      assert :error =
               Phoenix.ChannelTest.connect(EvenglassWeb.UserSocket, %{"token" => "garbage"})
    end
  end

  describe "POST /pc_users/log-in — 5/15min/IP+email" do
    test "returns rate-limit flash on the 6th attempt from same IP+email", %{conn: conn} do
      pc_user = pc_user_fixture()
      _pc_user = set_password(pc_user)
      ip = unique_ip()

      attempt = fn ->
        conn
        |> put_req_header("x-forwarded-for", ip)
        |> post(~p"/pc_users/log-in", %{
          "pc_user" => %{"email" => pc_user.email, "password" => "wrong-password"}
        })
      end

      for _ <- 1..5 do
        c = attempt.()
        assert Phoenix.Flash.get(c.assigns.flash, :error) == "Invalid email or password"
      end

      c = attempt.()
      assert Phoenix.Flash.get(c.assigns.flash, :error) =~ "Too many login attempts"
    end
  end

  ## Helpers

  defp unique_ip do
    "203.0.113.#{rem(System.unique_integer([:positive]), 254) + 1}"
  end

  defp create_device do
    Devices.create_device!(%{glasses_serial: "G-#{System.unique_integer([:positive])}"})
  end

  defp setup_authenticated_device do
    device = create_device()
    jti = "jti-#{System.unique_integer([:positive])}"
    device = Devices.set_jti!(device, jti)
    token = Token.sign_device_token(%{device_id: device.id, jti: jti})
    %{device: device, token: token}
  end

  defp totp_enrolled_pc_user do
    pc_user = pc_user_fixture() |> set_password()
    {:ok, pc_user} = Accounts.setup_totp(pc_user)
    otp = NimbleTOTP.verification_code(pc_user.totp_secret)
    {:ok, pc_user} = Accounts.confirm_totp(pc_user, otp)
    pc_user
  end
end
