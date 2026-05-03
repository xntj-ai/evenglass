defmodule EvenglassWeb.Admin.DeviceShowLiveTest do
  use EvenglassWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Evenglass.AccountsFixtures
  import Evenglass.DevicesFixtures

  describe "GET /admin/devices/:id" do
    setup %{conn: conn} do
      device =
        device_fixture(%{glasses_serial: "G2-DETAIL-#{System.unique_integer([:positive])}"})

      conn = log_in_pc_user(conn, admin_pc_user_fixture())
      %{conn: conn, device: device}
    end

    test "renders metadata for an active device", %{conn: conn, device: device} do
      {:ok, _lv, html} = live(conn, ~p"/admin/devices/#{device.id}")

      assert html =~ device.id
      assert html =~ device.glasses_serial
      assert html =~ "active"
      assert html =~ "Revoke device"
    end

    test "revoke button clears jti and marks the row revoked", %{conn: conn, device: device} do
      device = Evenglass.Devices.set_jti!(device, "some-jti")

      {:ok, lv, _} = live(conn, ~p"/admin/devices/#{device.id}")

      lv |> element("button", "Revoke device") |> render_click()

      reloaded = Evenglass.Devices.get_device!(device.id)
      assert reloaded.revoked_at
      refute reloaded.jti

      assert render(lv) =~ "revoked at"
      refute render(lv) =~ "Revoke device"
    end

    test "revoke broadcasts a disconnect on the device's user_socket topic", %{
      conn: conn,
      device: device
    } do
      _device = Evenglass.Devices.set_jti!(device, "some-jti")

      # Subscribe to the topic any active Hub App socket would be listening on.
      # This is the security-critical side-effect of revocation; without it,
      # a 2h channel_token survives the row update.
      EvenglassWeb.Endpoint.subscribe("user_socket:#{device.id}")

      {:ok, lv, _} = live(conn, ~p"/admin/devices/#{device.id}")
      lv |> element("button", "Revoke device") |> render_click()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 1_000
    end

    test "redirects when device id is unknown", %{conn: conn} do
      missing = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/admin/devices"}}} =
               live(conn, ~p"/admin/devices/#{missing}")
    end
  end
end
